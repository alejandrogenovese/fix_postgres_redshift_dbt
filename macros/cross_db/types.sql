{# ============================================================
   Macros cross-db: tipos de datos
   ------------------------------------------------------------
   ⚠ Diferencias clave que el documento marcó como SILENCIOSAS:
     - TEXT en Redshift = VARCHAR(256), trunca silenciosamente
     - VARCHAR cuenta BYTES en Redshift, CARACTERES en Postgres
     - Strings UTF-8 multibyte requieren sobredimensionar
   Por eso la regla del equipo: NUNCA usar TEXT, siempre VARCHAR(n)
   explícito, y multiplicar tamaño x4 para cubrir multibyte.
   dbt-core ya provee dbt.type_string, dbt.type_int, etc.
   Estas macros son complementos para casos específicos.
   ============================================================ #}


{# VARCHAR seguro: aplica el factor x4 para multibyte automáticamente.
   Uso: {{ varchar_safe(100) }}  ->  varchar(400)
   Si querés evitar el factor, usá varchar_exact. #}
{% macro varchar_safe(n_chars, multibyte_factor=4) %}
  varchar({{ n_chars * multibyte_factor }})
{% endmacro %}


{# VARCHAR exacto en bytes (Redshift) o caracteres (Postgres).
   Cuidado: significa cosas distintas en cada motor. #}
{% macro varchar_exact(n) %}
  varchar({{ n }})
{% endmacro %}


{# VARCHAR MAX equivalente. Redshift soporta varchar(max)=65535.
   Postgres no tiene MAX; usar text para texto sin límite o un tope
   alto explícito. Convención de equipo: usar 65535 para alinear. #}
{% macro varchar_max() %}
  {%- if target.type == 'redshift' -%}
    varchar(max)
  {%- else -%}
    varchar(65535)
  {%- endif -%}
{% endmacro %}


{# CAST de texto a numérico tolerante.
   Redshift es estricto en cast; Postgres también desde versiones recientes.
   Esta macro devuelve NULL si el cast falla, en lugar de error. #}
{% macro try_cast_numeric(col) %}
  {%- if target.type == 'redshift' -%}
    case
      when {{ col }} ~ '^-?[0-9]+(\\.[0-9]+)?$'
      then {{ col }}::numeric
      else null
    end
  {%- else -%}
    case
      when {{ col }} ~ '^-?[0-9]+(\\.[0-9]+)?$'
      then {{ col }}::numeric
      else null
    end
  {%- endif -%}
{% endmacro %}


{# TRY_CAST a date #}
{% macro try_cast_date(col, format='YYYY-MM-DD') %}
  {%- if target.type == 'redshift' -%}
    case
      when {{ col }} is null then null
      else nullif(to_date({{ col }}, '{{ format }}'), null)
    end
  {%- else -%}
    case
      when {{ col }} is null then null
      else nullif(({{ col }})::date, null)
    end
  {%- endif -%}
{% endmacro %}


{# Boolean portable: ambos soportan boolean, pero el cast desde texto
   tiene reglas distintas (Redshift acepta 't'/'f', '1'/'0', 'true'/'false';
   Postgres es similar pero más estricto). #}
{% macro to_boolean(col) %}
  case
    when lower(trim(({{ col }})::varchar)) in ('t', 'true', '1', 'y', 'yes') then true
    when lower(trim(({{ col }})::varchar)) in ('f', 'false', '0', 'n', 'no') then false
    else null
  end
{% endmacro %}
