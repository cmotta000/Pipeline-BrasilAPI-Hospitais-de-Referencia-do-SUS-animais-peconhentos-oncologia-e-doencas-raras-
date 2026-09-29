{{ config(materialized='table') }}

-- Dimensão de códigos de habilitação do SUS (17.xx oncologia, 35.xx doenças raras).
-- A descrição vem da própria API; quando o mesmo código aparece com grafias diferentes,
-- usa a mais frequente. Códigos que a fonte nunca descreve recebem 'Não informado pela fonte'.
select
    codigo_habilitacao,
    coalesce(
        mode() within group (order by descricao_habilitacao),
        'Não informado pela fonte'
    )                                   as descricao_habilitacao,
    count(descricao_habilitacao) > 0    as descricao_informada_na_fonte
from {{ ref('stg_brasilapi__hospital_especialidades') }}
group by codigo_habilitacao
