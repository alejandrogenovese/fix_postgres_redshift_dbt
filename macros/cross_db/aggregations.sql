{# ============================================================
   Macros cross-db: agregadas y analíticas
   ------------------------------------------------------------
   MEDIAN, APPROXIMATE COUNT DISTINCT y RATIO_TO_REPORT son
   exclusivos de Redshift; Postgres requiere emulación.
   ============================================================ #}


{# MEDIAN(col)
   Redshift: función nativa, semánticamente equivalente a
   PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY col).
   Postgres: usar percentile_cont. #}
{% macro median(col) %}
  {%- if target.type == 'redshift' -%}
    median({{ col }})
  {%- else -%}
    percentile_cont(0.5) within group (order by {{ col }})
  {%- endif -%}
{% endmacro %}


{# PERCENTILE_CONT(p) WITHIN GROUP (ORDER BY col)
   Ambos motores lo soportan idéntico. Macro para enforcement de estilo. #}
{% macro percentile_cont(col, p) %}
  percentile_cont({{ p }}) within group (order by {{ col }})
{% endmacro %}


{# PERCENTILE_DISC(p) WITHIN GROUP (ORDER BY col)
   Ambos motores lo soportan. #}
{% macro percentile_disc(col, p) %}
  percentile_disc({{ p }}) within group (order by {{ col }})
{% endmacro %}


{# APPROXIMATE COUNT(DISTINCT col)
   Redshift: usa HyperLogLog, mucho más rápido en grandes volúmenes.
   Postgres: fallback a count(distinct), exacto pero más lento.
   Si tenés la extensión postgresql-hll instalada, podés cambiar
   la rama de postgres por hll_count_distinct. #}
{% macro approximate_count_distinct(col) %}
  {%- if target.type == 'redshift' -%}
    approximate count(distinct {{ col }})
  {%- else -%}
    count(distinct {{ col }})
  {%- endif -%}
{% endmacro %}


{# RATIO_TO_REPORT(col) OVER (PARTITION BY ...)
   Redshift: función analítica nativa.
   Postgres: emular con SUM() OVER + división. #}
{% macro ratio_to_report(col, partition_by=none, order_by=none) %}
  {%- if target.type == 'redshift' -%}
    ratio_to_report({{ col }}) over (
      {%- if partition_by %}partition by {{ partition_by }}{%- endif -%}
      {%- if order_by %} order by {{ order_by }}{%- endif -%}
    )
  {%- else -%}
    (({{ col }})::numeric / nullif(sum({{ col }}) over (
      {%- if partition_by %}partition by {{ partition_by }}{%- endif -%}
      {%- if order_by %} order by {{ order_by }}{%- endif -%}
    ), 0))
  {%- endif -%}
{% endmacro %}


{# STDDEV / VAR portables: ambos motores soportan stddev_samp,
   stddev_pop, var_samp, var_pop. Macros para enforcement. #}
{% macro stddev_samp_xdb(col) %}
  stddev_samp({{ col }})
{% endmacro %}

{% macro stddev_pop_xdb(col) %}
  stddev_pop({{ col }})
{% endmacro %}


{# COVAR_SAMP / CORR / REGR_*: Redshift los soporta;
   Postgres también los soporta nativamente desde hace muchas versiones. #}
{% macro corr_xdb(y, x) %}
  corr({{ y }}, {{ x }})
{% endmacro %}


{# CUME_DIST / PERCENT_RANK / NTILE / RANK: window functions estándar,
   ambos motores idénticos. Sin macro necesaria. #}
