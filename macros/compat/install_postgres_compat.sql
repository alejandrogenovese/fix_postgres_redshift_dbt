{# ============================================================
   Capa de compatibilidad SQL para Postgres
   ------------------------------------------------------------
   Crea en el Postgres local funciones que emulan funciones
   Redshift-only. Permite escribir SQL "Redshift-style" y que
   funcione en local sin cambiar la consulta.
   USO: hookear como on-run-start en dbt_project.yml
     on-run-start:
       - "{{ install_postgres_compat() }}"
   La macro es idempotente (CREATE OR REPLACE).
   ============================================================ #}

{% macro install_postgres_compat() %}
  {% if target.type != 'postgres' %}
    {% do log("install_postgres_compat: target no es postgres, skip", info=False) %}
    {% do return('') %}
  {% endif %}

  {% set sql %}

    -- ============================================================
    -- FECHA / TIEMPO
    -- ============================================================

    create or replace function getdate()
    returns timestamp language sql immutable as $$
      select current_timestamp::timestamp
    $$;

    create or replace function dateadd(unit text, n int, ts timestamp)
    returns timestamp language plpgsql immutable as $$
    begin
      return case lower(unit)
        when 'year'    then ts + (n || ' year')::interval
        when 'quarter' then ts + (n*3 || ' month')::interval
        when 'month'   then ts + (n || ' month')::interval
        when 'week'    then ts + (n || ' week')::interval
        when 'day'     then ts + (n || ' day')::interval
        when 'hour'    then ts + (n || ' hour')::interval
        when 'minute'  then ts + (n || ' minute')::interval
        when 'second'  then ts + (n || ' second')::interval
        else null
      end;
    end;
    $$;

    -- DATEADD overload para date
    create or replace function dateadd(unit text, n int, d date)
    returns date language sql immutable as $$
      select (dateadd(unit, n, d::timestamp))::date
    $$;

    create or replace function datediff(unit text, a timestamp, b timestamp)
    returns bigint language plpgsql immutable as $$
    begin
      return case lower(unit)
        when 'year'    then extract(year from age(b, a))::bigint
        when 'quarter' then ((extract(year from age(b, a)) * 12
                            + extract(month from age(b, a))) / 3)::bigint
        when 'month'   then (extract(year from age(b, a)) * 12
                            + extract(month from age(b, a)))::bigint
        when 'week'    then ((b::date - a::date) / 7)::bigint
        when 'day'     then (b::date - a::date)::bigint
        when 'hour'    then (extract(epoch from (b - a)) / 3600)::bigint
        when 'minute'  then (extract(epoch from (b - a)) / 60)::bigint
        when 'second'  then extract(epoch from (b - a))::bigint
        else null
      end;
    end;
    $$;

    -- DATEDIFF overload para date
    create or replace function datediff(unit text, a date, b date)
    returns bigint language sql immutable as $$
      select datediff(unit, a::timestamp, b::timestamp)
    $$;

    create or replace function add_months(d timestamp, n int)
    returns timestamp language sql immutable as $$
      select d + (n || ' month')::interval
    $$;

    create or replace function add_months(d date, n int)
    returns date language sql immutable as $$
      select (d + (n || ' month')::interval)::date
    $$;

    create or replace function months_between(a timestamp, b timestamp)
    returns numeric language sql immutable as $$
      select (extract(year from age(a, b)) * 12
              + extract(month from age(a, b)))::numeric
    $$;

    create or replace function last_day(d timestamp)
    returns date language sql immutable as $$
      select (date_trunc('month', d) + interval '1 month - 1 day')::date
    $$;

    create or replace function last_day(d date)
    returns date language sql immutable as $$
      select last_day(d::timestamp)
    $$;

    create or replace function convert_timezone(tz_from text, tz_to text, ts timestamp)
    returns timestamp language sql immutable as $$
      select (ts at time zone tz_from) at time zone tz_to
    $$;

    create or replace function convert_timezone(tz_to text, ts timestamptz)
    returns timestamp language sql immutable as $$
      select (ts at time zone tz_to)::timestamp
    $$;

    -- TRUNC sobre timestamp -> date (no existe nativo en Postgres)
    create or replace function trunc(ts timestamp)
    returns date language sql immutable as $$
      select ts::date
    $$;

    -- ============================================================
    -- NULL / CONDICIONALES
    -- ============================================================

    create or replace function nvl(anyelement, anyelement)
    returns anyelement language sql immutable as $$
      select coalesce($1, $2)
    $$;

    create or replace function nvl2(anyelement, anyelement, anyelement)
    returns anyelement language sql immutable as $$
      select case when $1 is not null then $2 else $3 end
    $$;

    -- ============================================================
    -- STRING
    -- ============================================================

    create or replace function len(t text)
    returns int language sql immutable as $$
      select length(t)::int
    $$;

    create or replace function len(t varchar)
    returns int language sql immutable as $$
      select length(t)::int
    $$;

    create or replace function charindex(needle text, haystack text)
    returns int language sql immutable as $$
      select position(needle in haystack)
    $$;

    -- ============================================================
    -- REGEX
    -- ============================================================

    create or replace function regexp_count(t text, pattern text)
    returns int language sql immutable as $$
      select coalesce(
        (select count(*)::int from regexp_matches(t, pattern, 'g')),
        0
      )
    $$;

    create or replace function regexp_substr(t text, pattern text)
    returns text language sql immutable as $$
      select substring(t from pattern)
    $$;

    create or replace function regexp_instr(t text, pattern text)
    returns int language sql immutable as $$
      select coalesce(position(substring(t from pattern) in t), 0)
    $$;

    -- ============================================================
    -- AGREGADAS / ANALITICAS
    -- NOTA: MEDIAN como agregado no se puede definir trivialmente
    -- en Postgres. Usar la macro cross-db {{ median(col) }} en su lugar.
    -- ============================================================

    -- ============================================================
    -- JSON / SUPER (subset)
    -- ============================================================

    create or replace function is_valid_json_pg(t text)
    returns boolean language plpgsql immutable as $$
    begin
      perform t::jsonb;
      return true;
    exception when others then
      return false;
    end;
    $$;

    create or replace function is_valid_json_array_pg(t text)
    returns boolean language plpgsql immutable as $$
    declare j jsonb;
    begin
      j := t::jsonb;
      return jsonb_typeof(j) = 'array';
    exception when others then
      return false;
    end;
    $$;

    -- JSON_EXTRACT_PATH_TEXT versión 2 args (caso simple)
    create or replace function json_extract_path_text(j text, k1 text)
    returns text language sql immutable as $$
      select (j::jsonb #>> array[k1])
    $$;

    -- JSON_EXTRACT_PATH_TEXT versión 3 args
    create or replace function json_extract_path_text(j text, k1 text, k2 text)
    returns text language sql immutable as $$
      select (j::jsonb #>> array[k1, k2])
    $$;

    -- JSON_EXTRACT_PATH_TEXT versión 4 args
    create or replace function json_extract_path_text(j text, k1 text, k2 text, k3 text)
    returns text language sql immutable as $$
      select (j::jsonb #>> array[k1, k2, k3])
    $$;

    -- JSON_EXTRACT_ARRAY_ELEMENT_TEXT
    create or replace function json_extract_array_element_text(j text, idx int)
    returns text language sql immutable as $$
      select ((j::jsonb -> idx) #>> '{}')
    $$;

    -- JSON_ARRAY_LENGTH
    create or replace function json_array_length(j text)
    returns int language sql immutable as $$
      select jsonb_array_length(j::jsonb)
    $$;

  {% endset %}

  {% do run_query(sql) %}
  {% do log("✅ Capa de compatibilidad Postgres instalada", info=True) %}
{% endmacro %}
