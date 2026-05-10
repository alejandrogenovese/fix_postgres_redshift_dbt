{{ config(
    materialized='table',
    tags=['compat_examples']
) }}

-- ============================================================
-- example_regex.sql
-- Cubre TODAS las macros de cross_db/regex.sql
-- ============================================================
-- Macros ejercitadas:
--   regexp_substr, regexp_count, regexp_instr,
--   regexp_replace_xdb, regexp_matches_xdb
-- ============================================================
--
-- ⚠ Warning del documento de análisis:
-- Postgres y Redshift usan POSIX regex pero las semánticas de
-- captura, flags y multibyte tienen diferencias sutiles.
-- Validar caso por caso modelos críticos.

select
    id,
    email,
    tags_csv,

    -- ─── regexp_matches_xdb(col, pattern) → boolean ──────────
    -- Devuelve true/false si el patrón matchea.
    -- Ambos motores usan el operador ~ (POSIX); la macro existe
    -- para consistencia de naming.
    -- Caso clásico: validación de formato.
    {{ regexp_matches_xdb('email', '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$') }}
        as is_valid_email_format,

    {{ regexp_matches_xdb('tags_csv', '\\bpremium\\b') }}
        as has_premium_tag,

    {{ regexp_matches_xdb('first_name', '^[A-ZÁÉÍÓÚÑ]') }}
        as starts_with_capital,

    -- ─── regexp_substr(col, pattern[, position, occurrence]) ─
    -- Extrae el primer match del patrón.
    -- Args opcionales (position, occurrence) solo Redshift soporta
    -- nativos; en Postgres la macro emula con regexp_matches.
    -- Caso clásico: extraer dominio, código, primer dígito.
    {{ regexp_substr('email', '@(.+)$') }}
        as email_with_at_sign,

    {{ regexp_substr('email', '[A-Za-z0-9.-]+\\.[A-Za-z]+$') }}
        as email_domain,

    -- Extraer el primer número que aparezca
    {{ regexp_substr('first_name', '[0-9]+') }}
        as first_number_in_name,

    -- ─── regexp_count(col, pattern) → int ────────────────────
    -- Cuenta cuántas veces matchea el patrón en el string.
    -- Postgres no tiene regexp_count nativo; la macro emula con
    -- regexp_matches + count.
    {{ regexp_count('tags_csv', ',') }}
        as tag_separator_count,

    {{ regexp_count('email', '[0-9]') }}
        as digits_in_email,

    -- ─── regexp_instr(col, pattern) → int ────────────────────
    -- Posición (1-based) de la primera ocurrencia. 0 si no matchea.
    -- Postgres NO tiene equivalente directo; la macro emula con
    -- substring + position. ⚠ Casos con position/occurrence custom
    -- no están cubiertos: requiere reescritura.
    {{ regexp_instr('email', '@') }}
        as at_position_via_regex,

    {{ regexp_instr('first_name', '[áéíóúñÁÉÍÓÚÑ]') }}
        as first_accent_pos,

    -- ─── regexp_replace_xdb(col, pattern, replacement, flags) ─
    -- Reemplaza matches. ⚠ El 4to argumento (flags) difiere entre
    -- motores: Redshift no siempre lo acepta. La macro lo manda
    -- solo a Postgres.
    -- Casos: anonimización, normalización, limpieza.
    {{ regexp_replace_xdb('email', '[0-9]', '#') }}
        as email_anon_digits,

    {{ regexp_replace_xdb('email', '@.*$', '@***') }}
        as email_anon_domain,

    -- Normalizar acentos a su forma sin tilde (caso simple)
    {{ regexp_replace_xdb('first_name', '[áàâ]', 'a') }}
        as first_name_no_a_accents

from {{ ref('compat_test_users') }}
where email is not null
