# .devcontainer/Dockerfile
# ============================================================
# Imagen para VS Code Dev Containers.
# Basada en la imagen oficial de Microsoft devcontainers/python.
# ============================================================
# Esta imagen NO corre code-server. VS Code Server se inyecta
# automáticamente cuando vos te conectás desde tu VS Code local
# vía la extensión "Dev Containers".
# ============================================================

FROM mcr.microsoft.com/devcontainers/python:3.12-bookworm

USER root

# Herramientas extra
RUN apt-get update && apt-get install -y --no-install-recommends \
        postgresql-client \
        make \
    && rm -rf /var/lib/apt/lists/*

# dbt instalado globalmente (el devcontainer corre como user 'vscode'
# pero pip global está disponible en /usr/local/bin)
RUN pip install --no-cache-dir \
        "dbt-core>=1.8" \
        "dbt-postgres>=1.8" \
        "dbt-redshift>=1.8"

USER vscode