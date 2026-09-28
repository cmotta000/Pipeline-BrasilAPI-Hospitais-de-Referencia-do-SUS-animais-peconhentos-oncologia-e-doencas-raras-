-- Dimensão de especialidades (oncologia / doenças raras) com a vertical correspondente
select
    e.codigo_especialidade,
    e.especialidade,
    e.codigo_vertical,
    v.vertical
from {{ ref('especialidades') }} e
join {{ ref('verticais') }} v using (codigo_vertical)
