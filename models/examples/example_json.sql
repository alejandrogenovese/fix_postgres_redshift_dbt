{{ config(
    materialized='table',
    tags=['compat_examples']
) }}

-- ============================================================
-- example_json.sql
-- Cubre TODAS las macros de cross_db/json.sql
-- ============================================================
-- Macros ejercitadas:
--   json_parse, json_extract_path_text, json_extract_array_element_text,
--   json_path, is_valid_json, is_valid_json_array,
--   json_typeof, json_array_length
-- ============================================================
--
-- 📌 Recordatorio del documento de análisis:
-- En la arquitectura de Banco Galicia, datos semi-estructurados
-- deberían ir al lake (Iceberg/S3). Estas macros existen pero su uso
-- en modelos dbt sobre el warehouse debería ser limitado.
--
-- Para los ejemplos, usamos una columna VARCHAR con JSON adentro y
-- también construimos un caso con JSON arrays inline.

with json_arrays as (

    -- Construimos un caso con JSON array para ejercitar las macros
    -- que operan sobre arrays (no podemos meterlo cómodo en el CSV).
    select
        1 as id,
        '[{"sku": "A1"}, {"sku": "B2"}, {"sku": "C3"}]'::varchar as items_json
    union all
    select 2, '["red", "green", "blue"]'::varchar
    union all
    select 3, '[1, 2, 3, 4, 5]'::varchar
    union all
    select 4, 'not_a_json_array'::varchar

),

users_with_json as (

    select
        id,
        payload_json,

        -- ─── is_valid_json(col) → boolean ────────────────────
        -- Distingue JSON parseable de basura.
        -- Redshift: función nativa.
        -- Postgres: usa is_valid_json_pg() de la capa SQL (try/catch
        -- en plpgsql).
        -- Caso clásico: filtrar antes de extraer paths para no fallar
        -- el modelo.
        {{ is_valid_json('payload_json') }} as is_valid,

        -- ─── json_typeof(col) ────────────────────────────────
        -- Devuelve 'object', 'array', 'string', 'number', 'boolean', 'null'.
        -- Útil para validaciones defensivas.
        case
            when {{ is_valid_json('payload_json') }}
            then {{ json_typeof('payload_json') }}
            else 'invalid'
        end as payload_type,

        -- ─── json_parse(col) → SUPER/JSONB ───────────────────
        -- Cast explícito de texto a tipo semi-estructurado.
        -- Útil cuando vas a hacer múltiples accesos al mismo objeto;
        -- evita parsear N veces.
        case
            when {{ is_valid_json('payload_json') }}
            then {{ json_parse('payload_json') }}
            else null
        end as payload_parsed,

        -- ─── json_extract_path_text(col, k1, k2, ...) → text ─
        -- Extrae el valor de un path como TEXTO.
        -- N args variables: {{ json_extract_path_text('col', 'a', 'b', 'c') }}
        -- ⚠ La capa SQL tiene overloads para 2, 3 y 4 args. Si necesitás
        -- más profundidad, agregar overload o usar json_path con lista.
        case
            when {{ is_valid_json('payload_json') }} then
                {{ json_extract_path_text('payload_json', 'user', 'tier') }}
        end as user_tier,

        case
            when {{ is_valid_json('payload_json') }} then
                {{ json_extract_path_text('payload_json', 'user', 'address', 'city') }}
        end as user_city,

        -- ─── json_path(col, [list]) → JSONB/SUPER ────────────
        -- Como json_extract_path_text pero devuelve el objeto tipado,
        -- no texto. Útil para encadenar más accesos.
        case
            when {{ is_valid_json('payload_json') }} then
                ({{ json_path('payload_json', ['user', 'address']) }})::varchar
        end as user_address_obj

    from {{ ref('compat_test_users') }}
    where payload_json is not null and payload_json != ''

),

arrays_processed as (

    select
        id,
        items_json,

        -- ─── is_valid_json_array(col) ────────────────────────
        -- True solo si es un JSON válido Y es un array.
        {{ is_valid_json_array('items_json') }} as is_array,

        -- ─── json_array_length(col) ──────────────────────────
        -- Cantidad de elementos del array. NULL si no es array.
        case
            when {{ is_valid_json_array('items_json') }}
            then {{ json_array_length('items_json') }}
        end as array_len,

        -- ─── json_extract_array_element_text(col, idx) → text ─
        -- Extrae el elemento idx (0-based) como texto.
        -- ⚠ Si el elemento es un objeto, devuelve su representación
        -- en string (ej: '{"sku":"A1"}').
        case
            when {{ is_valid_json_array('items_json') }}
            then {{ json_extract_array_element_text('items_json', 0) }}
        end as first_element,

        case
            when {{ is_valid_json_array('items_json') }}
            then {{ json_extract_array_element_text('items_json', 1) }}
        end as second_element

    from json_arrays

)

-- Unimos ambas vistas en un solo modelo final
select
    'user' as source,
    id,
    payload_type as info,
    user_tier as field_a,
    user_city as field_b,
    user_address_obj as field_c
from users_with_json

union all

select
    'array' as source,
    id,
    case when is_array then 'array' else 'invalid' end as info,
    array_len::varchar as field_a,
    first_element as field_b,
    second_element as field_c
from arrays_processed
