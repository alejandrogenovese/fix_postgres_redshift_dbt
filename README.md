# galicia_dbt_compat

Proyecto dbt con capa de compatibilidad cross-db **Postgres ↔ Redshift** para el contexto de migración Teradata → Redshift de Banco Galicia.

Permite desarrollar y testear modelos dbt en Postgres local y promoverlos a Redshift sin reescribir las consultas.

## ¿Qué hay acá?

```
galicia_dbt_compat/
├── dbt_project.yml              # Config del proyecto + on-run-start hook
├── packages.yml                 # Dependencias dbt (dbt-utils)
├── profiles.yml.example         # Plantilla de conexiones
├── .gitignore
├── README.md                    # ← estás acá
├── INSTALACION.md               # Paso a paso desde cero
│
├── macros/
│   ├── compat/
│   │   └── install_postgres_compat.sql   # Crea funciones Redshift-compatibles en Postgres
│   ├── cross_db/                # Macros Jinja por categoría
│   │   ├── aggregations.sql     # MEDIAN, percentiles, RATIO_TO_REPORT, stddev, corr
│   │   ├── dates.sql            # GETDATE, ADD_MONTHS, MONTHS_BETWEEN, CONVERT_TIMEZONE…
│   │   ├── json.sql             # JSON/SUPER: extract, parse, valid, typeof
│   │   ├── nulls.sql            # NVL, NVL2, DECODE, GREATEST/LEAST
│   │   ├── regex.sql            # REGEXP_SUBSTR, REGEXP_COUNT, REGEXP_INSTR
│   │   ├── strings.sql          # LEN, LISTAGG, CONCAT con N args, padding
│   │   ├── types.sql            # VARCHAR seguro, try_cast, boolean
│   │   └── unnest.sql           # UNNEST + array_literal + object_construct
│   └── utils/
│       └── export_compat_results.sql      # Helper para comparar paridad
│
├── models/
│   └── examples/                # Suite pedagógica que cubre el 100% de las macros
│       ├── example_aggregations.sql
│       ├── example_dates.sql
│       ├── example_json.sql
│       ├── example_nulls.sql
│       ├── example_regex.sql
│       ├── example_strings.sql
│       ├── example_types.sql
│       ├── example_unnest.sql
│       └── schema.yml           # Tests dbt
│
├── seeds/
│   ├── compat_test_users.csv    # Datos sintéticos con casos borde
│   └── properties.yml
│
├── analyses/                    # (vacío, listo para análisis ad-hoc)
├── snapshots/                   # (vacío, listo para snapshots)
└── tests/                       # (vacío, listo para tests singulares)
```

## Quickstart

```bash
# 1. Clonar y entrar
git clone https://github.com/alejandrogenovese/fix_postgres_redshift_dbt.git galicia_dbt_compat
cd galicia_dbt_compat

# 2. Crear venv e instalar dbt
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install "dbt-core>=1.8" "dbt-postgres>=1.8" "dbt-redshift>=1.8"

# 3. Configurar profiles.yml
mkdir -p ~/.dbt
cp profiles.yml.example ~/.dbt/profiles.yml
# Editar ~/.dbt/profiles.yml con tus credenciales reales

# 4. Instalar dependencias dbt
dbt deps

# 5. Verificar conexión
dbt debug

# 6. Cargar datos de prueba y correr ejemplos
dbt seed --select compat_test_users
dbt run --select tag:compat_examples
dbt test --select tag:compat_examples
```

Si todo pasa: capa cross-db funcionando.

> ¿Primera vez con dbt o Postgres? Leer **`INSTALACION.md`** que tiene el paso a paso desde cero (instalar Postgres, crear venv, configurar credenciales, troubleshooting).

## Cobertura de macros

**57 macros del repo, 100% cubiertas por modelos de ejemplo.**

| Categoría | Macros | Ejemplo |
|---|---|---|
| Fecha/tiempo | 10 | `models/examples/example_dates.sql` |
| NULL/condicionales | 6 | `models/examples/example_nulls.sql` |
| Strings | 11 | `models/examples/example_strings.sql` |
| Regex | 5 | `models/examples/example_regex.sql` |
| Agregadas/analíticas | 8 | `models/examples/example_aggregations.sql` |
| JSON/SUPER | 8 | `models/examples/example_json.sql` |
| Arrays/UNNEST | 3 | `models/examples/example_unnest.sql` |
| Tipos/casts | 6 | `models/examples/example_types.sql` |

