-- Visão consolidada por UF: hospitais por habilitação, soros e CIATOX
with hospitais as (
    select
        uf,
        count(*)                                     as total_hospitais,
        count(distinct cidade)                       as total_cidades_com_hospital,
        count(*) filter (where atende_peconhentos)   as hospitais_peconhentos,
        count(*) filter (where atende_oncologia)     as hospitais_oncologia,
        count(*) filter (where atende_doencas_raras) as hospitais_doencas_raras,
        count(*) filter (where requer_verificacao)   as hospitais_requer_verificacao
    from {{ ref('dim_hospitais') }}
    group by uf
),

soros as (
    select h.uf, count(distinct f.codigo_tratamento) as tipos_soro_disponiveis
    from {{ ref('fct_hospital_soro') }} f
    join {{ ref('dim_hospitais') }} h using (hospital_id)
    group by h.uf
),

ciatox as (
    select uf, count(*) as total_ciatox
    from {{ ref('dim_ciatox') }}
    group by uf
)

select
    coalesce(h.uf, c.uf)                     as uf,
    coalesce(h.total_hospitais, 0)           as total_hospitais,
    coalesce(h.total_cidades_com_hospital, 0) as total_cidades_com_hospital,
    coalesce(h.hospitais_peconhentos, 0)     as hospitais_peconhentos,
    coalesce(h.hospitais_oncologia, 0)       as hospitais_oncologia,
    coalesce(h.hospitais_doencas_raras, 0)   as hospitais_doencas_raras,
    coalesce(h.hospitais_requer_verificacao, 0) as hospitais_requer_verificacao,
    coalesce(s.tipos_soro_disponiveis, 0)    as tipos_soro_disponiveis,
    coalesce(c.total_ciatox, 0)              as total_ciatox
from hospitais h
full outer join ciatox c on c.uf = h.uf
left join soros s on s.uf = coalesce(h.uf, c.uf)
