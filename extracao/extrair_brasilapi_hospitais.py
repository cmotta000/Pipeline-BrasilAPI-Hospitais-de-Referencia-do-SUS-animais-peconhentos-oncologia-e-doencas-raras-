#!/usr/bin/env python3
"""
Extração BRONZE -- BrasilAPI / Hospitais (100% dos dados).

Endpoints extraídos:
    /api/hospitais/v1          -> todos os hospitais, TODAS as verticais
                                  (venomous_animals, oncology, rare_diseases)
    /api/hospitais/v1/ciatox   -> centros de informação toxicológica

Nada é transformado aqui. Cada execução grava:
    bronze.brasilapi_extracoes  -> 1 linha por endpoint extraído, com o envelope
                                   da resposta (total, atualizado_em, fonte,
                                   emergencia) e contagens para auditoria
    bronze.brasilapi_raw        -> 1 linha por item, JSON cru em jsonb

A bronze é append-only (histórico de snapshots). O dbt lê sempre a extração
mais recente de cada endpoint.
"""

import os
import sys
import uuid
from datetime import datetime, timezone

import psycopg2
import requests
import truststore
from dotenv import load_dotenv
from psycopg2.extras import Json, execute_values
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

# Usa os certificados do Windows (necessário atrás do proxy/inspeção TLS corporativa)
truststore.inject_into_ssl()

BASE_URL = "https://brasilapi.com.br/api/hospitais/v1"
LIMIT_POR_PAGINA = 500  # máximo aceito pela API

ENDPOINTS = {
    "hospitais": {"path": "", "paginado": True},
    "ciatox": {"path": "/ciatox", "paginado": False},
}

DDL = """
CREATE SCHEMA IF NOT EXISTS bronze;

CREATE TABLE IF NOT EXISTS bronze.brasilapi_extracoes (
    id_extracao      UUID PRIMARY KEY,
    endpoint         TEXT        NOT NULL,
    url              TEXT        NOT NULL,
    total_api        INTEGER,
    total_extraido   INTEGER     NOT NULL,
    envelope         JSONB,
    extraido_em      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS bronze.brasilapi_raw (
    id_extracao  UUID        NOT NULL REFERENCES bronze.brasilapi_extracoes (id_extracao),
    endpoint     TEXT        NOT NULL,
    item_id      TEXT,
    payload      JSONB       NOT NULL,
    extraido_em  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_brasilapi_raw_extracao ON bronze.brasilapi_raw (id_extracao);
CREATE INDEX IF NOT EXISTS ix_brasilapi_extracoes_endpoint ON bronze.brasilapi_extracoes (endpoint, extraido_em DESC);
"""


def criar_sessao() -> requests.Session:
    sessao = requests.Session()
    sessao.headers.update({"User-Agent": "etl-seb/1.0", "Accept": "application/json"})
    retry = Retry(total=5, backoff_factor=1, status_forcelist=[429, 500, 502, 503, 504])
    sessao.mount("https://", HTTPAdapter(max_retries=retry))
    return sessao


def extrair(sessao: requests.Session, nome: str, cfg: dict) -> tuple[dict, list[dict]]:
    """Retorna (envelope sem items, lista completa de items)."""
    url = BASE_URL + cfg["path"]
    items: list[dict] = []
    offset = 0

    while True:
        params = {"limit": LIMIT_POR_PAGINA, "offset": offset} if cfg["paginado"] else None
        resp = sessao.get(url, params=params, timeout=60)
        resp.raise_for_status()
        data = resp.json()

        pagina = data.get("items", [])
        items.extend(pagina)
        envelope = {k: v for k, v in data.items() if k != "items"}
        print(f"[extract:{nome}] offset={offset} +{len(pagina)} (acumulado {len(items)}/{data.get('total')})")

        if not cfg["paginado"] or not pagina:
            break
        offset += LIMIT_POR_PAGINA
        if offset >= data["total"]:
            break

    validar(nome, envelope, items)
    return envelope, items


def validar(nome: str, envelope: dict, items: list[dict]) -> None:
    total = envelope.get("total")
    if total is not None and total != len(items):
        raise RuntimeError(f"[{nome}] API informou total={total}, mas vieram {len(items)} itens")
    ids = [i.get("id") for i in items]
    if len(ids) != len(set(ids)):
        raise RuntimeError(f"[{nome}] ids duplicados na paginação")


def carregar(conn, nome: str, url: str, envelope: dict, items: list[dict]) -> None:
    id_extracao = str(uuid.uuid4())
    agora = datetime.now(timezone.utc)
    with conn.cursor() as cur:
        cur.execute(
            """INSERT INTO bronze.brasilapi_extracoes
               (id_extracao, endpoint, url, total_api, total_extraido, envelope, extraido_em)
               VALUES (%s, %s, %s, %s, %s, %s, %s)""",
            (id_extracao, nome, url, envelope.get("total"), len(items), Json(envelope), agora),
        )
        execute_values(
            cur,
            "INSERT INTO bronze.brasilapi_raw (id_extracao, endpoint, item_id, payload, extraido_em) VALUES %s",
            [(id_extracao, nome, str(i.get("id")), Json(i), agora) for i in items],
            page_size=1000,
        )
    print(f"[load:{nome}] {len(items)} itens gravados (id_extracao={id_extracao})")


def conectar():
    load_dotenv(os.path.join(os.path.dirname(__file__), "..", ".env"))
    faltando = [v for v in ("PG_HOST", "PG_USER", "PG_PASSWORD", "PG_DB") if not os.environ.get(v)]
    if faltando:
        sys.exit(f"Erro: variáveis ausentes no .env: {', '.join(faltando)}")
    return psycopg2.connect(
        host=os.environ["PG_HOST"],
        port=os.environ.get("PG_PORT", "5432"),
        user=os.environ["PG_USER"],
        password=os.environ["PG_PASSWORD"],
        dbname=os.environ["PG_DB"],
    )


def main() -> None:
    sessao = criar_sessao()
    extraidos = {nome: extrair(sessao, nome, cfg) for nome, cfg in ENDPOINTS.items()}

    conn = conectar()
    try:
        with conn:  # uma transação: ou grava tudo, ou nada
            with conn.cursor() as cur:
                cur.execute(DDL)
            for nome, (envelope, items) in extraidos.items():
                carregar(conn, nome, BASE_URL + ENDPOINTS[nome]["path"], envelope, items)
    finally:
        conn.close()
    print("[bronze] ok")


if __name__ == "__main__":
    main()
