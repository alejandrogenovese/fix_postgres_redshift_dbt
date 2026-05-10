# Makefile
# ============================================================
# Atajos para desarrollo. Compatible con Docker y Podman.
# ============================================================
# El comando de compose se determina por la variable COMPOSE.
# Default: docker compose
#
# Para usar Podman:
#   make up COMPOSE="podman compose"
#
# Para usar podman-compose (Podman 3.x):
#   make up COMPOSE="podman-compose"
#
# Tip: exportar una vez en tu shell para no repetirlo:
#   export COMPOSE="podman compose"
#   make up
# ============================================================

COMPOSE ?= docker compose

.PHONY: help build up down logs psql shell dev-shell deps debug \
        seed run test all clean reset code

help: ## Mostrar este mensaje de ayuda
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "Container runtime actual: $(COMPOSE)"
	@echo "Override: make <target> COMPOSE=\"podman compose\""

# ─── Stack ──────────────────────────────────────────────────

build: ## Construir la imagen del dev container
	$(COMPOSE) build

up: ## Arrancar stack (postgres + dev)
	$(COMPOSE) up -d
	@echo "⏳ Esperando que Postgres esté listo..."
	@until $(COMPOSE) exec -T postgres pg_isready -U dbt_dev -d dbt_dev > /dev/null 2>&1; do sleep 1; done
	@echo "✅ Stack arriba. Próximo paso: 'make code' y 'Reopen in Container'."

down: ## Parar stack (mantiene datos)
	$(COMPOSE) down

reset: ## Parar y BORRAR datos y volúmenes
	$(COMPOSE) down -v
	@echo "⚠️  Datos y volúmenes borrados"

logs: ## Logs de todos los servicios
	$(COMPOSE) logs -f

# ─── Acceso a containers ────────────────────────────────────

code: ## Abrir VS Code en el proyecto (después: "Reopen in Container")
	code .

psql: ## Abrir psql contra el contenedor Postgres
	$(COMPOSE) exec postgres psql -U dbt_dev -d dbt_dev

shell: ## Bash dentro del contenedor Postgres
	$(COMPOSE) exec postgres bash

dev-shell: ## Bash dentro del contenedor dev (donde corre dbt)
	$(COMPOSE) exec dev bash

# ─── dbt (corren adentro del container dev) ─────────────────

deps: ## dbt deps
	$(COMPOSE) exec dev dbt deps

debug: ## dbt debug
	$(COMPOSE) exec dev dbt debug

seed: ## dbt seed
	$(COMPOSE) exec dev dbt seed --select compat_test_users

run: ## dbt run
	$(COMPOSE) exec dev dbt run --select tag:compat_examples

test: ## dbt test
	$(COMPOSE) exec dev dbt test --select tag:compat_examples

all: seed run test ## Pipeline completo: seed + run + test

# ─── Limpieza ───────────────────────────────────────────────

clean: ## Limpiar artefactos dbt en el host (target/, logs/, dbt_packages/)
	rm -rf target logs dbt_packages
