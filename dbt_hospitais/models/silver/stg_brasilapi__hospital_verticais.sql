{{ config(materialized='view') }}

-- Explode verticals: 1 linha por hospital x vertical (habilitação)
select
    h.hospital_id,
    v.codigo_vertical
from {{ ref('stg_brasilapi__hospitais_json') }} h
cross join lateral jsonb_array_elements_text(coalesce(h.payload->'verticals', '[]'::jsonb)) as v(codigo_vertical)
