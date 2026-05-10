# galicia_dbt_compat

Capa de compatibilidad cross-db **Postgres ↔ Redshift** para dbt. Pensada para el contexto de migración Teradata → Redshift de Banco Galicia.

Permite desarrollar y testear modelos dbt en Postgres y promoverlos a Redshift sin reescribir las consultas.

## Cómo funciona

Los modelos invocan macros como `{{ median(col) }}` o `{{ nvl(a, b) }}`. Al compilar:

- Contra **Postgres** → renderiza la equivalencia (`coalesce(a, b)`, `percentile_cont(0.5)`, etc.) y se apoya en una capa SQL de funciones (`getdate`, `dateadd`, `nvl`...) que el proyecto instala automáticamente en la base con un hook `on-run-start`.
- Contra **Redshift** → renderiza las funciones nativas (`nvl(a, b)`, `median(col)`).

El SQL final es distinto, el resultado es equivalente.

## Requisitos

- Python 3.9+
- dbt-core ≥ 1.8 con adapters `dbt-postgres` y `dbt-redshift`
- Una base Postgres accesible (local, contenedor, o remota)
- Credenciales a un Redshift dev (opcional, para promoción)

> El runtime que uses para correr la base (Postgres nativo, Docker, Podman, RDS, etc.) es irrelevante para el proyecto. Solo importa que dbt pueda conectarse al host configurado.

## Quickstart

```bash
git clone https://github.com/alejandrogenovese/fix_postgres_redshift_dbt.git
cd fix_postgres_redshift_dbt

# 1. Crear venv e instalar dbt
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install "dbt-core>=1.8" "dbt-postgres>=1.8" "dbt-redshift>=1.8"

# 2. Configurar profiles
mkdir -p ~/.dbt
cp profiles.yml.example ~/.dbt/profiles.yml
# Editar ~/.dbt/profiles.yml o exportar env vars (POSTGRES_HOST, etc.)

# 3. Instalar dependencias dbt y verificar
dbt deps
dbt debug

# 4. Correr ejemplos
dbt seed --select compat_test_users
dbt run --select tag:compat_examples
dbt test --select tag:compat_examples
```

> **Setup detallado:** ver [INSTALACION.md](INSTALACION.md).

## Estructura

```
.
├── README.md                           ← estás acá
├── INSTALACION.md                      ← setup paso a paso
├── dbt_project.yml                     ← config dbt + on-run-start hook
├── packages.yml                        ← dependencias (dbt-utils)
├── profiles.yml.example                ← plantilla de conexiones
│
├── macros/
│   ├── compat/
│   │   └── install_postgres_compat.sql ← capa SQL de funciones Redshift-compat
│   ├── cross_db/                       ← 8 categorías, 57 macros Jinja
│   │   ├── aggregations.sql
│   │   ├── dates.sql
│   │   ├── json.sql
│   │   ├── nulls.sql
│   │   ├── regex.sql
│   │   ├── strings.sql
│   │   ├── types.sql
│   │   └── unnest.sql
│   └── utils/
│       └── export_compat_results.sql
│
├── models/
│   └── examples/                       ← 100% cobertura de macros
│       ├── example_aggregations.sql
│       ├── example_dates.sql
│       ├── example_json.sql
│       ├── example_nulls.sql
│       ├── example_regex.sql
│       ├── example_strings.sql
│       ├── example_types.sql
│       ├── example_unnest.sql
│       └── schema.yml
│
└── seeds/
    ├── compat_test_users.csv
    └── properties.yml
```

## Cobertura de macros

| Categoría | Cantidad | Modelo de ejemplo |
|---|---:|---|
| Fecha/tiempo | 10 | `models/examples/example_dates.sql` |
| NULL/condicionales | 6 | `models/examples/example_nulls.sql` |
| Strings | 11 | `models/examples/example_strings.sql` |
| Regex | 5 | `models/examples/example_regex.sql` |
| Agregadas/analíticas | 8 | `models/examples/example_aggregations.sql` |
| JSON/SUPER | 8 | `models/examples/example_json.sql` |
| Arrays/UNNEST | 3 | `models/examples/example_unnest.sql` |
| Tipos/casts | 6 | `models/examples/example_types.sql` |
| **Total** | **57** | **100% cubierto** |

Cada modelo de ejemplo tiene comentarios pedagógicos explicando qué hace cada macro, cuándo usarla, y caveats. Orden de lectura recomendado: nulls → strings → dates → aggregations → regex → types → json → unnest.

