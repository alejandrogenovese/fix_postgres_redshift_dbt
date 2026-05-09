{# ============================================================
   Macros cross-db: arrays / UNNEST
   ------------------------------------------------------------
   ATENCIÓN: el unnest de SUPER en Redshift y de arrays nativos en
   Postgres difieren tanto en sintaxis como en semántica.
   Estas macros cubren los casos simples; los complejos (anidados,
   con seq, sobre campos struct) requieren reescritura específica.
   ============================================================ #}


{# UNNEST de array unidimensional en FROM
   Uso (en el FROM):
     from {{ ref('source_table') }} t,
          {{ unnest_array('t.tags', 'tag') }}
   Genera:
     - Redshift: t.tags as tag at seq
     - Postgres: unnest(t.tags) as tag #}
{% macro unnest_array(col, alias='value', with_ordinality=false) %}
  {%- if target.type == 'redshift' -%}
    {{ col }} as {{ alias }}{% if with_ordinality %} at seq{% endif %}
  {%- else -%}
    {%- if with_ordinality -%}
    unnest({{ col }}) with ordinality as {{ alias }}({{ alias }}, seq)
    {%- else -%}
    unnest({{ col }}) as {{ alias }}
    {%- endif -%}
  {%- endif -%}
{% endmacro %}


{# Construcción de array literal portable
   Uso: {{ array_literal("'a'", "'b'", "'c'") }} #}
{% macro array_literal() %}
  {%- if target.type == 'redshift' -%}
    array({{ varargs | join(', ') }})
  {%- else -%}
    array[{{ varargs | join(', ') }}]
  {%- endif -%}
{% endmacro %}


{# Construcción de un struct/object portable.
   Limitada al caso simple key/value.
   Uso: {{ object_construct('id', 'user_id', 'name', 'user_name') }} #}
{% macro object_construct() %}
  {%- set args = varargs -%}
  {%- if (args | length) is odd -%}
    {{ exceptions.raise_compiler_error("object_construct requiere pares key/value") }}
  {%- endif -%}
  {%- if target.type == 'redshift' -%}
    object(
    {%- for i in range(0, args | length, 2) -%}
      '{{ args[i] }}', {{ args[i+1] }}{% if not loop.last %}, {% endif %}
    {%- endfor -%}
    )
  {%- else -%}
    jsonb_build_object(
    {%- for i in range(0, args | length, 2) -%}
      '{{ args[i] }}', {{ args[i+1] }}{% if not loop.last %}, {% endif %}
    {%- endfor -%}
    )
  {%- endif -%}
{% endmacro %}
