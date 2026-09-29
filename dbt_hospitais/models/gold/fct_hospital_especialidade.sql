{{ config(materialized='table') }}

-- Fato sem medida: 1 linha por hospital x especialidade x código de habilitação.
-- Só chaves: descrições ficam em dim_hospitais, dim_especialidade, dim_habilitacao e dim_data.
-- A fonte não informa a data de habilitação de oncologia -> data_habilitacao_key = -1 ('Não informada').
select
    hospital_id,
    codigo_especialidade,
    codigo_habilitacao,
    coalesce(to_char(habilitado_em, 'YYYYMMDD')::int, -1) as data_habilitacao_key
from {{ ref('stg_brasilapi__hospital_especialidades') }}