## Lo que YA está en dbt-core (no reescrito acá)

Cross-db macros nativos de dbt-core; se invocan con prefijo `dbt.*`:

- Fecha: `dbt.dateadd`, `dbt.datediff`, `dbt.date_trunc`, `dbt.last_day`, `dbt.current_timestamp`
- Strings: `dbt.length`, `dbt.position`, `dbt.replace`, `dbt.right`, `dbt.split_part`, `dbt.concat`, `dbt.listagg`
- Tipos: `dbt.type_string`, `dbt.type_int`, `dbt.type_numeric`, `dbt.type_timestamp`, `dbt.type_boolean`
- Arrays: `dbt.array_construct`, `dbt.array_append`, `dbt.array_concat`
- Set ops: `dbt.except`, `dbt.intersect`
- Otros: `dbt.hash`, `dbt.bool_or`, `dbt.cast_bool_to_text`

## Uso en otro proyecto dbt

Agregar al `packages.yml` del proyecto destino:

```yaml
packages:
  - git: "https://github.com/alejandrogenovese/fix_postgres_redshift_dbt.git"
    revision: main   # o un tag versionado
```

Y en su `dbt_project.yml`:

```yaml
on-run-start:
  - "{{ install_postgres_compat() }}"
```

> Las macros quedan namespaced bajo el nombre del package (`galicia_dbt_compat`). Para invocar sin namespace, configurar `dispatch` en el `dbt_project.yml` del proyecto destino.

## Convenciones del equipo

Del documento de análisis interno:

1. Prohibir `TEXT` como tipo de columna. Usar `varchar(n)` explícito (`{{ varchar_safe(n) }}`).
2. Prohibir arrays nativos Postgres (`int[]`, `text[]`). Usar SUPER/JSONB vía macro.
3. Prohibir operadores JSONB (`->`, `->>`, `#>>`). Acceso siempre vía macro.
4. Prohibir `RETURNING`, `ON CONFLICT`.
5. Sobredimensionar VARCHAR x4 para multibyte UTF-8.

Enforcement: SQLFluff con reglas custom + pre-commit + CI.

## Limitaciones conocidas

- **`MEDIAN` agregado en Postgres**: no se puede definir como UDF agregada trivialmente. Siempre vía `{{ median(col) }}`, nunca `median(col)` directo.
- **`MONTHS_BETWEEN` con decimales**: usar `months_between_decimal`.
- **`DECODE` con NULLs**: Oracle/Teradata tratan `NULL = NULL`; el `CASE` estándar NO. Si el código original lo asume, agregar `WHEN expr IS NULL` explícito.
- **`REGEXP_INSTR` con position/occurrence**: emulación parcial.
- **`APPROXIMATE COUNT DISTINCT` en Postgres**: cae a count distinct exacto (sin HLL).
- **SUPER nested + UNNEST con seq**: solo casos simples.

## Comparar paridad Postgres ↔ Redshift

```bash
mkdir -p compare/postgres compare/redshift

# Postgres
for m in example_dates example_nulls example_strings example_regex \
         example_aggregations example_json example_unnest example_types; do
  PGPASSWORD="$POSTGRES_PASSWORD" psql -h "$POSTGRES_HOST" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c \
    "\COPY (select * from ${POSTGRES_SCHEMA}.${m} order by 1) TO 'compare/postgres/${m}.csv' WITH CSV HEADER"
done

# Redshift
for m in example_dates example_nulls example_strings example_regex \
         example_aggregations example_json example_unnest example_types; do
  PGPASSWORD="$REDSHIFT_PWD" psql "host=$REDSHIFT_HOST port=5439 dbname=$REDSHIFT_DB user=$REDSHIFT_USER sslmode=require" -c \
    "\COPY (select * from ${REDSHIFT_SCHEMA}.${m} order by 1) TO 'compare/redshift/${m}.csv' WITH CSV HEADER"
done

diff -r compare/postgres compare/redshift
```

Diferencias esperadas (timestamps de run, precisión numérica, HLL approx) están documentadas inline en cada `example_*.sql`.

## Recursos

- [Documentación oficial dbt](https://docs.getdbt.com)
- [dbt cross-db macros](https://docs.getdbt.com/reference/dbt-jinja-functions/cross-database-macros)
- [dbt-utils](https://github.com/dbt-labs/dbt-utils)

## Autor

Alejandro Genovese — Data Architecture Lead, Banco Galicia.
