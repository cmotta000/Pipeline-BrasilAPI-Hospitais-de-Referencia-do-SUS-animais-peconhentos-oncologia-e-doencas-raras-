-- Falha se a última extração de algum endpoint não trouxe 100% do que a API informou
-- ou se a silver perdeu linhas em relação à bronze.
with silver as (
    select 'hospitais' as endpoint, count(*) as qtd from {{ ref('stg_brasilapi__hospitais') }}
    union all
    select 'ciatox', count(*) from {{ ref('stg_brasilapi__ciatox') }}
)

select e.endpoint, e.total_api, e.total_extraido, s.qtd as total_silver
from {{ ref('stg_brasilapi__ultima_extracao') }} e
left join silver s using (endpoint)
where e.total_api is distinct from e.total_extraido
   or e.total_extraido is distinct from s.qtd
