# Makefile
# Atajos para desarrollo local. Uso: `make help`

.PHONY: help build up down logs psql shell dev-shell debug seed run test all \
        clean reset code

help: ## Mostrar este mensaje de ayuda
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

# ─── Stack ──────────────────────────────────────────────────

build: ## Construir la imagen del dev container (primera vez o si cambia el Dockerfile)
	docker compose build

up: ## Arrancar stack (postgres + dev)
	docker compose up -d
	@echo "⏳ Esperando que Postgres esté listo..."
	@until docker compose exec -T postgres pg_isready -U dbt_dev -d dbt_dev > /dev/null 2>&1; do sleep 1; done
	@echo "✅ Stack arriba. Ahora: 'make code' para abrir VS Code y reopen in container."

down: ## Parar stack (mantiene datos)
	docker compose down

reset: ## Parar y BORRAR todos los datos y configs
	docker compose down -v
	@echo "⚠️  Datos y configs borrados"

logs: ## Logs de todos los servicios
	docker compose logs -f

# ─── Acceso a containers ────────────────────────────────────

code: ## Abrir VS Code con el proyecto (después: "Reopen in Container")
	code .

psql: ## Abrir psql contra el contenedor Postgres
	docker compose exec postgres psql -U dbt_dev -d dbt_dev

shell: ## Abrir bash dentro del contenedor Postgres
	docker compose exec postgres bash

dev-shell: ## Abrir bash dentro del contenedor dev (donde corre dbt)
	docker compose exec dev bash

# ─── dbt (corren adentro del container dev) ─────────────────

deps: ## dbt deps
	docker compose exec dev dbt deps

debug: ## dbt debug
	docker compose exec dev dbt debug

seed: ## dbt seed
	docker compose exec dev dbt seed --select compat_test_users

run: ## dbt run
	docker compose exec dev dbt run --select tag:compat_examples

test: ## dbt test
	docker compose exec dev dbt test --select tag:compat_examples

all: seed run test ## Pipeline completo: seed + run + test

# ─── Limpieza ───────────────────────────────────────────────

clean: ## Limpiar artefactos dbt en el host (target/, logs/)
	rm -rf target logs