{{ config(materialized='table') }}

-- Fato sem medida: 1 linha por hospital x soro disponível.
-- Atributos descritivos ficam em dim_hospitais (localização) e dim_soro (animal / acidente).
select
    hospital_id,
    codigo_tratamento
from {{ ref('stg_brasilapi__hospital_tratamentos') }}
