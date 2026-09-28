-- 1 linha por hospital, todos os campos escalares da API tipados
select
    hospital_id,
    nullif(trim(payload->>'cnes'), '')                  as cnes,
    trim(payload->>'name')                              as nome,
    upper(trim(payload->>'state_code'))                 as uf,
    trim(payload->>'city')                              as cidade,
    trim(payload->>'address')                           as endereco,
    trim(payload->>'phones')                            as telefones,
    (payload->>'lat')::numeric(10, 7)                   as latitude,
    (payload->>'lng')::numeric(10, 7)                   as longitude,
    payload->>'extraction_source'                       as fonte_extracao,
    (payload->>'ocr_confidence')::numeric               as confianca_ocr,
    (payload->>'requires_verification')::boolean        as requer_verificacao,
    payload->'treatments'                               as tratamentos_json,
    payload->'verticals'                                as verticais_json,
    payload->'specialties'                              as especialidades_json,
    extraido_em
from {{ ref('stg_brasilapi__hospitais_json') }}
