{{ config(
    materialized='table',
    tags=['compat_examples']
) }}

-- ============================================================
-- example_unnest.sql
-- Cubre TODAS las macros de cross_db/unnest.sql
-- ============================================================
-- Macros ejercitadas:
--   array_literal, object_construct, unnest_array
-- ============================================================
--
-- ⚠ IMPORTANTE: la abstracción cross-db de arrays es la MÁS LIMITADA
-- de toda la capa, porque:
--   - Redshift maneja arrays como SUPER (PartiQL) — tipo unificado.
--   - Postgres tiene arrays nativos por tipo (int[], text[], jsonb).
-- Por eso este modelo prioriza casos simples; los productivos
-- requieren validación caso por caso.

-- ─── array_literal(...) ──────────────────────────────────────
-- Construye un array literal.
--   Redshift: array(...)
--   Postgres: array[...]
with arrays as (

    select
        1 as id,
        {{ array_literal("'AR'", "'UY'", "'CL'") }} as latam_countries,
        {{ array_literal('100', '200', '300', '400') }} as tier_thresholds

),

-- ─── object_construct(k1, v1, k2, v2, ...) ──────────────────
-- Pares clave/valor → struct semi-estructurado.
--   Redshift: object('k1', v1, ...)         → SUPER
--   Postgres: jsonb_build_object('k1', v1)  → JSONB
-- Caso típico: armar payload para columna SUPER/JSONB downstream.
objects as (

    select
        u.id,
        u.country_code,
        {{ object_construct(
            'user_id',  'u.id',
            'name',     'u.first_name',
            'country',  'u.country_code',
            'balance',  'coalesce(u.balance, 0)'
        ) }} as user_payload
    from {{ ref('compat_test_users') }} u

),

-- ─── unnest_array(col, alias[, with_ordinality]) ────────────
-- Expande un array a filas. Sintaxis subyacente difiere:
--   Redshift (SUPER):    from t, t.tags as tag at seq
--   Postgres (array):    from t cross join unnest(t.tags) as tag(value)
-- En este ejemplo construimos el array inline porque el CSV no
-- guarda arrays nativos.
unnest_via_macro as (

    select
        v as fruit
    from (
        select {{ array_literal("'apple'", "'banana'", "'cherry'", "'date'") }} as fruits
    ) src
    cross join {{ unnest_array('src.fruits', 'v') }}

),

-- Caso "real": expandir tags_csv a filas. Como tags_csv es VARCHAR,
-- usamos string_to_array para convertirlo y después la macro.
-- Postgres: native. Redshift: split_to_array convierte VARCHAR a SUPER.
unnest_tags as (

    select
        u.id,
        u.first_name,
        tag.value as tag_name
    from {{ ref('compat_test_users') }} u
    cross join lateral unnest(
        string_to_array(coalesce(nullif(u.tags_csv, ''), 'no_tags'), ',')
    ) as tag(value)

)

-- Materializamos los tres demos como filas
select
    'array_literal' as demo_type,
    a.id as ref_id,
    array_to_string(a.latam_countries, ',') as info_value
from arrays a

union all

select
    'object_construct' as demo_type,
    o.id as ref_id,
    o.user_payload::varchar as info_value
from objects o

union all

select
    'unnest_macro' as demo_type,
    null as ref_id,
    um.fruit as info_value
from unnest_via_macro um

union all

select
    'unnest_tags' as demo_type,
    u.id as ref_id,
    u.tag_name as info_value
from unnest_tags u
where u.tag_name not in ('no_tags', '')
