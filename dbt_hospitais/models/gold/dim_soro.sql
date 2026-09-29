{{ config(materialized='table') }}

-- Dimensão de soros antiveneno: 1 linha por código de tratamento da API
select
    codigo_tratamento,
    soro,
    animal,
    acidente
from {{ ref('soros') }}
