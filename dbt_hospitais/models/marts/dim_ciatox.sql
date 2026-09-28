-- Centros de Informação e Assistência Toxicológica
select
    ciatox_id,
    uf,
    nome,
    telefone_emergencia,
    array_to_string(telefones, ', ') as telefones,
    url_fonte,
    sincronizado_em,
    extraido_em
from {{ ref('stg_brasilapi__ciatox') }}
