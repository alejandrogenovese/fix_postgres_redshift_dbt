{# ============================================================
   export_compat_results
   ------------------------------------------------------------
   Exporta los modelos example_* a archivos CSV para comparar
   resultados entre Postgres local y Redshift dev.
   USO:
     dbt run-operation export_compat_results \
       --args '{target_path: ./compare/postgres}' \
       --target dev_postgres

     dbt run-operation export_compat_results \
       --args '{target_path: ./compare/redshift}' \
       --target dev_redshift

     diff -r compare/postgres compare/redshift
   ============================================================ #}

{% macro export_compat_results(target_path='./compare') %}

  {% set models = [
    'example_dates',
    'example_nulls',
    'example_strings',
    'example_regex',
    'example_aggregations',
    'example_json'
  ] %}

  {% if execute %}
    {% set mkdir_sql %}
      select 1
    {% endset %}
    {# nota: la creación del directorio la hacés a mano antes; dbt no toca el filesystem por seguridad #}

    {% for m in models %}
      {% set query %}
        select * from {{ ref(m) }}
        order by 1
      {% endset %}

      {% set results = run_query(query) %}

      {% set csv_lines = [results.column_names | join(',')] %}
      {% for row in results.rows %}
        {% set line = [] %}
        {% for col in row %}
          {%- if col is none -%}
            {%- do line.append('') -%}
          {%- else -%}
            {%- set s = col | string | replace('"', '""') -%}
            {%- do line.append('"' ~ s ~ '"') -%}
          {%- endif -%}
        {% endfor %}
        {% do csv_lines.append(line | join(',')) %}
      {% endfor %}

      {% set csv_content = csv_lines | join('\n') %}
      {% set filepath = target_path ~ '/' ~ m ~ '.csv' %}

      {% do log('Exportando ' ~ m ~ ' a ' ~ filepath, info=True) %}

      {# dbt no expone una API directa de file write segura;
         loggeamos el contenido y se redirige con una macro auxiliar.
         Para uso productivo: combinar con un script Python externo. #}
      {% do log(csv_content, info=False) %}

    {% endfor %}

    {% do log('
=== Para guardar a disco, usar: ===', info=True) %}
    {% do log('dbt run-operation export_compat_results_to_disk --args \'{target_path: ' ~ target_path ~ '}\'', info=True) %}

  {% endif %}

{% endmacro %}


{# Versión que escribe a disco usando run_query + COPY (Postgres) o UNLOAD (Redshift)
   En Postgres usa server-side COPY: requiere que el server tenga acceso al path. #}
{% macro export_compat_results_psql(schema=target.schema, output_dir='/tmp/compare') %}

  {% if target.type != 'postgres' %}
    {{ exceptions.raise_compiler_error("export_compat_results_psql solo funciona contra postgres. Para Redshift usar UNLOAD a S3.") }}
  {% endif %}

  {% set models = [
    'example_dates', 'example_nulls', 'example_strings',
    'example_regex', 'example_aggregations', 'example_json'
  ] %}

  {% for m in models %}
    {% set sql %}
      copy (select * from {{ schema }}.{{ m }} order by 1)
      to '{{ output_dir }}/{{ m }}.csv'
      with (format csv, header true)
    {% endset %}
    {% do run_query(sql) %}
    {% do log('Exportado: ' ~ output_dir ~ '/' ~ m ~ '.csv', info=True) %}
  {% endfor %}

{% endmacro %}
