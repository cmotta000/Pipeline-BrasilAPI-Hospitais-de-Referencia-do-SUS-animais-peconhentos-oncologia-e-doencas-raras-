{{ config(materialized='view') }}

-- Bronze: envelope de cada extração (1 linha por endpoint por execução), exatamente como gravado pelo Python
select
    id_extracao,
    endpoint,
    url,
    total_api,
    total_extraido,
    envelope,
    extraido_em
from {{ source('bronze', 'brasilapi_extracoes') }}
