# Pipeline BrasilAPI – Hospitais de Referência do SUS

Pipeline ELT que extrai **100%** dos dados de hospitais de referência do SUS (animais peçonhentos, oncologia e doenças raras) e dos CIATOX da [BrasilAPI](https://brasilapi.com.br), carrega no PostgreSQL (camada **bronze**) e transforma com **dbt** nas camadas **silver** e **gold** (arquitetura medalhão).

```
BrasilAPI ──(Python)──► bronze (JSON cru, append-only)
                            │
                           dbt
                            ▼
                silver (views tipadas / explodidas)
                            │
                            ▼
                gold (tabelas analíticas)
```

---

## 1. Estrutura do projeto

```
Extração via API/
├── pipeline.py                         # Orquestrador: extração + dbt build
├── requirements.txt                    # Dependências Python
├── .env / .env.example                 # Credenciais do Postgres (o .env não vai pro git)
├── extracao/
│   └── extrair_brasilapi_hospitais.py  # Extração e carga da bronze
├── dbt_hospitais/                      # Projeto dbt (silver + gold)
│   ├── dbt_project.yml
│   ├── profiles.yml                    # Lê a conexão das variáveis do .env
│   ├── macros/generate_schema_name.sql
│   ├── seeds/                          # De-paras (soros, verticais)
│   ├── models/staging/                 # Silver
│   ├── models/marts/                   # Gold
│   └── tests/                          # Testes singulares
└── _legado/                            # Versão antiga (scripts SQL/Python sem dbt) – só referência
```

---

## 2. Pré-requisitos e setup

- Python 3.14 (testado) com o ambiente virtual em `venv/`
- PostgreSQL acessível com as credenciais do `.env`

### 2.1 Configurar o `.env`

Copie `.env.example` para `.env` e preencha:

```
PG_HOST=localhost
PG_PORT=5432
PG_USER=seu_usuario
PG_PASSWORD=sua_senha
PG_DB=seb
```

O `profiles.yml` do dbt lê essas mesmas variáveis via `env_var(...)`, então não há credencial duplicada.

### 2.2 Instalar dependências (uma vez)

```powershell
.\venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
```

Pacotes: `requests`, `psycopg2-binary`, `python-dotenv`, `dbt-core`, `dbt-postgres`, `truststore`.

> **Atenção:** ativar o venv não instala nada. Se aparecer `ModuleNotFoundError: No module named 'dotenv'`, rode o `pip install -r requirements.txt` acima.

---

## 3. Como executar

Com o venv ativo, na raiz do projeto:

| Comando | O que faz |
|---|---|
| `python pipeline.py` | Extrai da API → grava na bronze → `dbt build` (seeds, modelos e testes) |
| `python pipeline.py --so-dbt` | Pula a extração e só roda o `dbt build` |
| `python pipeline.py dbt <args>` | Repassa qualquer comando ao dbt com o `.env` carregado. Ex.: `python pipeline.py dbt docs generate`, `python pipeline.py dbt run -s dim_hospitais` |

Sem venv ativo, use o executável direto: `.\venv\Scripts\python.exe pipeline.py`.

---

## 4. Extração e carga (bronze)

Script: `extracao/extrair_brasilapi_hospitais.py`

### 4.1 Endpoints

| Nome | URL | Paginação |
|---|---|---|
| `hospitais` | `https://brasilapi.com.br/api/hospitais/v1` | `limit=500` / `offset` (máximo aceito pela API) |
| `ciatox` | `https://brasilapi.com.br/api/hospitais/v1/ciatox` | Não paginado |

### 4.2 Comportamento

- **Retry** automático (5 tentativas, backoff exponencial) para HTTP 429/500/502/503/504.
- **truststore**: usa os certificados do Windows – necessário atrás do proxy/inspeção TLS corporativa.
- **Validação antes de gravar**: falha se `total` informado pela API ≠ itens recebidos, ou se houver `id` duplicado na paginação.
- **Transação única**: os dois endpoints são gravados juntos; se algo falhar, nada é gravado.
- **Nenhuma transformação**: o JSON de cada item é gravado cru em `jsonb`.
- O DDL (`CREATE SCHEMA/TABLE IF NOT EXISTS`) roda a cada execução, então o schema é criado automaticamente na primeira vez.

### 4.3 Tabelas da bronze (append-only / histórico de snapshots)

**`bronze.brasilapi_extracoes`** – 1 linha por endpoint por execução

| Coluna | Tipo | Descrição |
|---|---|---|
| `id_extracao` | UUID (PK) | Identificador da execução daquele endpoint |
| `endpoint` | text | `hospitais` ou `ciatox` |
| `url` | text | URL chamada |
| `total_api` | int | Total informado pela API |
| `total_extraido` | int | Itens efetivamente recebidos |
| `envelope` | jsonb | Resposta sem `items` (`atualizado_em`, `fonte`, `emergencia`...) |
| `extraido_em` | timestamptz | Momento da carga |

**`bronze.brasilapi_raw`** – 1 linha por item da API

| Coluna | Tipo | Descrição |
|---|---|---|
| `id_extracao` | UUID (FK) | Referência a `brasilapi_extracoes` |
| `endpoint` | text | `hospitais` ou `ciatox` |
| `item_id` | text | `id` do item na API |
| `payload` | jsonb | Item cru |
| `extraido_em` | timestamptz | Momento da carga |

Cada execução **acrescenta** um novo snapshot; o dbt sempre lê **a extração mais recente de cada endpoint**.

---

## 5. Transformação com dbt

Projeto `dbt_hospitais/` (nome `hospitais_sus`, profile `hospitais_sus`, target `dev`, 4 threads).

### 5.1 Configurações relevantes

- `models/staging` → schema **`silver`**, materializados como **view**
- `models/marts` → schema **`gold`**, materializados como **table**
- `seeds` → schema **`silver`**
- Macro `generate_schema_name`: faz o dbt usar o nome do schema exatamente como configurado (`silver`/`gold`) em vez do padrão `public_silver`.

### 5.2 Seeds (de-paras)

| Seed | Conteúdo |
|---|---|
| `soros` | Código de tratamento da API → soro, animal e tipo de acidente em português (9 linhas: Bothropic → Antibotrópico / jararaca etc.) |
| `verticais` | `venomous_animals` → Animais peçonhentos, `oncology` → Oncologia, `rare_diseases` → Doenças raras |
| `especialidades` | Código de especialidade da API → nome em português + vertical (10 linhas: `unacon` → UNACON, `breast_reconstruction` → Reconstrução mamária etc.) |

### 5.3 Silver (`models/staging`, views)

| Modelo | Grão | Descrição |
|---|---|---|
| `stg_brasilapi__ultima_extracao` | 1 por endpoint | Última extração de cada endpoint (`row_number` por `extraido_em desc`) + metadados do envelope: fonte (MapaSUS), data de atualização da fonte, avisos, telefones SAMU e Disque-Intoxicação |
| `stg_brasilapi__hospitais_json` | 1 por hospital | Payload cru dos hospitais da última extração – base das demais stg |
| `stg_brasilapi__hospitais` | 1 por hospital | Campos escalares tipados: CNES, nome, UF, cidade, endereço, telefones, lat/long, fonte, confiança do OCR, `requer_verificacao` |
| `stg_brasilapi__hospital_tratamentos` | hospital × soro | Explode o array `treatments` |
| `stg_brasilapi__hospital_verticais` | hospital × vertical | Explode o array `verticals` |
| `stg_brasilapi__hospital_especialidades` | hospital × especialidade × código | Explode `specialties` → `qualification_codes`. Trata as sujeiras da fonte: vários códigos na mesma string (separados por `\n` **ou só por espaços**), código sem ponto (`3501` → `35.01`) e espaços repetidos. Separa `codigo_habilitacao` (ex.: `17.06`) de `descricao_habilitacao` e mantém `qualificacao_original` para rastreabilidade |
| `stg_brasilapi__ciatox` | 1 por CIATOX | Centros de Informação e Assistência Toxicológica tipados |

### 5.4 Gold (`models/marts`, tabelas)

Modelagem dimensional (estrela):

- As **fatos guardam só chaves**. Tudo o que descreve o hospital (nome, CNES, UF, cidade, endereço, lat/long) fica em `dim_hospitais`; o soro em `dim_soro`; a especialidade em `dim_especialidade`; o código de habilitação em `dim_habilitacao`; a data em `dim_data`. Para filtrar/agrupar por cidade ou UF, faça join da fato com `dim_hospitais` por `hospital_id`.
- **Fatos sem nulos**: quando a fonte não informa algo, a fato aponta para um **membro desconhecido** da dimensão em vez de gravar nulo:
  - Data não informada → `data_habilitacao_key = -1` (linha "Não informada" da `dim_data`). A API não traz a data de habilitação de **nenhum** hospital de oncologia (696 de 942 linhas).
  - Descrição de habilitação não informada → `dim_habilitacao.descricao_habilitacao = 'Não informado pela fonte'` com `descricao_informada_na_fonte = false`. A API só manda o código para os 17.xx (oncologia). Não foram inventadas descrições oficiais do SIGTAP; se quiser completá-las, crie um seed com a tabela oficial e dê prioridade a ele na `dim_habilitacao`.

| Modelo | Grão | Descrição |
|---|---|---|
| `dim_hospitais` | 1 por hospital | Hospital com localização (UF, cidade, endereço, lat/long) + flags `atende_peconhentos` / `atende_oncologia` / `atende_doencas_raras`, lista de verticais, quantidade e lista de soros, quantidade e lista de especialidades |
| `dim_soro` | 1 por soro | Código de tratamento da API → soro, animal e acidente (a partir do seed `soros`) |
| `fct_hospital_soro` | hospital × soro | Fato sem medida: `hospital_id`, `codigo_tratamento` |
| `dim_especialidade` | 1 por especialidade | Especialidade em português + vertical (seeds `especialidades` e `verticais`) |
| `dim_habilitacao` | 1 por código | Código de habilitação do SUS com descrição padronizada (quando o mesmo código vem com grafias diferentes, usa a mais frequente) e flag `descricao_informada_na_fonte` |
| `dim_data` | 1 por dia | Calendário de `dim_data_inicio` (var no `dbt_project.yml`, padrão 2000-01-01) até o fim do ano corrente. `data_key` = `YYYYMMDD` (int), ano, trimestre, mês, nome do mês, dia da semana. Membro `-1` = "Não informada" |
| `fct_hospital_especialidade` | hospital × especialidade × código | Fato sem medida, só chaves e sem nulos: `hospital_id`, `codigo_especialidade`, `codigo_habilitacao`, `data_habilitacao_key` |
| `hospitais_por_uf_soro` | UF × soro | Total de hospitais e cidades que oferecem cada soro |
| `cobertura_por_uf` | 1 por UF | Resumo: hospitais por habilitação, cidades atendidas, hospitais que requerem verificação, tipos de soro disponíveis e número de CIATOX |
| `dim_ciatox` | 1 por CIATOX | CIATOX com telefones concatenados |

### 5.5 Linhagem

```
bronze.brasilapi_extracoes ─► stg_brasilapi__ultima_extracao ─┬─► stg_brasilapi__hospitais_json ─┬─► stg_brasilapi__hospitais ──────────────┐
bronze.brasilapi_raw ─────────────────────────────────────────┤                                  ├─► stg_brasilapi__hospital_tratamentos ─┤
                                                              │                                  ├─► stg_brasilapi__hospital_verticais ───┤
                                                              │                                  └─► stg_brasilapi__hospital_especialidades
                                                              └─► stg_brasilapi__ciatox ─► dim_ciatox
seeds: soros, verticais, especialidades

stg_* + seeds ─► dim_hospitais
seed soros ─► dim_soro
seeds especialidades + verticais ─► dim_especialidade
stg_brasilapi__hospital_especialidades ─► dim_habilitacao
generate_series ─► dim_data
stg_brasilapi__hospital_tratamentos ─► fct_hospital_soro
stg_brasilapi__hospital_especialidades ─► fct_hospital_especialidade
fct_hospital_soro + dim_hospitais + dim_soro ─► hospitais_por_uf_soro
dim_hospitais + fct_hospital_soro + dim_ciatox ─► cobertura_por_uf
```

Para ver o grafo interativo: `python pipeline.py dbt docs generate` e depois `python pipeline.py dbt docs serve`.

### 5.6 Testes de qualidade (54)

- **Source**: `id_extracao` único e não nulo.
- **Seeds**: códigos únicos e não nulos em `soros`, `verticais` e `especialidades`; toda especialidade aponta para uma vertical existente.
- **Silver**: `endpoint` único na última extração; `hospital_id` e `ciatox_id` únicos e não nulos; `uf` não nula; `codigo_habilitacao` não nulo (pega regressão no parsing); **relationships** garantindo que todo código de tratamento, vertical e especialidade vindo da API existe no seed (se a API criar um código novo, o teste falha e avisa que o de-para precisa ser atualizado).
- **Gold**: chaves únicas/não nulas em todas as dimensões; `descricao_habilitacao` não nula; `dim_data.data` não nula exceto no membro -1; grão único nas duas fatos; **todas as chaves das fatos não nulas e com relationships** para as dimensões (integridade referencial da estrela — inclusive `data_habilitacao_key` → `dim_data`, que falha se aparecer data fora do calendário).
- **Singular `assert_extracao_completa`**: falha se a última extração não trouxe 100% do total informado pela API ou se a silver perdeu linhas em relação à bronze.

---

## 6. Resultado da execução de 28/09/2026

Extração:

```
[extract:hospitais] 2342/2342 (5 páginas de 500)
[extract:ciatox]    32/32
[load:hospitais] 2342 itens gravados (id_extracao=8a263e31-1f85-4bba-912d-dd7d0d9bf26f)
[load:ciatox]    32 itens gravados   (id_extracao=31e2db9b-79bc-44e4-a57a-9d1796aa62f8)
```

dbt build (após a remodelagem em estrela sem nulos nas fatos): **PASS=74 WARN=0 ERROR=0** (3 seeds, 7 views, 10 tabelas, 54 testes).

| Objeto | Linhas |
|---|---|
| `gold.dim_hospitais` | 2.342 |
| `gold.dim_soro` | 9 |
| `gold.dim_especialidade` | 10 |
| `gold.dim_habilitacao` | 30 (14 sem descrição na fonte) |
| `gold.dim_data` | 9.863 (2000-01-01 a 2026-12-31 + membro -1) |
| `gold.fct_hospital_soro` | 7.946 |
| `gold.fct_hospital_especialidade` | 942 (696 com data "Não informada") |
| `gold.hospitais_por_uf_soro` | 175 |
| `gold.cobertura_por_uf` | 27 |
| `gold.dim_ciatox` | 32 |
| `bronze.brasilapi_extracoes` (histórico) | 4 (2 execuções) |
| `bronze.brasilapi_raw` (histórico) | 4.748 |

Fonte: MapaSUS, atualizada em 12/08/2026.

Destaques:

- Hospitais por habilitação: **2.018** animais peçonhentos, **384** oncologia, **52** doenças raras.
- Soros mais disponíveis: Antiescorpiônico (1.695 hospitais), Antibotrópico (1.559), Anticrotálico (1.093).
- UFs com mais hospitais: MG (324), SP (309), BA (262), PR (170), SC (155).

---

## 7. Consultas úteis

```sql
-- Onde encontrar soro antiescorpiônico em uma cidade
select nome, endereco, telefones
from gold.dim_hospitais
where uf = 'MG' and cidade ilike 'Belo Horizonte' and soros_disponiveis ilike '%Antiescorpiônico%';

-- Mesma pergunta pela estrela: fato + dimensões
select h.nome, h.cidade, s.soro, s.animal
from gold.fct_hospital_soro f
join gold.dim_hospitais h using (hospital_id)
join gold.dim_soro s      using (codigo_tratamento)
where h.uf = 'SP' and s.animal ilike 'Escorpião%';

-- Habilitações de doenças raras por ano de habilitação
select d.ano, e.especialidade, hab.descricao_habilitacao, count(*) as hospitais
from gold.fct_hospital_especialidade f
join gold.dim_especialidade e using (codigo_especialidade)
join gold.dim_habilitacao hab using (codigo_habilitacao)
join gold.dim_data d on d.data_key = f.data_habilitacao_key
where e.codigo_vertical = 'rare_diseases'
group by 1, 2, 3
order by 1;

-- Cobertura por UF
select * from gold.cobertura_por_uf order by total_hospitais desc;

-- Metadados e telefones de emergência da última extração
select endpoint, fonte_nome, fonte_atualizada_em, telefone_samu, telefone_disque_intoxicacao
from silver.stg_brasilapi__ultima_extracao;
```

---

## 8. Solução de problemas

| Sintoma | Causa / solução |
|---|---|
| `ModuleNotFoundError: No module named 'dotenv'` | Dependências não instaladas no venv → `pip install -r requirements.txt` |
| `Erro: variáveis ausentes no .env` | Preencha `PG_HOST`, `PG_USER`, `PG_PASSWORD`, `PG_DB` |
| Erro de certificado SSL | Verifique se `truststore` está instalado (necessário na rede corporativa) |
| `API informou total=X, mas vieram Y itens` | API mudou durante a paginação – rode novamente |
| Teste `relationships_...ref_soros_` falhando | A API trouxe um código de tratamento/vertical novo → adicione ao seed correspondente e rode `python pipeline.py --so-dbt` |
| Bronze crescendo muito | Ela é append-only por design; snapshots antigos podem ser apagados por `id_extracao` se não precisar do histórico |
