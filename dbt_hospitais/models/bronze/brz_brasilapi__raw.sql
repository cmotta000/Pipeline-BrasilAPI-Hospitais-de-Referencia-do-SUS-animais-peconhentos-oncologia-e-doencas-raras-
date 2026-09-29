{{ config(materialized='view') }}

-- Bronze: 1 item da API por linha, JSON cru em payload
select
    id_extracao,
    endpoint,
    item_id,
    payload,
    extraido_em
from {{ source('bronze', 'brasilapi_raw') }}
