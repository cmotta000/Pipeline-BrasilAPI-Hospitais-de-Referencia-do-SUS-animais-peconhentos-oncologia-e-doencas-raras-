{{ config(materialized='view') }}

-- 1 linha por CIATOX (centro de informação e assistência toxicológica)
select
    (r.payload->>'id')::int                         as ciatox_id,
    upper(trim(r.payload->>'state_code'))           as uf,
    trim(r.payload->>'name')                        as nome,
    trim(r.payload->>'emergency_phone')             as telefone_emergencia,
    array(select jsonb_array_elements_text(coalesce(r.payload->'phones', '[]'::jsonb))) as telefones,
    r.payload->>'source_url'                        as url_fonte,
    (r.payload->>'synced_at')::timestamptz          as sincronizado_em,
    r.extraido_em
from {{ ref('brz_brasilapi__raw') }} r
join {{ ref('stg_brasilapi__ultima_extracao') }} e
  on e.id_extracao = r.id_extracao
where e.endpoint = 'ciatox'
