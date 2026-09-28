-- Quantos hospitais / cidades oferecem cada soro em cada UF
select
    h.uf,
    s.soro,
    s.animal,
    count(distinct f.hospital_id) as total_hospitais,
    count(distinct h.cidade)      as total_cidades
from {{ ref('fct_hospital_soro') }} f
join {{ ref('dim_hospitais') }} h using (hospital_id)
join {{ ref('dim_soro') }} s      using (codigo_tratamento)
group by h.uf, s.soro, s.animal
