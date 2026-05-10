# Guía paso a paso — Instalación local

Esta guía está pensada para alguien que **nunca implementó este tipo de capa cross-db** y quiere correr el proyecto en su máquina antes de adaptarlo a un entorno productivo.

Si ya tenés Postgres y dbt instalados, podés saltar al [paso 4](#4-clonar-el-proyecto).

---

## Tabla de contenidos

1. [Prerrequisitos](#1-prerrequisitos)
2. [Instalar PostgreSQL local](#2-instalar-postgresql-local)
3. [Instalar Python y dbt](#3-instalar-python-y-dbt)
4. [Clonar el proyecto](#4-clonar-el-proyecto)
5. [Configurar `profiles.yml`](#5-configurar-profilesyml)
6. [Verificar conexión y dependencias](#6-verificar-conexión-y-dependencias)
7. [Verificar la capa de compatibilidad](#7-verificar-la-capa-de-compatibilidad)
8. [Correr los modelos de ejemplo](#8-correr-los-modelos-de-ejemplo)
9. [Correr el mismo proyecto contra Redshift](#9-correr-el-mismo-proyecto-contra-redshift)
10. [Validar paridad de resultados](#10-validar-paridad-de-resultados)
11. [Adaptar a tu proyecto productivo](#11-adaptar-a-tu-proyecto-productivo)
12. [Troubleshooting](#12-troubleshooting)

---

## 1. Prerrequisitos

| Herramienta | Versión mínima | Cómo verificar |
|---|---|---|
| Python | 3.9 | `python3 --version` |
| pip | reciente | `pip3 --version` |
| Git | cualquiera | `git --version` |
| PostgreSQL | 14 | `psql --version` |

En **WSL Ubuntu / Linux**:

```bash
sudo apt update
sudo apt install -y python3 python3-pip python3-venv git
```

En **macOS**:

```bash
brew install python git
```

---

## 2. Instalar PostgreSQL local

### Opción A — WSL Ubuntu / Linux nativo

```bash
sudo apt install -y postgresql postgresql-contrib
sudo service postgresql start
```

Crear usuario y base:

```bash
sudo -u postgres psql
```

Dentro del prompt `postgres=#`:

```sql
CREATE USER dbt_dev WITH PASSWORD 'dbt_dev_pwd' SUPERUSER;
CREATE DATABASE dbt_dev OWNER dbt_dev;
\q
```

> Le damos `SUPERUSER` solo para que pueda crear funciones sin pelear con permisos. En productivo NO se hace así.

Probar la conexión:

```bash
psql -h localhost -U dbt_dev -d dbt_dev -c "select version();"
```

### Opción B — macOS

```bash
brew install postgresql@16
brew services start postgresql@16
createuser -s dbt_dev
createdb -O dbt_dev dbt_dev
```

### Opción C — Docker (si no querés instalar nada en el host)

```bash
docker run -d --name pg-dbt-local \
  -e POSTGRES_USER=dbt_dev \
  -e POSTGRES_PASSWORD=dbt_dev_pwd \
  -e POSTGRES_DB=dbt_dev \
  -p 5432:5432 \
  postgres:16
```

---

## 3. Instalar Python y dbt

```bash
# Crear entorno virtual fuera del proyecto (que vamos a clonar después)
mkdir -p ~/dbt-workspace && cd ~/dbt-workspace
python3 -m venv .venv
source .venv/bin/activate

# Instalar dbt
pip install --upgrade pip
pip install "dbt-core>=1.8" "dbt-postgres>=1.8" "dbt-redshift>=1.8"

dbt --version
```

> A partir de acá, **siempre que abras una terminal nueva, primero**: `source ~/dbt-workspace/.venv/bin/activate`

---

## 4. Clonar el proyecto

```bash
cd ~/dbt-workspace
git clone https://github.com/alejandrogenovese/fix_postgres_redshift_dbt.git galicia_dbt_compat
cd galicia_dbt_compat
```

Verificar la estructura:

```bash
ls -la
```

Tendrías que ver:

```
.gitignore
README.md
INSTALACION.md
dbt_project.yml
packages.yml
profiles.yml.example
analyses/
macros/
models/
seeds/
snapshots/
tests/
```

---

## 5. Configurar `profiles.yml`

dbt no lee credenciales del proyecto: las lee de `~/.dbt/profiles.yml` (fuera del repo, para no commitear secretos por accidente).

```bash
mkdir -p ~/.dbt
cp profiles.yml.example ~/.dbt/profiles.yml
```

Editá `~/.dbt/profiles.yml` y dejá al menos el bloque `dev_postgres`. Si todavía no usás Redshift, podés borrar el bloque `dev_redshift` o dejarlo con las env vars vacías (no se va a romper hasta que intentes correr contra ese target).

```yaml
galicia_dbt_compat:
  target: dev_postgres
  outputs:
    dev_postgres:
      type: postgres
      host: localhost
      port: 5432
      user: dbt_dev
      password: dbt_dev_pwd
      dbname: dbt_dev
      schema: dbt_dev
      threads: 4
      sslmode: disable
```

---

## 6. Verificar conexión y dependencias

Desde la raíz del proyecto:

```bash
# Instalar dependencias dbt (dbt-utils)
dbt deps

# Verificar conexión Postgres
dbt debug
```

Tiene que decir `All checks passed!`.

Si algo falla, ir directo a [Troubleshooting](#12-troubleshooting).

---

## 7. Verificar la capa de compatibilidad

El `dbt_project.yml` tiene un hook `on-run-start` que instala las funciones SQL automáticamente cuando corrés cualquier comando dbt contra Postgres. Verificación manual:

```bash
dbt run-operation install_postgres_compat
```

Esperás ver:

```
✅ Capa de compatibilidad Postgres instalada
```

Verificar directamente en Postgres:

```bash
psql -h localhost -U dbt_dev -d dbt_dev <<'EOF'
\df getdate
\df dateadd
\df nvl
\df json_extract_path_text
EOF
```

Test funcional rápido:

```bash
psql -h localhost -U dbt_dev -d dbt_dev <<'EOF'
SELECT
  getdate() AS ahora,
  dateadd('day', 7, getdate()) AS en_7_dias,
  datediff('day', '2025-01-01'::timestamp, '2025-12-31'::timestamp) AS dias_del_anio,
  nvl(NULL, 'fallback') AS nvl_test;
EOF
```

---

## 8. Correr los modelos de ejemplo

```bash
# Cargar datos de prueba
dbt seed --select compat_test_users

# Correr los 8 modelos de ejemplo
dbt run --select tag:compat_examples

# Correr los tests asociados
dbt test --select tag:compat_examples
```

Si todo pasó:

```
Completed successfully
Done. PASS=N WARN=0 ERROR=0 SKIP=0 TOTAL=N
```

Para inspeccionar los datos generados:

```bash
psql -h localhost -U dbt_dev -d dbt_dev <<'EOF'
SELECT * FROM dbt_dev.example_dates LIMIT 3;
SELECT * FROM dbt_dev.example_nulls LIMIT 3;
SELECT * FROM dbt_dev.example_aggregations;
EOF
```

> Recomendación: leer los `models/examples/example_*.sql` en el orden que sugiere `models/examples/schema.yml`. Los comentarios pedagógicos cubren cada macro.

---

## 9. Correr el mismo proyecto contra Redshift

Una vez que validaste en Postgres, hacé exactamente lo mismo apuntando al target Redshift:

```bash
export REDSHIFT_HOST=galicia-dev.xxxx.redshift.amazonaws.com
export REDSHIFT_USER=tu_usuario
export REDSHIFT_PWD='tu_password'

dbt debug --target dev_redshift   # verificar conexión primero
dbt seed --select compat_test_users --target dev_redshift
dbt run --select tag:compat_examples --target dev_redshift
dbt test --select tag:compat_examples --target dev_redshift
```

Si los modelos compilaron y los tests pasan en ambos motores → la capa cross-db está cumpliendo su función.

> Tip: agregar `--target dev_redshift` a cada comando se vuelve molesto. Alternativa: cambiar `target: dev_postgres` a `target: dev_redshift` en `~/.dbt/profiles.yml` cuando trabajés mayormente contra Redshift.

---

## 10. Validar paridad de resultados

```bash
mkdir -p compare/postgres compare/redshift

# Postgres
for m in example_dates example_nulls example_strings example_regex \
         example_aggregations example_json example_unnest example_types; do
  psql -h localhost -U dbt_dev -d dbt_dev -c \
    "\COPY (select * from dbt_dev.${m} order by 1) TO 'compare/postgres/${m}.csv' WITH CSV HEADER"
done

# Redshift
for m in example_dates example_nulls example_strings example_regex \
         example_aggregations example_json example_unnest example_types; do
  psql "host=$REDSHIFT_HOST port=5439 dbname=dev user=$REDSHIFT_USER password=$REDSHIFT_PWD sslmode=require" -c \
    "\COPY (select * from ${USER}_dev.${m} order by 1) TO 'compare/redshift/${m}.csv' WITH CSV HEADER"
done

# Diff
diff -r compare/postgres compare/redshift | less
```

Diferencias esperadas (timestamps de run, precisión numérica, HLL approx) están documentadas inline en cada `example_*.sql`.

---

## 11. Adaptar a tu proyecto productivo

Cuando termines de validar acá, integrar en tu proyecto dbt principal:

### Opción A — Copiar las macros (rápido, no auto-actualiza)

```bash
cp -r macros/compat /tu/proyecto/macros/
cp -r macros/cross_db /tu/proyecto/macros/
```

Y agregar al `dbt_project.yml` de tu proyecto:

```yaml
on-run-start:
  - "{{ install_postgres_compat() }}"
```

### Opción B — Como package dbt (productivo, recomendado)

En el `packages.yml` de tu proyecto:

```yaml
packages:
  - git: "https://github.com/alejandrogenovese/fix_postgres_redshift_dbt.git"
    revision: main   # o un tag específico cuando saques release
```

Después: `dbt deps`.

> ⚠ Con la opción B las macros quedan namespaced. `{{ median(col) }}` se transforma en `{{ galicia_dbt_compat.median(col) }}` (o como esté seteado el name del package). En el `dispatch` de dbt podés re-exportarlas sin namespace si querés.

---

## 12. Troubleshooting

### `function getdate() does not exist`

La capa de compatibilidad no se instaló. Verificá:

1. Que `on-run-start` esté en `dbt_project.yml`.
2. Que el usuario tenga permiso para crear funciones (debe ser owner de la DB o superuser).
3. Corré manualmente: `dbt run-operation install_postgres_compat`.

### `permission denied for schema public`

```bash
sudo -u postgres psql -c "ALTER DATABASE dbt_dev OWNER TO dbt_dev;"
sudo -u postgres psql -d dbt_dev -c "GRANT ALL ON SCHEMA public TO dbt_dev;"
```

### El `on-run-start` corre cada vez y es lento

Las funciones usan `CREATE OR REPLACE`, así que es idempotente y rápido (~100ms). Si te molesta, comentar el hook y correr `dbt run-operation install_postgres_compat` solo cuando hagas pull de cambios al repo.

### Error en Redshift: `syntax error at or near 'concat_n'`

`concat_n` es el nombre de la macro Jinja, no de una función SQL. Si ves ese error es porque te olvidaste las llaves `{{ }}`.

Mal: `select concat_n(first_name, ' ', last_name) from users`
Bien: `select {{ concat_n('first_name', "' '", 'last_name') }} from users`

### `dbt seed` falla con encoding

Asegurate que los CSV estén en UTF-8:

```bash
file seeds/*.csv
```

Tendrían que decir `UTF-8 Unicode text`.

### Las funciones de Postgres se "perdieron"

Si dropeaste y recreaste la DB, reinstalalas:

```bash
dbt run-operation install_postgres_compat
```

### `dbt deps` falla con `git not found`

```bash
sudo apt install git    # WSL/Linux
brew install git        # macOS
```

### `dbt debug` falla contra Redshift por SSL

Verificar que `sslmode: require` esté en el bloque `dev_redshift` del profiles.yml.

### Quiero deshacer todo en Postgres local

```bash
psql -h localhost -U dbt_dev -d dbt_dev <<'EOF'
DROP SCHEMA dbt_dev CASCADE;
CREATE SCHEMA dbt_dev;

DROP FUNCTION IF EXISTS getdate() CASCADE;
DROP FUNCTION IF EXISTS dateadd(text, int, timestamp) CASCADE;
DROP FUNCTION IF EXISTS dateadd(text, int, date) CASCADE;
DROP FUNCTION IF EXISTS datediff(text, timestamp, timestamp) CASCADE;
DROP FUNCTION IF EXISTS datediff(text, date, date) CASCADE;
DROP FUNCTION IF EXISTS add_months(timestamp, int) CASCADE;
DROP FUNCTION IF EXISTS add_months(date, int) CASCADE;
DROP FUNCTION IF EXISTS months_between(timestamp, timestamp) CASCADE;
DROP FUNCTION IF EXISTS last_day(timestamp) CASCADE;
DROP FUNCTION IF EXISTS last_day(date) CASCADE;
DROP FUNCTION IF EXISTS convert_timezone(text, text, timestamp) CASCADE;
DROP FUNCTION IF EXISTS convert_timezone(text, timestamptz) CASCADE;
DROP FUNCTION IF EXISTS trunc(timestamp) CASCADE;
DROP FUNCTION IF EXISTS nvl(anyelement, anyelement) CASCADE;
DROP FUNCTION IF EXISTS nvl2(anyelement, anyelement, anyelement) CASCADE;
DROP FUNCTION IF EXISTS len(text) CASCADE;
DROP FUNCTION IF EXISTS len(varchar) CASCADE;
DROP FUNCTION IF EXISTS charindex(text, text) CASCADE;
DROP FUNCTION IF EXISTS regexp_count(text, text) CASCADE;
DROP FUNCTION IF EXISTS regexp_substr(text, text) CASCADE;
DROP FUNCTION IF EXISTS regexp_instr(text, text) CASCADE;
DROP FUNCTION IF EXISTS is_valid_json_pg(text) CASCADE;
DROP FUNCTION IF EXISTS is_valid_json_array_pg(text) CASCADE;
DROP FUNCTION IF EXISTS json_extract_path_text(text, text) CASCADE;
DROP FUNCTION IF EXISTS json_extract_path_text(text, text, text) CASCADE;
DROP FUNCTION IF EXISTS json_extract_path_text(text, text, text, text) CASCADE;
DROP FUNCTION IF EXISTS json_extract_array_element_text(text, int) CASCADE;
DROP FUNCTION IF EXISTS json_array_length(text) CASCADE;
EOF
```

---

## Próximos pasos

Cuando ya validaste localmente:

1. **Sumar el package al proyecto dbt productivo**: opción B del paso 11.
2. **SQLFluff con reglas custom**: enforcement de las convenciones (no `TEXT`, no operadores `->>`, etc.).
3. **CI**: pipeline que corra `dbt run` y `dbt test` en ambos targets contra el mismo set de modelos críticos.
4. **Sampling de paridad**: extender `export_compat_results.sql` para muestreo aleatorio en modelos de alto volumen.

---

## Referencias

- [Documentación oficial dbt](https://docs.getdbt.com)
- [dbt cross-db macros](https://docs.getdbt.com/reference/dbt-jinja-functions/cross-database-macros)
- [dbt-utils](https://github.com/dbt-labs/dbt-utils)
