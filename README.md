# fix_postgres_redshift_dbt

[![Python 3.9+](https://img.shields.io/badge/Python-3.9%2B-blue.svg)](https://www.python.org/downloads/)
[![dbt 1.8+](https://img.shields.io/badge/dbt-1.8%2B-4A154B.svg)](https://docs.getdbt.com)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Maintained: Yes](https://img.shields.io/badge/Maintained%3F-yes-green.svg)](https://github.com/alejandrogenovese/fix_postgres_redshift_dbt)

Capa de compatibilidad cross-db **Postgres ↔ Redshift** para dbt. Permite desarrollar y testear modelos dbt en Postgres y promoverlos a Redshift sin reescribir las consultas.

Diseñada para contextos de migración **Teradata → Redshift** (Banco Galicia).

---

## 📋 Tabla de contenidos

- [Características](#-características)
- [Requisitos](#-requisitos)
- [Quickstart](#-quickstart)
- [Estructura](#-estructura)
- [Cobertura de macros](#-cobertura-de-macros)
- [Cómo funciona](#-cómo-funciona)
- [Uso en otro proyecto dbt](#-uso-en-otro-proyecto-dbt)
- [Limitaciones conocidas](#-limitaciones-conocidas)
- [Troubleshooting](#-troubleshooting)
- [Recursos](#-recursos)
- [Contribuir](#-contribuir)
- [Licencia](#-licencia)

---

## ✨ Características

- **57 macros Jinja** cross-db organizadas en 8 categorías
- **100% cobertura** de macros con modelos de ejemplo
- **Capa SQL automática** en Postgres que emula Redshift
- **Uso como package** en otros proyectos dbt
- **Soporte multi-plataforma**: macOS, Linux, WSL, Windows
- **Runtimes flexibles**: Postgres nativo, Docker, Podman, RDS
- **Herramientas para comparar paridad** entre motores (CSV diff)
- **Documentación completa** con comentarios pedagógicos

---

## 🔧 Requisitos

| Herramienta | Versión | Verificar |
|---|---|---|
| Python | 3.9+ | `python3 --version` |
| pip | reciente | `pip3 --version` |
| Git | cualquiera | `git --version` |
| dbt-core | 1.8+ | `dbt --version` |
| dbt-postgres | 1.8+ | `dbt --version` |
| dbt-redshift | 1.8+ | `dbt --version` |
| PostgreSQL | 14+ | accesible por red |

---

## 🚀 Quickstart

> **Si tu entorno ya tiene Python y dbt instalados**, saltar el paso 1 y entrar al directorio del proyecto desde donde ejecutas dbt.

```bash
git clone https://github.com/alejandrogenovese/fix_postgres_redshift_dbt.git
cd fix_postgres_redshift_dbt

# 1. (Opcional) Python+dbt en venv local
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install "dbt-core>=1.8" "dbt-postgres>=1.8" "dbt-redshift>=1.8"

# 2. Configurar profiles
mkdir -p ~/.dbt
cp profiles.yml.example ~/.dbt/profiles.yml
# Editar ~/.dbt/profiles.yml o exportar env vars (POSTGRES_HOST, etc.)

# 3. Instalar dependencias dbt y verificar
dbt deps
dbt debug

# 4. Correr ejemplos
dbt seed --select compat_test_users
dbt run --select tag:compat_examples
dbt test --select tag:compat_examples
```

**Setup detallado:** ver [INSTALACION.md](INSTALACION.md)

---

## 📁 Estructura

```
.
├── README.md                           ← estás acá
├── INSTALACION.md                      ← setup paso a paso
├── dbt_project.yml                     ← config dbt + on-run-start hook
├── packages.yml                        ← dependencias (dbt-utils)
├── profiles.yml.example                ← plantilla de conexiones
│
├── macros/
│   ├── compat/
│   │   └── install_postgres_compat.sql ← capa SQL de funciones Redshift-compat
│   ├── cross_db/                       ← 8 categorías, 57 macros Jinja
│   │   ├── aggregations.sql
│   │   ├── dates.sql
│   │   ├── json.sql
│   │   ├── nulls.sql
│   │   ├── regex.sql
│   │   ├── strings.sql
│   │   ├── types.sql
│   │   └── unnest.sql
│   └── utils/
│       └── export_compat_results.sql
│
├── models/
│   └── examples/                       ← 100% cobertura de macros
│       ├── example_aggregations.sql
│       ├── example_dates.sql
│       ├── example_json.sql
│       ├── example_nulls.sql
│       ├── example_regex.sql
│       ├── example_strings.sql
│       ├── example_types.sql
│       ├── example_unnest.sql
│       └── schema.yml
│
└── seeds/
    ├── compat_test_users.csv
    └── properties.yml
```

---

## 🎯 Cómo funciona

Los modelos invocan macros como `{{ median(col) }}` o `{{ nvl(a, b) }}`. Al compilar:

- **Contra Postgres** → renderiza equivalencias (`coalesce(a, b)`, `percentile_cont(0.5)`, etc.) y se apoya en una capa SQL de funciones que el proyecto instala automáticamente
- **Contra Redshift** → renderiza funciones nativas (`nvl(a, b)`, `median(col)`)

El SQL final es distinto, pero el resultado es equivalente.

---

## 📊 Cobertura de macros

| Categoría | # Macros | Modelo de ejemplo |
|---|---|---|
| Fecha/tiempo | 10 | `example_dates.sql` |
| NULL/condicionales | 6 | `example_nulls.sql` |
| Strings | 11 | `example_strings.sql` |
| Regex | 5 | `example_regex.sql` |
| Agregadas/analíticas | 8 | `example_aggregations.sql` |
| JSON/SUPER | 8 | `example_json.sql` |
| Arrays/UNNEST | 3 | `example_unnest.sql` |
| Tipos/casts | 6 | `example_types.sql` |
| **Total** | **57** | **100% cubierto** |

Cada modelo tiene comentarios pedagógicos explicando qué hace cada macro y cuándo usarla.

---

## 📦 Uso en otro proyecto dbt

Agregar al `packages.yml` del proyecto destino:

```yaml
packages:
  - git: "https://github.com/alejandrogenovese/fix_postgres_redshift_dbt.git"
    revision: main   # o un tag versionado
```

Y en el `dbt_project.yml` del proyecto destino:

```yaml
on-run-start:
  - "{{ install_postgres_compat() }}"
```

> Las macros quedan namespaced bajo `galicia_dbt_compat`. Para invocar sin namespace, configurar `dispatch` en el `dbt_project.yml`.

---

## ⚠️ Limitaciones conocidas

- `MEDIAN` agregado: siempre vía `{{ median(col) }}`
- `MONTHS_BETWEEN` con decimales: usar `months_between_decimal`
- `DECODE` con NULLs: agregar `WHEN expr IS NULL` explícito si es necesario
- `APPROXIMATE COUNT DISTINCT` en Postgres: cae a count distinct exacto
- SUPER nested + UNNEST: solo casos simples soportados

---

## 🔍 Comparar paridad Postgres ↔ Redshift

```bash
mkdir -p compare/postgres compare/redshift

# Postgres
for m in example_dates example_nulls example_strings example_regex \
        example_aggregations example_json example_unnest example_types; do
  PGPASSWORD="$POSTGRES_PASSWORD" psql -h "$POSTGRES_HOST" -U "$POSTGRES_USER" \
    -d "$POSTGRES_DB" -c \
    "\COPY (select * from ${POSTGRES_SCHEMA}.${m} order by 1) TO \
    'compare/postgres/${m}.csv' WITH CSV HEADER"
done

# Redshift
for m in example_dates example_nulls example_strings example_regex \
        example_aggregations example_json example_unnest example_types; do
  PGPASSWORD="$REDSHIFT_PWD" psql "host=$REDSHIFT_HOST port=5439 dbname=$REDSHIFT_DB \
    user=$REDSHIFT_USER sslmode=require" -c \
    "\COPY (select * from ${REDSHIFT_SCHEMA}.${m} order by 1) TO \
    'compare/redshift/${m}.csv' WITH CSV HEADER"
done

# Comparar
diff -r compare/postgres compare/redshift
```

---

## 🆘 Troubleshooting

Ver [INSTALACION.md → Sección 10](INSTALACION.md#10-troubleshooting)

---

## 📚 Recursos

- [Documentación oficial dbt](https://docs.getdbt.com/)
- [dbt cross-db macros](https://docs.getdbt.com/reference/dbt-jinja-functions/cross-database-macros)
- [dbt-utils](https://github.com/dbt-labs/dbt-utils)
- [Análisis dbt con Postgres vs Redshift](https://github.com/alejandrogenovese/fix_postgres_redshift_dbt/blob/main/analisis%20dbt%20con%20postgres%20vs%20redshift.docx)

---

## 🤝 Contribuir

Las contribuciones son bienvenidas. Por favor:

1. Fork el repositorio
2. Crea una rama con tu feature (`git checkout -b feature/AmazingFeature`)
3. Commit tus cambios (`git commit -m 'Add some AmazingFeature'`)
4. Push a la rama (`git push origin feature/AmazingFeature`)
5. Abre un Pull Request

---

## 📄 Licencia

Este proyecto está licenciado bajo la MIT License. Ver [LICENSE](LICENSE) para más detalles.

---

**Alejandro Genovese**  
*Líder de Arquitectura Data*
