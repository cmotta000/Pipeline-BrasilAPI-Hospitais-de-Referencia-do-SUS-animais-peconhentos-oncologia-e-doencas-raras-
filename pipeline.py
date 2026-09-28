#!/usr/bin/env python3
"""
Orquestrador: extração (bronze) + dbt (silver/gold).

Uso:
    python pipeline.py              # extrai da API e roda dbt build (seeds, modelos e testes)
    python pipeline.py --so-dbt     # pula a extração, só roda o dbt build
    python pipeline.py dbt <args>   # repassa comandos ao dbt com o .env carregado
                                    # ex: python pipeline.py dbt docs generate
"""

import os
import shutil
import subprocess
import sys
from pathlib import Path

from dotenv import load_dotenv

RAIZ = Path(__file__).resolve().parent
DBT_DIR = RAIZ / "dbt_hospitais"

sys.path.insert(0, str(RAIZ / "extracao"))


def dbt(*args: str) -> None:
    exe = shutil.which("dbt", path=str(Path(sys.executable).parent)) or "dbt"
    cmd = [exe, *args, "--project-dir", str(DBT_DIR), "--profiles-dir", str(DBT_DIR)]
    print(f"[dbt] {' '.join(args)}")
    resultado = subprocess.run(cmd, cwd=DBT_DIR)
    if resultado.returncode != 0:
        sys.exit(resultado.returncode)


def main() -> None:
    load_dotenv(RAIZ / ".env")
    args = sys.argv[1:]

    if args and args[0] == "dbt":
        dbt(*args[1:])
        return

    if "--so-dbt" not in args:
        import extrair_brasilapi_hospitais
        extrair_brasilapi_hospitais.main()

    dbt("build")


if __name__ == "__main__":
    main()
