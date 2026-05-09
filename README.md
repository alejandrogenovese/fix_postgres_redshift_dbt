# dbt cross-db compatibility — Postgres ⇄ Redshift

Set de macros y capa de compatibilidad SQL para desarrollar dbt en Postgres local y promover a Redshift sin reescribir consultas.

## Estructura

```
macros/
├── compat/
│   └── install_postgres_compat.sql   # Crea funciones SQL en Postgres
└── cross_db/
    ├── dates.sql           # GETDATE, ADD_MONTHS, MONTHS_BETWEEN, CONVERT_TIMEZONE…
    ├── nulls.sql           # NVL, NVL2, DECODE
    ├── strings.sql         # LEN, LISTAGG, CONCAT con N args
    ├── regex.sql           # REGEXP_SUBSTR, REGEXP_COUNT, REGEXP_INSTR
    ├── aggregations.sql    # MEDIAN, APPROXIMATE COUNT DISTINCT, RATIO_TO_REPORT
    ├── json.sql            # JSON/SUPER: extract, parse, valid, typeof
    ├── unnest.sql          # UNNEST de arrays / SUPER + array/object construct
    └── types.sql           # VARCHAR seguro, try_cast, boolean
```

## Setup

1. Copiar la carpeta `macros/` a tu proyecto dbt.
2. En `dbt_project.yml` agregar el hook para que la capa de compatibilidad se instale automáticamente al correr dbt contra Postgres:

```yaml
on-run-start:
  - "{{ install_postgres_compat() }}"
```

3. Listo. Las macros `cross_db` se invocan con `{{ macro(args) }}` desde modelos.

## Cobertura

### Lo que YA está en dbt-core (no reescrito acá)

- `dbt.dateadd`, `dbt.datediff`, `dbt.date_trunc`
- `dbt.last_day`, `dbt.current_timestamp`
- `dbt.length`, `dbt.position`, `dbt.replace`, `dbt.right`, `dbt.split_part`
- `dbt.concat`, `dbt.listagg`
- `dbt.type_string`, `dbt.type_int`, `dbt.type_numeric`, `dbt.type_timestamp`, `dbt.type_boolean`, `dbt.type_bigint`, `dbt.type_float`
- `dbt.hash`, `dbt.bool_or`, `dbt.cast_bool_to_text`
- `dbt.array_construct`, `dbt.array_append`, `dbt.array_concat`
- `dbt.except`, `dbt.intersect`
- `dbt.escape_single_quotes`, `dbt.string_literal`

### Lo que cubren estas macros

| Categoría | Macros incluidas |
|---|---|
| Fecha/tiempo | `getdate`, `sysdate`, `add_months`, `months_between`, `months_between_decimal`, `convert_timezone`, `convert_timezone_2`, `trunc_to_date`, `ts_literal`, `date_part_xdb` |
| NULL/cond. | `nvl`, `nvl2`, `decode`, `nullif_xdb`, `greatest_xdb`, `least_xdb` |
| String | `len`, `charindex`, `concat_n`, `listagg`, `listagg_distinct`, `left_xdb`, `right_xdb`, `lpad_xdb`, `rpad_xdb`, `quote_literal_xdb` |
| Regex | `regexp_substr`, `regexp_count`, `regexp_instr`, `regexp_replace_xdb`, `regexp_matches_xdb` |
| Agregadas | `median`, `percentile_cont`, `percentile_disc`, `approximate_count_distinct`, `ratio_to_report`, `corr_xdb` |
| JSON/SUPER | `json_parse`, `json_extract_path_text`, `json_extract_array_element_text`, `json_path`, `is_valid_json`, `is_valid_json_array`, `json_typeof`, `json_array_length` |
| Arrays | `unnest_array`, `array_literal`, `object_construct` |
| Tipos | `varchar_safe`, `varchar_exact`, `varchar_max`, `try_cast_numeric`, `try_cast_date`, `to_boolean` |

### Capa SQL en Postgres (`install_postgres_compat`)

Crea funciones nativas para que código Redshift-style funcione sin macro:

- `getdate()`, `dateadd()`, `datediff()`, `add_months()`, `months_between()`, `last_day()`, `convert_timezone()`, `trunc(timestamp)`
- `nvl()`, `nvl2()`
- `len()`, `charindex()`
- `regexp_count()`, `regexp_substr()`, `regexp_instr()`
- `is_valid_json_pg()`, `is_valid_json_array_pg()`
- `json_extract_path_text()` (overloads 2/3/4 args)
- `json_extract_array_element_text()`, `json_array_length()`

## DDL específico de Redshift

NO van en macros: usar `config()` de dbt. El adapter Postgres los ignora.

```sql
{{ config(
    materialized='table',
    dist='customer_id',
    sort=['created_at', 'customer_id'],
    sort_type='compound'
) }}
```

## Convenciones recomendadas (del documento de análisis)

1. Prohibir `TEXT` como tipo. Forzar `varchar(n)` explícito (usar `{{ varchar_safe(n) }}`).
2. Prohibir arrays nativos Postgres (`int[]`, `text[]`).
3. Prohibir operadores JSONB (`->`, `->>`, `#>>`). Acceso siempre vía macro.
4. Prohibir `RETURNING`, `ON CONFLICT`.
5. Sobredimensionar VARCHAR x4 para multibyte UTF-8.

Enforcement con SQLFluff + reglas custom en pre-commit + CI.

## Limitaciones conocidas

- **MEDIAN agregado en Postgres**: no se puede definir trivialmente como UDF agregada. Usar siempre la macro `{{ median(col) }}`, no `median(col)` directo en SQL.
- **REGEXP_INSTR con position/occurrence**: emulación parcial; casos complejos requieren reescritura.
- **CONVERT_TIMEZONE**: comportamiento sobre `timestamptz` vs `timestamp` difiere; usar la versión correcta.
- **MONTHS_BETWEEN**: la versión "entera" pierde decimales; usar `months_between_decimal` si los necesitás.
- **APPROXIMATE COUNT DISTINCT en Postgres**: fallback a `count(distinct)` exacto. Para emular HLL real, instalar la extensión `postgresql-hll` y modificar la rama.
- **SUPER nested + UNNEST con seq**: solo casos simples; reescribir manualmente para arrays anidados o iteración con índice.
- **DECODE con NULLs**: `DECODE` en Oracle/Teradata trata `NULL = NULL`; el `CASE expr WHEN v` de SQL estándar NO. Si el código original depende de match con NULL, usar `case when expr is null then ... when expr = v then ... end`.

## Riesgos residuales (del documento)

Aunque las macros estén instaladas, persisten:

- Divergencias silenciosas no detectadas en pipeline (TEXT trunca, VARCHAR cuenta bytes vs chars).
- Diferencias de performance no se ven en local (DISTKEY/SORTKEY no aplican).
- Constraint enforcement: Postgres enforcea PK/FK/UNIQUE; Redshift no.

Mitigación: tests dbt explícitos (`unique`, `not_null`, `relationships`) + pipeline con sampling de modelos críticos.
# fix_postgres_redshift_dbt
