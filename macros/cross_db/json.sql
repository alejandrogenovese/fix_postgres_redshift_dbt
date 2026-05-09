{# ============================================================
   Macros cross-db: JSON / SUPER
   ------------------------------------------------------------
   Redshift usa el tipo SUPER (PartiQL) y un set de funciones JSON_*.
   Postgres usa JSONB con operadores ->, ->>, #>, #>>.
   IMPORTANTE: el documento de análisis señala que datos
   semi-estructurados deberían ir al lake (Iceberg/S3), por lo que
   el uso real de estas macros en modelos dbt debería ser limitado.
   ============================================================ #}


{# JSON_PARSE: convierte texto JSON a SUPER/JSONB #}
{% macro json_parse(json_string) %}
  {%- if target.type == 'redshift' -%}
    json_parse({{ json_string }})
  {%- else -%}
    ({{ json_string }})::jsonb
  {%- endif -%}
{% endmacro %}


{# JSON_EXTRACT_PATH_TEXT(col, 'a', 'b', ...)
   Devuelve el valor TEXT del path. N argumentos variables.
   Uso:
     {{ json_extract_path_text('payload', 'user', 'address', 'city') }} #}
{% macro json_extract_path_text(col) %}
  {%- set path = varargs -%}
  {%- if path | length == 0 -%}
    {{ exceptions.raise_compiler_error("json_extract_path_text requiere al menos un key") }}
  {%- endif -%}
  {%- if target.type == 'redshift' -%}
    json_extract_path_text({{ col }},
    {%- for k in path %} '{{ k }}'{% if not loop.last %},{% endif %}{% endfor %})
  {%- else -%}
    (({{ col }})::jsonb #>> '{
      {%- for k in path -%}{{ k }}{% if not loop.last %},{% endif %}{%- endfor -%}
    }')
  {%- endif -%}
{% endmacro %}


{# JSON_EXTRACT_ARRAY_ELEMENT_TEXT(col, idx)
   Devuelve el elemento idx (0-based) de un array JSON, como texto. #}
{% macro json_extract_array_element_text(col, idx) %}
  {%- if target.type == 'redshift' -%}
    json_extract_array_element_text({{ col }}, {{ idx }})
  {%- else -%}
    ((({{ col }})::jsonb -> {{ idx }})#>>'{}')
  {%- endif -%}
{% endmacro %}


{# Acceso a path tipado JSONB / SUPER (devuelve JSONB / SUPER, no texto)
   Uso:
     {{ json_path('payload', ['user', 'address']) }}
   Path debe ser una lista Python literal en Jinja. #}
{% macro json_path(col, path) %}
  {%- if target.type == 'redshift' -%}
    {{ col }}{% for k in path %}.{{ k }}{% endfor %}
  {%- else -%}
    (({{ col }})::jsonb #> '{
      {%- for k in path -%}{{ k }}{% if not loop.last %},{% endif %}{%- endfor -%}
    }')
  {%- endif -%}
{% endmacro %}


{# IS_VALID_JSON(col)
   Redshift tiene la función nativa.
   Postgres requiere la función helper is_valid_json_pg de la capa
   de compatibilidad (compat/install_postgres_compat.sql). #}
{% macro is_valid_json(col) %}
  {%- if target.type == 'redshift' -%}
    is_valid_json({{ col }})
  {%- else -%}
    is_valid_json_pg({{ col }})
  {%- endif -%}
{% endmacro %}


{# IS_VALID_JSON_ARRAY(col) #}
{% macro is_valid_json_array(col) %}
  {%- if target.type == 'redshift' -%}
    is_valid_json_array({{ col }})
  {%- else -%}
    is_valid_json_array_pg({{ col }})
  {%- endif -%}
{% endmacro %}


{# JSON_TYPEOF / JSONB_TYPEOF #}
{% macro json_typeof(col) %}
  {%- if target.type == 'redshift' -%}
    json_typeof({{ col }})
  {%- else -%}
    jsonb_typeof(({{ col }})::jsonb)
  {%- endif -%}
{% endmacro %}


{# Tamaño de un array JSON / SUPER #}
{% macro json_array_length(col) %}
  {%- if target.type == 'redshift' -%}
    json_array_length({{ col }})
  {%- else -%}
    jsonb_array_length(({{ col }})::jsonb)
  {%- endif -%}
{% endmacro %}
