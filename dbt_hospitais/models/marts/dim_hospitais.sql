-- Dimensão de hospitais: 1 linha por hospital, com habilitações e soros consolidados
with verticais as (
    select
        hospital_id,
        bool_or(codigo_vertical = 'venomous_animals') as atende_peconhentos,
        bool_or(codigo_vertical = 'oncology')         as atende_oncologia,
        bool_or(codigo_vertical = 'rare_diseases')    as atende_doencas_raras,
        string_agg(v.vertical, ', ' order by v.vertical) as verticais
    from {{ ref('stg_brasilapi__hospital_verticais') }} hv
    left join {{ ref('verticais') }} v using (codigo_vertical)
    group by hospital_id
),

soros as (
    select
        hospital_id,
        count(*)                                   as qtd_soros,
        string_agg(s.soro, ', ' order by s.soro)   as soros_disponiveis
    from {{ ref('stg_brasilapi__hospital_tratamentos') }} ht
    left join {{ ref('soros') }} s using (codigo_tratamento)
    group by hospital_id
),

especialidades as (
    select
        hospital_id,
        count(distinct codigo_especialidade)                           as qtd_especialidades,
        string_agg(distinct esp.especialidade, ', ')                   as especialidades
    from {{ ref('stg_brasilapi__hospital_especialidades') }} he
    left join {{ ref('especialidades') }} esp using (codigo_especialidade)
    group by hospital_id
)

select
    h.hospital_id,
    h.cnes,
    h.nome,
    h.uf,
    h.cidade,
    h.endereco,
    h.telefones,
    h.latitude,
    h.longitude,
    coalesce(v.atende_peconhentos, false)   as atende_peconhentos,
    coalesce(v.atende_oncologia, false)     as atende_oncologia,
    coalesce(v.atende_doencas_raras, false) as atende_doencas_raras,
    v.verticais,
    coalesce(s.qtd_soros, 0)                as qtd_soros,
    s.soros_disponiveis,
    coalesce(e.qtd_especialidades, 0)       as qtd_especialidades,
    e.especialidades,
    h.fonte_extracao,
    h.confianca_ocr,
    h.requer_verificacao,
    h.extraido_em
from {{ ref('stg_brasilapi__hospitais') }} h
left join verticais v      using (hospital_id)
left join soros s          using (hospital_id)
left join especialidades e using (hospital_id)
