{{ config(
    materialized='table',
    tags=['compat_examples']
) }}

-- ============================================================
-- example_aggregations.sql
-- Cubre TODAS las macros de cross_db/aggregations.sql
-- ============================================================
-- Macros ejercitadas:
--   median, percentile_cont, percentile_disc,
--   approximate_count_distinct, ratio_to_report,
--   stddev_samp_xdb, stddev_pop_xdb, corr_xdb
-- ============================================================
--
-- ⚠ MEDIAN como agregado en Postgres NO se puede definir como UDF
-- trivialmente. SIEMPRE usar la macro {{ median(col) }}, nunca
-- median(col) directo en SQL.

with by_country as (

    select
        country_code,
        count(*) as users_count,

        -- ─── median(col) ─────────────────────────────────────
        -- Mediana del set. Redshift: nativo. Postgres: emulado con
        -- percentile_cont(0.5).
        -- Comportamiento idéntico para datasets normales.
        {{ median('balance') }} as median_balance,

        -- ─── percentile_cont(col, p) ─────────────────────────
        -- Percentil "continuous" (interpola entre valores).
        -- Estándar SQL: ambos motores idénticos.
        -- Útil para distribuciones (cuartiles, deciles).
        {{ percentile_cont('balance', 0.25) }} as p25_balance,
        {{ percentile_cont('balance', 0.75) }} as p75_balance,
        {{ percentile_cont('balance', 0.95) }} as p95_balance,

        -- ─── percentile_disc(col, p) ─────────────────────────
        -- Percentil "discrete": devuelve un valor que existe en el set
        -- (no interpola).
        -- Cuándo usar disc vs cont: cont para promedios estadísticos,
        -- disc cuando necesitás un valor real (ej. para mostrar al usuario).
        {{ percentile_disc('balance', 0.5) }} as median_disc_balance,

        -- ─── approximate_count_distinct(col) ─────────────────
        -- Redshift: usa HyperLogLog, ~10x más rápido en miles de millones.
        -- Postgres: cae a count(distinct) exacto. Para emular HLL real,
        -- instalar la extensión postgresql-hll.
        -- Cuándo usar: dashboards con cardinalidad alta donde no necesitás
        -- precisión absoluta.
        {{ approximate_count_distinct('email') }} as approx_unique_emails,

        -- ─── stddev_samp_xdb / stddev_pop_xdb ────────────────
        -- Desvío estándar muestral vs poblacional.
        -- Estándar SQL: ambos motores soportan stddev_samp y stddev_pop
        -- nativos. Las macros existen para enforcement de estilo.
        -- Diferencia samp vs pop:
        --   samp: divide por (n-1), para muestras de una población
        --   pop:  divide por n, para la población completa
        {{ stddev_samp_xdb('balance') }} as balance_stddev_sample,
        {{ stddev_pop_xdb('balance') }} as balance_stddev_population,

        -- Agregadas estándar para comparar
        avg(balance) as avg_balance,
        sum(balance) as total_balance

    from {{ ref('compat_test_users') }}
    where balance is not null
    group by country_code

),

-- ─── corr_xdb(y, x) ──────────────────────────────────────────
-- Coeficiente de correlación lineal de Pearson entre dos columnas.
-- Útil para: análisis exploratorio, detección de relaciones.
-- Para que tenga sentido necesitamos varios puntos por país.
country_internal_corr as (

    select
        country_code,
        -- Correlación entre id y balance (proxy de "antigüedad de signup vs balance").
        -- En este dataset es ruido por la cantidad de filas, pero muestra el patrón.
        {{ corr_xdb('id', 'balance') }} as id_balance_corr
    from {{ ref('compat_test_users') }}
    where balance is not null
    group by country_code
    having count(*) >= 2

)

select
    c.country_code,
    c.users_count,
    c.median_balance,
    c.median_disc_balance,
    c.p25_balance,
    c.p75_balance,
    c.p95_balance,
    c.approx_unique_emails,
    c.balance_stddev_sample,
    c.balance_stddev_population,
    c.avg_balance,
    c.total_balance,

    -- ─── ratio_to_report(col, partition_by, order_by) ────────
    -- Función ANALÍTICA (window): porcentaje del total.
    -- Redshift: ratio_to_report nativo.
    -- Postgres: emulado con sum() over.
    -- Cuándo usar: distribuciones porcentuales, % del total por categoría.
    {{ ratio_to_report('total_balance') }} as country_share_of_total,

    -- Con partition_by: % del país sobre los países con count >= 2
    {{ ratio_to_report('total_balance',
                        partition_by='case when users_count >= 2 then 1 else 0 end') }}
        as share_within_size_group,

    coalesce(corr.id_balance_corr, 0) as id_balance_corr

from by_country c
left join country_internal_corr corr using (country_code)
