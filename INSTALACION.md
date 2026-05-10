# Guía paso a paso — Instalación

Setup desde cero. El proyecto solo necesita Python+dbt y una base Postgres accesible. Cómo proveer esos ingredientes (host, contenedor, RDS, etc.) está fuera del alcance de esta guía.

## Tabla de contenidos

1. [Requisitos](#1-requisitos)
2. [Preparar Postgres](#2-preparar-postgres)
3. [Instalar Python y dbt](#3-instalar-python-y-dbt)
4. [Clonar el proyecto](#4-clonar-el-proyecto)
5. [Configurar `profiles.yml`](#5-configurar-profilesyml)
6. [Verificar la capa de compatibilidad](#6-verificar-la-capa-de-compatibilidad)
7. [Correr el pipeline](#7-correr-el-pipeline)
8. [Validar paridad contra Redshift](#8-validar-paridad-contra-redshift)
9. [Usar como package en otro proyecto dbt](#9-usar-como-package-en-otro-proyecto-dbt)
10. [Troubleshooting](#10-troubleshooting)

---

## 1. Requisitos

| Herramienta | Versión | Verificar |
|---|---|---|
| Python | 3.9+ | `python3 --version` |
| pip | reciente | `pip3 --version` |
| Git | cualquiera | `git --version` |
| PostgreSQL | 14+ | accesible por red, con permisos de DDL |

Plataformas soportadas: macOS, Linux nativo, WSL Ubuntu, Windows nativo.

---

## 2. Preparar Postgres

Tenés que tener una base Postgres a la cual dbt pueda conectarse y crear schemas. Algunas opciones:

### Postgres nativo en la máquina

```bash
# Ubuntu/Debian/WSL
sudo apt install -y postgresql postgresql-contrib

# macOS
brew install postgresql@16
brew services start postgresql@16
```

Crear usuario y base:

```bash
sudo -u postgres psql <<SQL
CREATE USER dbt_dev WITH PASSWORD 'dbt_dev_pwd' SUPERUSER;
CREATE DATABASE dbt_dev OWNER dbt_dev;
SQL
```

### Postgres en un contenedor (Docker o Podman)

```bash
# Docker
docker run -d --name pg-dbt \
  -e POSTGRES_USER=dbt_dev \
  -e POSTGRES_PASSWORD=dbt_dev_pwd \
  -e POSTGRES_DB=dbt_dev \
  -p 5432:5432 \
  postgres:16

# Podman (mismo comando, reemplazando docker por podman)
podman run -d --name pg-dbt \
  -e POSTGRES_USER=dbt_dev \
  -e POSTGRES_PASSWORD=dbt_dev_pwd \
  -e POSTGRES_DB=dbt_dev \
  -p 5432:5432 \
  postgres:16
```

### Postgres remoto (RDS, gerenciado, etc.)

Solo necesitás:
- host alcanzable
- credenciales
- permiso para crear/dropear schemas (porque dbt los maneja)

### Verificación

```bash
psql -h <host> -U <user> -d <db> -c "select version();"
```

Si conecta y muestra la versión, está OK.

---

## 3. Instalar Python y dbt

```bash
# Crear venv en el proyecto (o donde prefieras)
python3 -m venv .venv
source .venv/bin/activate           # Linux/macOS/WSL
# .venv\Scripts\activate            # Windows PowerShell

pip install --upgrade pip
pip install "dbt-core>=1.8" "dbt-postgres>=1.8" "dbt-redshift>=1.8"

dbt --version
```

Salida esperada (algo similar):
```
Core:
  - installed: 1.8.x
Plugins:
  - postgres: 1.8.x
  - redshift: 1.8.x
```

> Cada vez que abras una terminal nueva, primero: `source .venv/bin/activate`.

---

## 4. Clonar el proyecto

```bash
git clone https://github.com/alejandrogenovese/fix_postgres_redshift_dbt.git
cd fix_postgres_redshift_dbt
```

Verificar la estructura:

```bash
ls -la
# Tendría que ver: dbt_project.yml, packages.yml, profiles.yml.example,
# README.md, INSTALACION.md, macros/, models/, seeds/, ...
```

---

## 5. Configurar `profiles.yml`

dbt lee credenciales desde `~/.dbt/profiles.yml` (fuera del repo).

```bash
mkdir -p ~/.dbt
cp profiles.yml.example ~/.dbt/profiles.yml
```

El template usa `env_var('POSTGRES_HOST', 'localhost')` con fallback. Hay dos formas de configurarlo:

### Opción A — Editar `~/.dbt/profiles.yml` directamente

Reemplazar el bloque `env_var(...)` por los valores fijos de tu entorno:

```yaml
dev_postgres:
  type: postgres
  host: localhost           # o el host de tu Postgres
  port: 5432
  user: dbt_dev
  password: dbt_dev_pwd
  dbname: dbt_dev
  schema: dbt_dev
  threads: 4
  sslmode: disable
```

### Opción B — Exportar env vars (recomendado en CI o servidores)

Dejar `profiles.yml` con los `env_var(...)` y exportar antes de correr dbt:

```bash
export POSTGRES_HOST=localhost
export POSTGRES_PORT=5432
export POSTGRES_USER=dbt_dev
export POSTGRES_PASSWORD=dbt_dev_pwd
export POSTGRES_DB=dbt_dev
export POSTGRES_SCHEMA=dbt_dev
```

> Si tu Postgres está en un contenedor y dbt corre en el host, el host suele ser `localhost` y el puerto el que mapeaste al ejecutar `docker run -p 5432:5432`. Si los dos corren en contenedores conectados por red, el host es el nombre del servicio o el alias de red.

### Instalar dependencias dbt y verificar

```bash
dbt deps
dbt debug
```

Salida esperada al final:
```
Connection test: [OK connection ok]
All checks passed!
```

---

## 6. Verificar la capa de compatibilidad

El `dbt_project.yml` tiene un hook `on-run-start` que instala automáticamente las funciones SQL en Postgres cuando ejecutás cualquier comando dbt. Verificación manual:

```bash
dbt run-operation install_postgres_compat
```

Esperás:
```
✅ Capa de compatibilidad Postgres instalada
```

Verificar en Postgres que las funciones existan:

```bash
psql -h $POSTGRES_HOST -U $POSTGRES_USER -d $POSTGRES_DB <<'EOF'
\df getdate
\df dateadd
\df nvl
\df json_extract_path_text

SELECT
  getdate() AS ahora,
  dateadd('day', 7, getdate()) AS en_7_dias,
  nvl(NULL::text, 'fallback') AS nvl_test;
EOF
```

---

## 7. Correr el pipeline

```bash
# Cargar seed con datos de prueba
dbt seed --select compat_test_users

# Correr los 8 modelos de ejemplo
dbt run --select tag:compat_examples

# Correr los tests
dbt test --select tag:compat_examples
```

Salida esperada al final del `dbt test`:
```
Completed successfully
Done. PASS=N WARN=0 ERROR=0 SKIP=0 TOTAL=N
```

Inspeccionar resultados:

```bash
psql -h $POSTGRES_HOST -U $POSTGRES_USER -d $POSTGRES_DB <<'EOF'
\dt dbt_dev.*
SELECT * FROM dbt_dev.example_dates LIMIT 3;
SELECT * FROM dbt_dev.example_aggregations;
EOF
```

> Recomendación: leer los modelos en `models/examples/` en orden — los comentarios pedagógicos cubren cada macro.

---

## 8. Validar paridad contra Redshift

Una vez validado en Postgres, repetir el mismo pipeline contra Redshift. Exportar credenciales:

```bash
export REDSHIFT_HOST=tu-cluster.xxxx.redshift.amazonaws.com
export REDSHIFT_USER=tu_usuario
export REDSHIFT_PWD='tu_password'
export REDSHIFT_DB=dev
export REDSHIFT_SCHEMA="${USER}_dev"
```

Correr:

```bash
dbt seed --select compat_test_users --target dev_redshift
dbt run --select tag:compat_examples --target dev_redshift
dbt test --select tag:compat_examples --target dev_redshift
```

Si los modelos compilan y los tests pasan en ambos motores → la capa cross-db está cumpliendo su función.

Para comparación granular de resultados (CSV diff), ver el bloque `Comparar paridad` del README.

---

## 9. Usar como package en otro proyecto dbt

En el proyecto destino, agregar al `packages.yml`:

```yaml
packages:
  - git: "https://github.com/alejandrogenovese/fix_postgres_redshift_dbt.git"
    revision: main   # o un tag versionado
```

Después: `dbt deps`.

Y en el `dbt_project.yml` del proyecto destino, agregar el hook:

```yaml
on-run-start:
  - "{{ install_postgres_compat() }}"
```

> Cuando se usa como package, las macros quedan namespaced. `{{ median(col) }}` se vuelve `{{ galicia_dbt_compat.median(col) }}`. Para invocar sin namespace, configurar `dispatch` en el `dbt_project.yml` del proyecto destino.

---

## 10. Troubleshooting

### `Could not find profile named 'galicia_dbt_compat'`

`profiles.yml` no está en `~/.dbt/`. Solución:

```bash
mkdir -p ~/.dbt
cp profiles.yml.example ~/.dbt/profiles.yml
dbt debug
```

### `connection refused` en `dbt debug`

dbt no puede llegar al host. Verificar:

```bash
# El host en profiles.yml apunta a donde debe
grep -E "host|port" ~/.dbt/profiles.yml

# Postgres está escuchando
psql -h <host> -U <user> -d <db> -c "select 1;"

# Si Postgres está en un contenedor: ¿está corriendo? ¿está mapeado el puerto?
docker ps   # o: podman ps
```

### `function getdate() does not exist`

La capa de compatibilidad no se instaló. Verificar:

```bash
# Que el hook esté en dbt_project.yml
grep -A1 "on-run-start" dbt_project.yml

# Forzar instalación
dbt run-operation install_postgres_compat
```

### `permission denied` al crear funciones en Postgres

El usuario no tiene permisos de DDL. Solución (como superuser):

```sql
ALTER USER dbt_dev WITH SUPERUSER;
-- o más restrictivo:
GRANT CREATE ON SCHEMA public TO dbt_dev;
```

### Error en Redshift: `syntax error at or near 'concat_n'`

`concat_n` es macro Jinja, no función SQL. Falta `{{ }}`:

```sql
-- Mal
select concat_n(first_name, ' ', last_name)

-- Bien
select {{ concat_n('first_name', "' '", 'last_name') }}
```

### `dbt seed` falla con encoding

Verificar UTF-8:

```bash
file seeds/*.csv
# tendría que decir: UTF-8 Unicode text
```

### Las funciones de Postgres se "perdieron" después de drop schema

Si dropeaste y recreaste la base/schema, reinstalá:

```bash
dbt run-operation install_postgres_compat
```

### Quiero deshacer todo en Postgres

```sql
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
```

---

## Referencias

- [Documentación oficial dbt](https://docs.getdbt.com)
- [dbt cross-db macros](https://docs.getdbt.com/reference/dbt-jinja-functions/cross-database-macros)
- [dbt-utils](https://github.com/dbt-labs/dbt-utils)
