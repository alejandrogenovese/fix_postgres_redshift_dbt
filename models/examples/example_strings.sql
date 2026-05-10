{{ config(
    materialized='table',
    tags=['compat_examples']
) }}

-- ============================================================
-- example_strings.sql
-- Cubre TODAS las macros de cross_db/strings.sql
-- ============================================================
-- Macros ejercitadas:
--   len, charindex, concat_n, listagg, listagg_distinct,
--   split_part_xdb, left_xdb, right_xdb, lpad_xdb, rpad_xdb,
--   quote_literal_xdb
-- ============================================================

with per_user as (

    select
        id,
        first_name,
        last_name,
        email,
        country_code,
        tags_csv,

        -- ─── len(col) ────────────────────────────────────────
        -- Alias de length(). Existe porque Redshift soporta LEN
        -- como alias y Postgres no.
        -- Recomendación nueva: usar dbt.length() directo.
        {{ len('first_name') }} as first_name_len,
        {{ len('email') }} as email_len,

        -- ─── charindex(needle, haystack) ─────────────────────
        -- Equivalente a position(needle in haystack). 1-based.
        -- 0 si no encuentra.
        {{ charindex("'@'", 'email') }} as at_pos,
        {{ charindex("'.'", 'email') }} as dot_pos,

        -- ─── concat_n(...) ───────────────────────────────────
        -- CONCAT con N argumentos. ⚠ El CONCAT de Redshift solo
        -- acepta 2; esta es la primera macro que el equipo escribió.
        -- En Redshift se renderiza con || y coalesce; en Postgres usa concat().
        -- ⚠ Los strings literales se pasan con comillas dobles afuera y
        -- comillas simples adentro: "' '"  o  '\'\'' (más feo).
        {{ concat_n('first_name', "' '", 'last_name') }} as full_name,
        {{ concat_n('first_name', "' <'", 'email', "'>'") }} as full_name_email,
        {{ concat_n('country_code', "':'", 'id::varchar') }} as country_id_code,

        -- ─── left_xdb / right_xdb ────────────────────────────
        -- Wrappers idénticos en ambos motores. Existen para
        -- enforcement (forzar uso de la macro vs función nativa).
        {{ left_xdb('first_name', 3) }} as first_3_chars,
        {{ right_xdb('email', 10) }} as last_10_chars_email,

        -- ─── lpad_xdb / rpad_xdb (col, length, pad) ──────────
        -- Pad por izquierda/derecha. Casteo a varchar para evitar
        -- error en Redshift cuando la columna es text (que no existe
        -- realmente, es varchar(256)).
        {{ lpad_xdb('country_code', 5, '*') }} as country_lpad,
        {{ rpad_xdb('country_code', 5, '_') }} as country_rpad,
        {{ lpad_xdb('id::varchar', 6, '0') }} as id_zero_padded,

        -- ─── split_part_xdb(col, delim, n) ───────────────────
        -- Wrapper sobre split_part. Existe para consistencia de naming.
        -- Útil para tags_csv, paths, dominios de email.
        {{ split_part_xdb('email', '@', 1) }} as email_user_part,
        {{ split_part_xdb('email', '@', 2) }} as email_domain_part,
        {{ split_part_xdb('tags_csv', ',', 1) }} as first_tag,

        -- ─── quote_literal_xdb(col) ──────────────────────────
        -- Escapa un valor para que sirva como literal SQL.
        -- Postgres tiene quote_literal() nativo; Redshift NO.
        -- La macro emula con replace() de comillas simples.
        -- Cuándo usarlo: construir SQL dinámico (raro en dbt) o
        -- generar scripts de carga.
        {{ quote_literal_xdb('first_name') }} as first_name_quoted,

        tags_csv

    from {{ ref('compat_test_users') }}

)

-- ─── listagg / listagg_distinct ─────────────────────────────
-- Concatenación agregada. Diferencia clave entre motores:
--   Redshift: listagg(col, sep) within group (order by ...)
--   Postgres: string_agg(col::text, sep order by ...)
-- La macro abstrae esa diferencia con order_by opcional.
-- listagg_distinct = mismo pero con DISTINCT.

select
    country_code,
    count(*) as users_count,
    {{ listagg('first_name', ', ', 'first_name') }}
        as users_alphabetical,

    {{ listagg('email', '; ', 'email') }}
        as emails_alphabetical,

    -- listagg_distinct: deduplica antes de concatenar
    {{ listagg_distinct("split_part(email, '@', 2)", ', ', "split_part(email, '@', 2)") }}
        as distinct_email_domains

from per_user
where email is not null
group by country_code