Cada modelo de ejemplo contiene comentarios pedagógicos por macro: qué hace, cuándo usarla, qué pasaría sin ella, caveats.

## Lo que YA está en dbt-core (no reescrito acá)

Estos cross-db macros vienen en dbt-core y se invocan con prefijo `dbt.*`:

- `dbt.dateadd`, `dbt.datediff`, `dbt.date_trunc`, `dbt.last_day`, `dbt.current_timestamp`
- `dbt.length`, `dbt.position`, `dbt.replace`, `dbt.right`, `dbt.split_part`
- `dbt.concat`, `dbt.listagg`
- `dbt.type_string`, `dbt.type_int`, `dbt.type_numeric`, `dbt.type_timestamp`, `dbt.type_boolean`
- `dbt.hash`, `dbt.bool_or`, `dbt.cast_bool_to_text`
- `dbt.array_construct`, `dbt.array_append`, `dbt.array_concat`
- `dbt.except`, `dbt.intersect`

## Cómo usar las macros en tus modelos

**Ejemplo simple:**

```sql
{{ config(materialized='table') }}

select
    user_id,
    {{ nvl('email', "'no-email'") }} as email_clean,
    {{ add_months('signup_at', 12) }} as one_year_later,
    {{ median('balance') }} over (partition by country_code) as median_balance_country
from {{ source('raw', 'users') }}
```

**Lo que hace dbt al compilar:**

- Contra Postgres → renderiza `coalesce(email, 'no-email')`, etc.
- Contra Redshift → renderiza `nvl(email, 'no-email')` (función nativa).

El SQL final es distinto, el resultado es equivalente.

## Convenciones del equipo

Del documento de análisis (ver `INSTALACION.md`):

1. Prohibir `TEXT` como tipo. Usar `varchar(n)` explícito (`{{ varchar_safe(n) }}`).
2. Prohibir arrays nativos Postgres (`int[]`, `text[]`). Usar SUPER/JSONB vía macro.
3. Prohibir operadores JSONB Postgres (`->`, `->>`, `#>>`). Acceso siempre vía macro.
4. Prohibir `RETURNING`, `ON CONFLICT`.
5. Sobredimensionar VARCHAR x4 para multibyte UTF-8 (default del proyecto).

Enforcement: SQLFluff con reglas custom + pre-commit + CI.

## Limitaciones conocidas

- **`MEDIAN` agregado en Postgres**: SIEMPRE vía macro `{{ median(col) }}`.
- **`MONTHS_BETWEEN` con decimales**: usar `months_between_decimal`.
- **`DECODE` con NULLs**: Oracle/Teradata tratan `NULL = NULL`; el `CASE` estándar NO. Si el código original lo asume, agregar `WHEN expr IS NULL` explícito.
- **`REGEXP_INSTR` con position/occurrence**: emulación parcial.
- **`APPROXIMATE COUNT DISTINCT` en Postgres**: cae a count distinct exacto.
- **SUPER nested + UNNEST con seq**: solo casos simples; reescribir manualmente para anidados.

## Comparar paridad Postgres ↔ Redshift

```bash
mkdir -p compare/postgres compare/redshift

for m in example_dates example_nulls example_strings example_regex \
         example_aggregations example_json example_unnest example_types; do
  psql -h localhost -U dbt_dev -d dbt_dev -c \
    "\COPY (select * from dbt_dev.${m} order by 1) TO 'compare/postgres/${m}.csv' WITH CSV HEADER"
done

for m in example_dates example_nulls example_strings example_regex \
         example_aggregations example_json example_unnest example_types; do
  psql "host=$REDSHIFT_HOST port=5439 dbname=dev user=$REDSHIFT_USER password=$REDSHIFT_PWD sslmode=require" -c \
    "\COPY (select * from ${USER}_dev.${m} order by 1) TO 'compare/redshift/${m}.csv' WITH CSV HEADER"
done

diff -r compare/postgres compare/redshift
```

Diferencias esperadas (timestamps de run, precisión numérica, HLL approx) están documentadas en `models/examples/` (comentarios inline).

## Recursos

- [dbt cross-db macros oficiales](https://docs.getdbt.com/reference/dbt-jinja-functions/cross-database-macros)
- [dbt-utils](https://github.com/dbt-labs/dbt-utils)
- Documento de análisis interno: `analisis dbt con postgres vs redshift.docx`

## Autor

Alejandro Genovese — Data Architecture Lead, Banco Galicia.
