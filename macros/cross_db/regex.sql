{# ============================================================
   Macros cross-db: expresiones regulares
   ------------------------------------------------------------
   Postgres y Redshift usan POSIX regex pero las funciones difieren:
     - Postgres: regexp_matches, regexp_replace, substring(... from pattern)
     - Redshift: regexp_substr, regexp_count, regexp_instr,
                 regexp_replace
   ATENCIÓN: las semánticas de captura, flags y multibyte tienen
   diferencias sutiles. Validar caso por caso modelos críticos.
   ============================================================ #}


{# REGEXP_SUBSTR(col, pattern[, position[, occurrence]])
   Devuelve la primera ocurrencia matched (o el N-ésima en Redshift).
   Postgres no soporta 'position' ni 'occurrence' nativamente: para
   occurrence > 1 usamos regexp_matches con array indexing. #}
{% macro regexp_substr(col, pattern, position=1, occurrence=1) %}
  {%- if target.type == 'redshift' -%}
    regexp_substr({{ col }}, '{{ pattern }}', {{ position }}, {{ occurrence }})
  {%- else -%}
    {%- if occurrence | int == 1 and position | int == 1 -%}
      substring({{ col }} from '{{ pattern }}')
    {%- else -%}
      (array(
        select (regexp_matches(substring({{ col }} from {{ position }}), '{{ pattern }}', 'g'))[1]
      ))[{{ occurrence }}]
    {%- endif -%}
  {%- endif -%}
{% endmacro %}


{# REGEXP_COUNT(col, pattern)
   Cuenta ocurrencias del patrón. #}
{% macro regexp_count(col, pattern) %}
  {%- if target.type == 'redshift' -%}
    regexp_count({{ col }}, '{{ pattern }}')
  {%- else -%}
    coalesce(
      (select count(*) from regexp_matches({{ col }}, '{{ pattern }}', 'g')),
      0
    )
  {%- endif -%}
{% endmacro %}


{# REGEXP_INSTR(col, pattern)
   Devuelve la posición (1-based) de la primera ocurrencia.
   Postgres no tiene equivalente directo; emulamos con substring + position. #}
{% macro regexp_instr(col, pattern) %}
  {%- if target.type == 'redshift' -%}
    regexp_instr({{ col }}, '{{ pattern }}')
  {%- else -%}
    coalesce(
      position(substring({{ col }} from '{{ pattern }}') in {{ col }}),
      0
    )
  {%- endif -%}
{% endmacro %}


{# REGEXP_REPLACE: ambos motores lo soportan, pero con diferencias en flags.
   Redshift: 4to argumento son flags ('i', 'g', etc.) en algunas versiones.
   Postgres: 4to argumento son flags como string ('gi'). #}
{% macro regexp_replace_xdb(col, pattern, replacement='', flags='g') %}
  {%- if target.type == 'redshift' -%}
    regexp_replace({{ col }}, '{{ pattern }}', '{{ replacement }}')
  {%- else -%}
    regexp_replace({{ col }}, '{{ pattern }}', '{{ replacement }}', '{{ flags }}')
  {%- endif -%}
{% endmacro %}


{# Detección rápida: ¿matchea el patrón? (booleano)
   Postgres: operador ~. Redshift: regexp_count > 0 o ~. #}
{% macro regexp_matches_xdb(col, pattern) %}
  {%- if target.type == 'redshift' -%}
    ({{ col }} ~ '{{ pattern }}')
  {%- else -%}
    ({{ col }} ~ '{{ pattern }}')
  {%- endif -%}
{% endmacro %}
