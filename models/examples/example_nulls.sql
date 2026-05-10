{{ config(
    materialized='table',
    tags=['compat_examples']
) }}

-- ============================================================
-- example_nulls.sql
-- Cubre TODAS las macros de cross_db/nulls.sql
-- ============================================================
-- Macros ejercitadas:
--   nvl, nvl2, decode, nullif_xdb, greatest_xdb, least_xdb
-- ============================================================

select
    id,
    email,
    balance,
    status_code,
    country_code,

    -- ─── nvl(a, b) ───────────────────────────────────────────
    -- Si a es NULL devuelve b. Equivalente a coalesce(a, b).
    -- Existe porque herencia Oracle/Teradata. Redshift la soporta nativa,
    -- Postgres no (la macro la traduce o la capa SQL la define).
    -- Cuándo usarla: cuando el código original viene de Teradata.
    -- Recomendación nueva: usar coalesce() directo (estándar SQL).
    {{ nvl('email', "'no-email@unknown'") }} as email_or_default,
    {{ nvl('balance', '0') }} as balance_or_zero,

    -- ─── nvl2(a, b, c) ───────────────────────────────────────
    -- Si a NO es NULL, devuelve b. Si lo es, devuelve c.
    -- No tiene equivalente directo en SQL estándar; la macro renderiza
    -- un CASE WHEN.
    {{ nvl2('balance', "'has_balance'", "'no_balance'") }} as balance_flag,
    {{ nvl2('email', '1', '0') }} as has_email_int,

    -- ─── decode(expr, v1, r1, v2, r2, ..., default) ──────────
    -- Mapeo many-to-one estilo Oracle. La macro renderiza CASE expr WHEN v.
    -- ⚠ DECODE en Oracle/Teradata trata NULL = NULL (matchea).
    -- El CASE estándar NO. Si tu código depende de match con NULL,
    -- agregar un WHEN explícito para is null.
    {{ decode('status_code',
              "'A'", "'Active'",
              "'I'", "'Inactive'",
              "'P'", "'Pending'",
              "'Unknown'") }} as status_name,

    -- decode sin default (cantidad de args par). Si no matchea, devuelve NULL.
    {{ decode('country_code',
              "'AR'", "'Argentina'",
              "'UY'", "'Uruguay'") }} as country_name_or_null,

    -- ─── nullif_xdb(a, b) ────────────────────────────────────
    -- Si a == b devuelve NULL, sino a. Estándar SQL pero la macro
    -- lo expone para enforcement de estilo (linter).
    -- Caso de uso clásico: evitar división por cero.
    -- balance / nullif(otra_col, 0)
    {{ nullif_xdb('balance', '0') }} as balance_null_if_zero,
    {{ nullif_xdb('country_code', "''") }} as country_null_if_empty,

    -- ─── greatest_xdb(a, b, ...) y least_xdb(a, b, ...) ──────
    -- Wrappers sobre greatest()/least() con varargs.
    -- Comportamiento NULL: ignora NULLs si hay al menos un valor;
    -- devuelve NULL solo si TODOS los argumentos son NULL.
    -- Cuándo importa: comparaciones multi-columna sin reescribir CASE.
    {{ greatest_xdb('balance', '0') }} as balance_floor_zero,
    {{ greatest_xdb('balance', '100', '500') }} as min_balance_500,
    {{ least_xdb('balance', '10000') }} as balance_ceiling_10k,

    -- ─── coalesce + nullif combinados (patrón común) ─────────
    -- Reemplazar string vacío por default real.
    coalesce({{ nullif_xdb('email', "''") }}, 'no-email') as email_clean

from {{ ref('compat_test_users') }}
