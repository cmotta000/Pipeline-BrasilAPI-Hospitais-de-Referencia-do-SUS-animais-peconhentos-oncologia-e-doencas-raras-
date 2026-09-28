-- Payload cru dos hospitais da extração mais recente (base para as demais stg)
select
    r.payload,
    (r.payload->>'id')::int as hospital_id,
    r.extraido_em
from {{ source('bronze', 'brasilapi_raw') }} r
join {{ ref('stg_brasilapi__ultima_extracao') }} e
  on e.id_extracao = r.id_extracao
where e.endpoint = 'hospitais'
