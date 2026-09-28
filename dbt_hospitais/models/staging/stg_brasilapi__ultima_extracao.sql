-- Extração mais recente de cada endpoint + metadados do envelope da API
with ranqueado as (
    select
        *,
        row_number() over (partition by endpoint order by extraido_em desc) as rn
    from {{ source('bronze', 'brasilapi_extracoes') }}
)

select
    id_extracao,
    endpoint,
    url,
    total_api,
    total_extraido,
    (envelope->>'atualizado_em')::timestamptz          as fonte_atualizada_em,
    envelope->'fonte'->>'nome'                          as fonte_nome,
    envelope->'fonte'->>'url'                           as fonte_url,
    (envelope->'fonte'->>'oficial')::boolean            as fonte_oficial,
    envelope->'fonte'->>'documentos_de_origem'          as fonte_documentos_origem,
    envelope->'fonte'->>'aviso'                         as fonte_aviso,
    envelope->'emergencia'->>'aviso'                    as emergencia_aviso,
    envelope->'emergencia'->>'samu'                     as telefone_samu,
    envelope->'emergencia'->>'disque_intoxicacao'       as telefone_disque_intoxicacao,
    envelope                                            as envelope_json,
    extraido_em
from ranqueado
where rn = 1
