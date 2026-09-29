{{ config(materialized='view') }}

-- Explode treatments: 1 linha por hospital x soro
select
    h.hospital_id,
    t.codigo_tratamento
from {{ ref('stg_brasilapi__hospitais_json') }} h
cross join lateral jsonb_array_elements_text(coalesce(h.payload->'treatments', '[]'::jsonb)) as t(codigo_tratamento)
