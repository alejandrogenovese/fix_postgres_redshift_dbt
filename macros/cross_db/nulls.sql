{# ============================================================
   Macros cross-db: NULL y condicionales
   ------------------------------------------------------------
   NVL, NVL2 y DECODE son herencia Oracle/Teradata. Redshift los
   soporta nativamente; Postgres no.
   La capa de compatibilidad SQL (compat/install_postgres_compat.sql)
   crea funciones NVL/NVL2 reales en Postgres, así que estas macros
   son útiles solo si NO querés depender de la capa SQL.
   ============================================================ #}


{# NVL(a, b) -> COALESCE(a, b) en ambos motores #}
{% macro nvl(a, b) %}
  coalesce({{ a }}, {{ b }})
{% endmacro %}


{# NVL2(a, b, c) -> si a IS NOT NULL devuelve b, sino c #}
{% macro nvl2(a, b, c) %}
  case when {{ a }} is not null then {{ b }} else {{ c }} end
{% endmacro %}


{# DECODE(expr, v1, r1, v2, r2, ..., default)
   Ejemplo:
     {{ decode('status', "'A'", "'Active'", "'I'", "'Inactive'", "'Unknown'") }}
   Genera:
     case status when 'A' then 'Active' when 'I' then 'Inactive' else 'Unknown' end
   Si la cantidad de args es par, no hay ELSE. #}
{% macro decode(expr) %}
  {%- set args = varargs -%}
  {%- if args | length < 2 -%}
    {{ exceptions.raise_compiler_error("decode() requiere al menos un par valor/resultado") }}
  {%- endif -%}
  {%- set has_default = (args | length) is odd -%}
  {%- set pairs_end = (args | length) - 1 if has_default else (args | length) -%}
  case {{ expr }}
  {%- for i in range(0, pairs_end, 2) %}
    when {{ args[i] }} then {{ args[i+1] }}
  {%- endfor %}
  {%- if has_default %}
    else {{ args[-1] }}
  {%- endif %}
  end
{% endmacro %}


{# NULLIF cross-db (es estándar SQL, ambos lo soportan).
   Existe para enforcement de estilo. #}
{% macro nullif_xdb(a, b) %}
  nullif({{ a }}, {{ b }})
{% endmacro %}


{# GREATEST/LEAST con tratamiento de NULL al estilo Redshift:
   Redshift y Postgres devuelven NULL si todos son NULL pero ignoran
   los NULL si hay al menos uno no nulo. Comportamiento idéntico.
   Macro pensada para enforcement de estilo. #}
{% macro greatest_xdb() %}
  greatest({{ varargs | join(', ') }})
{% endmacro %}

{% macro least_xdb() %}
  least({{ varargs | join(', ') }})
{% endmacro %}
