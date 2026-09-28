-- Dimensão de datas (chave inteligente YYYYMMDD) + membro desconhecido -1 = 'Não informada'.
-- O intervalo cobre as datas das fatos; o teste relationships nas fatos avisa se alguma ficar de fora.
with datas as (
    select d::date as data
    from generate_series(
        date '{{ var("dim_data_inicio") }}',
        (date_trunc('year', current_date) + interval '1 year - 1 day')::date,
        interval '1 day'
    ) as g(d)
)

select
    to_char(data, 'YYYYMMDD')::int                    as data_key,
    data,
    extract(year from data)::int                      as ano,
    extract(quarter from data)::int                   as trimestre,
    extract(month from data)::int                     as mes,
    (array['Janeiro','Fevereiro','Março','Abril','Maio','Junho','Julho',
           'Agosto','Setembro','Outubro','Novembro','Dezembro'])[extract(month from data)::int]
                                                      as nome_mes,
    to_char(data, 'YYYY-MM')                          as ano_mes,
    extract(day from data)::int                       as dia,
    (array['Domingo','Segunda-feira','Terça-feira','Quarta-feira',
           'Quinta-feira','Sexta-feira','Sábado'])[extract(dow from data)::int + 1]
                                                      as nome_dia_semana,
    to_char(data, 'DD/MM/YYYY')                       as data_formatada
from datas

union all

select
    -1,
    null,
    null,
    null,
    null,
    'Não informada',
    'Não informada',
    null,
    'Não informada',
    'Não informada'
