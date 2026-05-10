{{ config(
    materialized='table',
    tags=['compat_examples']
) }}

-- ============================================================
-- example_types.sql
-- Cubre TODAS las macros de cross_db/types.sql
-- ============================================================
-- Macros ejercitadas:
--   varchar_safe, varchar_exact, varchar_max,
--   try_cast_numeric, try_cast_date, to_boolean
-- ============================================================
--
-- 🎯 La razón de existir de estas macros viene del documento de
-- análisis: el riesgo SILENCIOSO más grande Postgres↔Redshift es:
--   1. TEXT en Redshift = VARCHAR(256), trunca sin avisar.
--   2. VARCHAR(n) en Redshift cuenta BYTES; en Postgres cuenta CARACTERES.
--      Con UTF-8 multibyte (acentos), un string de 100 chars
--      ocupa ~110 bytes y se trunca al promover de Postgres a Redshift.
-- Mitigación: SIEMPRE varchar(n) explícito + factor x4 multibyte.

-- ============================================================
-- PARTE 1: macros de TIPO (DDL)
-- ============================================================
-- Estas macros se usan típicamente en ::cast inline o en config()
-- de modelos. Acá las mostramos como cast en SELECT.
--
-- NOTA: en este archivo, NO incluimos ejemplos de uso adentro de
-- comentarios SQL (--), porque los macros generan whitespace que
-- al expandir Jinja rompe el comentario en múltiples líneas y
-- termina inyectando SQL real. Para ver ejemplos de uso:
-- README.md o models/examples/schema.yml.

with cast_demo as (

    select
        u.id,
        u.first_name,

        -- varchar_safe(n_chars) -> varchar(n*4)
        -- Aplica el factor x4 para cubrir UTF-8 multibyte.
        u.first_name::{{ varchar_safe(50) }} as first_name_safe50,

        -- varchar_exact(n) -> varchar(n)
        -- Tamaño exacto sin factor. ATENCION: significa BYTES en
        -- Redshift y CARACTERES en Postgres (riesgo silencioso).
        u.first_name::{{ varchar_exact(100) }} as first_name_exact100,

        -- varchar_max() -> varchar(max) en Redshift, varchar(65535) en Postgres
        u.first_name::{{ varchar_max() }} as first_name_unbounded

    from {{ ref('compat_test_users') }} u

),

-- ============================================================
-- PARTE 2: TRY_CAST tolerantes (DML)
-- ============================================================
dirty_data as (

    select '123.45'        as price_str, '2025-01-15' as date_str, 'true'  as bool_str union all
    select '0'             as price_str, '2024-12-31' as date_str, 'false' as bool_str union all
    select '-99.99'        as price_str, '2025-13-99' as date_str, 'yes'   as bool_str union all
    select 'not_a_number'  as price_str, 'no_date'    as date_str, '1'     as bool_str union all
    select ''              as price_str, ''           as date_str, ''      as bool_str union all
    select null::varchar   as price_str, null         as date_str, null    as bool_str union all
    select '  500  '       as price_str, '2025-06-15' as date_str, 'maybe' as bool_str

),

casts_applied as (

    select
        price_str,

        -- try_cast_numeric(col) -> numeric o NULL si no parsea.
        -- Implementacion: regex check + cast. Util para datos sucios.
        {{ try_cast_numeric('trim(price_str)') }} as price_numeric,

        date_str,

        -- try_cast_date(col, format) -> date o NULL.
        -- La emulacion en Postgres es basica (cast directo a ::date).
        -- Para formatos no-ISO extender la macro.
        {{ try_cast_date("nullif(trim(date_str), '')") }} as date_casted,

        bool_str,

        -- to_boolean(col) -> boolean con tolerancia.
        -- true: 't', 'true', '1', 'y', 'yes'
        -- false: 'f', 'false', '0', 'n', 'no'
        -- otros: NULL
        {{ to_boolean('bool_str') }} as bool_casted

    from dirty_data

)

-- Materializamos ambas partes para inspeccion
select
    'cast_ddl' as demo_type,
    id::varchar as ref,
    first_name as input_value,
    first_name_safe50 as output_value,
    null::varchar as raw_input,
    null::varchar as casted_str
from cast_demo

union all

select
    'try_cast' as demo_type,
    null as ref,
    price_str as input_value,
    price_numeric::varchar as output_value,
    bool_str as raw_input,
    case
        when bool_casted is null then 'NULL'
        when bool_casted then 'true'
        else 'false'
    end as casted_str
from casts_applied
