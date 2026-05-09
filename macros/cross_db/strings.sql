{# ============================================================
   Macros cross-db: funciones de string
   ------------------------------------------------------------
   dbt-core ya provee:
     dbt.length, dbt.position, dbt.replace, dbt.right,
     dbt.split_part, dbt.concat, dbt.listagg
   Acá cubrimos lo que NO está en dbt-core o donde el comportamiento
   default de dbt no encaja.
   ============================================================ #}


{# LEN(col) -> LENGTH en ambos.
   Redshift soporta LEN como alias; Postgres NO.
   Preferí dbt.length() en código nuevo. #}
{% macro len(col) %}
  length({{ col }})
{% endmacro %}


{# CHARINDEX(needle, haystack) -> POSITION en ambos #}
{% macro charindex(needle, haystack) %}
  position({{ needle }} in {{ haystack }})
{% endmacro %}


{# CONCAT con N argumentos
   Redshift CONCAT solo acepta 2 argumentos. Postgres acepta N.
   Esta macro normaliza el comportamiento usando || con coalesce()
   para emular el descarte de NULLs que hace concat() en Postgres.
   Uso:
     {{ concat_n("first_name", "' '", "last_name") }}
#}
{% macro concat_n() %}
  {%- set args = varargs -%}
  {%- if args | length == 0 -%}
    ''
  {%- elif target.type == 'redshift' -%}
    (
    {%- for arg in args -%}
      coalesce(({{ arg }})::varchar, '')
      {%- if not loop.last %} || {% endif -%}
    {%- endfor -%}
    )
  {%- else -%}
    concat({{ args | join(', ') }})
  {%- endif -%}
{% endmacro %}


{# LISTAGG con order_by opcional.
   dbt.listagg existe pero la firma no es la más cómoda; esta versión
   es más directa para el caso típico. #}
{% macro listagg(col, sep=',', order_by=none) %}
  {%- if target.type == 'redshift' -%}
    listagg({{ col }}, '{{ sep }}')
    {%- if order_by %} within group (order by {{ order_by }}){%- endif %}
  {%- else -%}
    string_agg(({{ col }})::text, '{{ sep }}'
    {%- if order_by %} order by {{ order_by }}{%- endif -%}
    )
  {%- endif -%}
{% endmacro %}


{# LISTAGG con DISTINCT.
   Redshift listagg NO soporta distinct directo dentro de la función;
   se emula con un subquery. Postgres string_agg sí soporta distinct. #}
{% macro listagg_distinct(col, sep=',', order_by=none) %}
  {%- if target.type == 'redshift' -%}
    listagg(distinct {{ col }}, '{{ sep }}')
    {%- if order_by %} within group (order by {{ order_by }}){%- endif %}
  {%- else -%}
    string_agg(distinct ({{ col }})::text, '{{ sep }}'
    {%- if order_by %} order by {{ order_by }}{%- endif -%}
    )
  {%- endif -%}
{% endmacro %}


{# SPLIT_PART portable -> dbt.split_part también lo cubre.
   Esta versión existe por si querés un nombre consistente con tu naming. #}
{% macro split_part_xdb(col, delimiter, part_number) %}
  split_part({{ col }}, '{{ delimiter }}', {{ part_number }})
{% endmacro %}


{# LEFT/RIGHT portable: ambos motores los soportan idéntico #}
{% macro left_xdb(col, n) %}
  left({{ col }}, {{ n }})
{% endmacro %}

{% macro right_xdb(col, n) %}
  right({{ col }}, {{ n }})
{% endmacro %}


{# LPAD / RPAD portable: ambos motores los soportan idéntico #}
{% macro lpad_xdb(col, length, pad=' ') %}
  lpad(({{ col }})::varchar, {{ length }}, '{{ pad }}')
{% endmacro %}

{% macro rpad_xdb(col, length, pad=' ') %}
  rpad(({{ col }})::varchar, {{ length }}, '{{ pad }}')
{% endmacro %}


{# QUOTE_LITERAL: Postgres lo soporta nativo; Redshift NO.
   Si necesitás escapar dinámicamente, hacelo en Jinja con replace,
   no en SQL runtime. Esta macro emula el caso simple. #}
{% macro quote_literal_xdb(s) %}
  '''' || replace({{ s }}, '''', '''''') || ''''
{% endmacro %}
