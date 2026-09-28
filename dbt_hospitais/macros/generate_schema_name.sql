{# Usa o nome do schema exatamente como configurado (silver / gold),
   em vez do padrão do dbt "<schema_do_target>_<schema_custom>". #}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}{{ target.schema }}{%- else -%}{{ custom_schema_name | trim }}{%- endif -%}
{%- endmacro %}
