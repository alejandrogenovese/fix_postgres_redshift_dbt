{# ============================================================
   Macros cross-db: fecha y tiempo
   ------------------------------------------------------------
   dbt-core ya provee:
     dbt.dateadd, dbt.datediff, dbt.date_trunc,
     dbt.last_day, dbt.current_timestamp
   Acá cubrimos lo que NO está en dbt-core.
   ============================================================ #}

{# GETDATE() -> en código nuevo preferí dbt.current_timestamp() #}
{% macro getdate() %}
  {%- if target.type == 'redshift' -%}
    getdate()
  {%- else -%}
    current_timestamp::timestamp
  {%- endif -%}
{% endmacro %}


{# SYSDATE: en Redshift devuelve el timestamp del transaction start.
   Equivalente más cercano en Postgres: transaction_timestamp(). #}
{% macro sysdate() %}
  {%- if target.type == 'redshift' -%}
    sysdate
  {%- else -%}
    transaction_timestamp()::timestamp
  {%- endif -%}
{% endmacro %}


{# CONVERT_TIMEZONE(tz_from, tz_to, ts) #}
{% macro convert_timezone(tz_from, tz_to, ts) %}
  {%- if target.type == 'redshift' -%}
    convert_timezone('{{ tz_from }}', '{{ tz_to }}', {{ ts }})
  {%- else -%}
    (({{ ts }})::timestamp at time zone '{{ tz_from }}') at time zone '{{ tz_to }}'
  {%- endif -%}
{% endmacro %}


{# CONVERT_TIMEZONE(tz_to, ts) — versión 2 args, asume ts en UTC #}
{% macro convert_timezone_2(tz_to, ts) %}
  {%- if target.type == 'redshift' -%}
    convert_timezone('{{ tz_to }}', {{ ts }})
  {%- else -%}
    (({{ ts }}) at time zone '{{ tz_to }}')::timestamp
  {%- endif -%}
{% endmacro %}


{# ADD_MONTHS(col, n)
   Ambos motores ajustan al último día si el destino no existe. #}
{% macro add_months(col, n) %}
  {%- if target.type == 'redshift' -%}
    add_months({{ col }}, {{ n }})
  {%- else -%}
    (({{ col }})::timestamp + interval '{{ n }} month')
  {%- endif -%}
{% endmacro %}


{# MONTHS_BETWEEN(a, b) - versión entera
   OJO: Redshift devuelve numeric con decimales. Si necesitás
   la fracción de mes, usar months_between_decimal. #}
{% macro months_between(a, b) %}
  {%- if target.type == 'redshift' -%}
    months_between({{ a }}, {{ b }})
  {%- else -%}
    (extract(year from age({{ a }}::timestamp, {{ b }}::timestamp)) * 12
     + extract(month from age({{ a }}::timestamp, {{ b }}::timestamp)))
  {%- endif -%}
{% endmacro %}


{# MONTHS_BETWEEN con decimales (más fiel a Redshift) #}
{% macro months_between_decimal(a, b) %}
  {%- if target.type == 'redshift' -%}
    months_between({{ a }}, {{ b }})
  {%- else -%}
    (
      (extract(year from age({{ a }}::timestamp, {{ b }}::timestamp)) * 12
       + extract(month from age({{ a }}::timestamp, {{ b }}::timestamp)))::numeric
      + (extract(day from age({{ a }}::timestamp, {{ b }}::timestamp))::numeric / 31.0)
    )
  {%- endif -%}
{% endmacro %}


{# TRUNC(timestamp) -> en Redshift devuelve date.
   Postgres no soporta trunc() sobre timestamp directo. #}
{% macro trunc_to_date(col) %}
  {%- if target.type == 'redshift' -%}
    trunc({{ col }})
  {%- else -%}
    ({{ col }})::date
  {%- endif -%}
{% endmacro %}


{# Literal timestamp portable (algunos linters se quejan con TIMESTAMP '...') #}
{% macro ts_literal(s) %}
  cast('{{ s }}' as timestamp)
{% endmacro %}


{# EXTRACT/DATE_PART portable, ambos motores lo soportan idéntico.
   Existe solo para enforcement de estilo en linter. #}
{% macro date_part_xdb(part, col) %}
  extract({{ part }} from {{ col }})
{% endmacro %}
