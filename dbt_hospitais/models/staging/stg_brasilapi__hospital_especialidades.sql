-- Explode specialties -> qualification_codes: 1 linha por hospital x especialidade x código de habilitação.
-- A API às vezes junta vários códigos numa única string, separados por quebra de linha
-- ou só por espaços ("... Metabolismo      35.11- Serviço ..."), e às vezes omite o ponto ("3501-").
with especialidades as (
    select
        h.hospital_id,
        s.ordem                                              as ordem_especialidade,
        s.item->>'specialty'                                 as codigo_especialidade,
        (s.item->>'habilitado_em')::date                     as habilitado_em,
        coalesce(s.item->'qualification_codes', '[]'::jsonb) as codigos
    from {{ ref('stg_brasilapi__hospitais_json') }} h
    cross join lateral jsonb_array_elements(coalesce(h.payload->'specialties', '[]'::jsonb))
        with ordinality as s(item, ordem)
),

codigos as (
    select
        e.hospital_id,
        e.ordem_especialidade,
        e.codigo_especialidade,
        e.habilitado_em,
        trim(l.linha) as qualificacao
    from especialidades e
    cross join lateral jsonb_array_elements_text(e.codigos) as c(codigo)
    -- quebra a linha antes de cada código embutido no meio do texto
    cross join lateral regexp_split_to_table(
        regexp_replace(c.codigo, '\s+(\d{2}\.?\d{2}\s*-)', E'\n\\1', 'g'),
        E'\n'
    ) as l(linha)
    where trim(l.linha) <> ''
)

select
    hospital_id,
    ordem_especialidade,
    codigo_especialidade,
    habilitado_em,
    regexp_replace(substring(qualificacao from '^\d{2}\.?\d{2}'), '^(\d{2})\.?(\d{2})$', '\1.\2') as codigo_habilitacao,
    nullif(
        regexp_replace(trim(regexp_replace(qualificacao, '^\d{2}\.?\d{2}\s*-?\s*', '')), '\s+', ' ', 'g'),
        ''
    )                                                                                          as descricao_habilitacao,
    qualificacao                                                                               as qualificacao_original
from codigos
