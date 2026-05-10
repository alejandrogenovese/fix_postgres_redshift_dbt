{{ config(
    materialized='table',
    tags=['compat_examples']
) }}

-- ============================================================
-- example_dates.sql
-- Cubre TODAS las macros de cross_db/dates.sql
-- ============================================================
-- Macros ejercitadas:
--   getdate, sysdate, convert_timezone, convert_timezone_2,
--   add_months, months_between, months_between_decimal,
--   trunc_to_date, ts_literal, date_part_xdb
-- ============================================================

select
    id,
    signup_at,

    -- ─── getdate() ───────────────────────────────────────────
    -- Devuelve el timestamp actual.
    -- En Redshift es función nativa; en Postgres la macro renderiza
    -- current_timestamp::timestamp.
    -- Cuándo usarla: para auditoría (created_at, run_at).
    {{ getdate() }} as run_ts,

    -- ─── sysdate() ───────────────────────────────────────────
    -- Devuelve el timestamp del INICIO de la transacción.
    -- En Redshift es palabra reservada; en Postgres la macro usa
    -- transaction_timestamp().
    -- Diferencia con getdate(): si tu modelo tarda 5 minutos,
    -- getdate() cambia, sysdate() queda fijo en el inicio.
    {{ sysdate() }} as txn_start_ts,

    -- ─── ts_literal('YYYY-MM-DD HH:MM:SS') ───────────────────
    -- Construye un literal timestamp portable.
    -- Útil para evitar TIMESTAMP '...' que algunos linters marcan.
    {{ ts_literal('2025-01-01 00:00:00') }} as year_start,

    -- ─── add_months(col, n) ──────────────────────────────────
    -- Suma n meses (puede ser negativo).
    -- Si el día no existe en el mes destino (31 → febrero),
    -- ambos motores ajustan al último día.
    {{ add_months('signup_at', 6) }} as signup_plus_6m,
    {{ add_months('signup_at', -3) }} as signup_minus_3m,

    -- ─── months_between(a, b) ───────────────────────────────
    -- Cantidad de meses ENTEROS entre dos fechas (a - b).
    -- IMPORTANTE: pierde decimales. Para fracción de mes usar
    -- months_between_decimal.
    {{ months_between('current_timestamp::timestamp', 'signup_at') }}
        as months_since_signup_int,

    -- ─── months_between_decimal(a, b) ────────────────────────
    -- Misma lógica pero conservando la fracción.
    -- Más fiel al comportamiento Redshift nativo.
    -- Cuándo importa: cálculos de antigüedad para billing, churn, etc.
    {{ months_between_decimal('current_timestamp::timestamp', 'signup_at') }}
        as months_since_signup_decimal,

    -- ─── convert_timezone(tz_from, tz_to, ts) ────────────────
    -- Convierte un timestamp asumiendo origen y destino.
    -- Uso: signup_at lo guardamos en UTC, lo mostramos en BSAS.
    {{ convert_timezone('UTC', 'America/Argentina/Buenos_Aires', 'signup_at') }}
        as signup_at_bsas,

    -- ─── convert_timezone_2(tz_to, ts) ───────────────────────
    -- Variante 2-args: asume que ts ya es timestamptz (UTC implícito).
    -- Más seguro si almacenás siempre timestamptz.
    {{ convert_timezone_2('America/Argentina/Buenos_Aires',
                           'signup_at::timestamptz') }} as signup_at_bsas_v2,

    -- ─── trunc_to_date(col) ──────────────────────────────────
    -- Trunca a fecha (descarta hora).
    -- En Redshift es trunc(); en Postgres es ::date.
    -- NO confundir con dbt.date_trunc('day', ...) que devuelve timestamp.
    {{ trunc_to_date('signup_at') }} as signup_date,

    -- ─── date_part_xdb(part, col) ────────────────────────────
    -- Wrapper sobre extract(). Estándar SQL en ambos motores.
    -- Existe para enforcement de estilo (vs date_part(...)).
    {{ date_part_xdb('year', 'signup_at') }} as signup_year,
    {{ date_part_xdb('month', 'signup_at') }} as signup_month,
    {{ date_part_xdb('dow', 'signup_at') }} as signup_day_of_week,

    -- ─── dbt-core: dateadd / datediff / last_day ─────────────
    -- Estos NO los reescribimos: vienen en dbt-core.
    -- Se usan con prefijo dbt.* (no es magia: es el package "dbt").
    {{ dbt.dateadd('day', 30, 'signup_at') }} as signup_plus_30d,
    {{ dbt.datediff('signup_at', 'current_timestamp', 'day') }} as days_since_signup,
    {{ dbt.last_day('signup_at', 'month') }} as signup_eom

from {{ ref('compat_test_users') }}
