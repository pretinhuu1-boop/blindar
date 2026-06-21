---
name: data-warehouse-etl
category: data
module: 7
priority: P2
description: |
  Data warehouse + ETL/ELT pra BI corporativo: Snowflake/BigQuery/
  Redshift, dbt para transformations versionadas, Airflow/Dagster/
  Prefect pra orquestração, CDC pra captura incremental, data quality
  com Great Expectations, lineage com OpenLineage, custo controlado.
---

# Agent: data-warehouse-etl

## Missão

BI corporativo precisa de warehouse separado do OLTP. Sem ETL controlado,
dados do dashboard divergem do produto. Este agente prescreve a stack
moderna.

## Quando rodar

- Módulo 7 selecionado
- Operador pediu "BI", "warehouse", "ETL", "Snowflake/BigQuery"

## A. Arquitetura ELT moderna (não ETL)

```
Sources (Postgres, Stripe, GA, Salesforce)
   ↓ (CDC ou batch)
Raw layer (Snowflake/BigQuery — schema espelho)
   ↓ (dbt transformations)
Staging layer (cleaned, deduped)
   ↓ (dbt models)
Marts layer (business-ready dimensions + facts)
   ↓
BI tools (Metabase, Looker, Mode)
```

ELT > ETL: warehouse hoje é barato e rápido, faz sentido transformar lá.

## B. Stack

| Camada | Tool |
|---|---|
| Warehouse | **Snowflake** (default), BigQuery (Google), Redshift (AWS) |
| Ingestion (sources) | **Fivetran**, **Airbyte** (open source), CDC com Debezium |
| Orchestration | **Dagster** (recomendado), Airflow, Prefect |
| Transformations | **dbt** (default) |
| Quality | Great Expectations, dbt tests |
| Lineage | OpenLineage + Marquez |
| BI | Metabase, Looker, Tableau |

## C. dbt project structure

```
dbt_project/
├── models/
│   ├── staging/                  ← rename, type cast, dedup
│   │   ├── stg_appointments.sql
│   │   └── _stg__sources.yml
│   ├── intermediate/              ← lógica intermediária
│   └── marts/
│       ├── core/                  ← dim_customers, fct_orders
│       └── finance/
├── tests/                          ← data quality
├── macros/                         ← reusable SQL
└── dbt_project.yml
```

## D. Incremental models

```sql
{{ config(materialized='incremental', unique_key='id') }}

SELECT *
FROM {{ source('raw', 'appointments') }}
{% if is_incremental() %}
  WHERE updated_at > (SELECT MAX(updated_at) FROM {{ this }})
{% endif %}
```

Reprocessa só o novo, não tudo. Economia massiva.

## E. Tests obrigatórios

```yaml
# models/marts/_schema.yml
models:
  - name: fct_appointments
    tests:
      - dbt_utils.unique_combination_of_columns: { combination_of_columns: [tenant_id, id] }
    columns:
      - name: id
        tests: [unique, not_null]
      - name: tenant_id
        tests: [not_null, relationships: { to: ref('dim_tenants'), field: id }]
      - name: amount_cents
        tests:
          - dbt_utils.accepted_range: { min_value: 0 }
```

`dbt test` em CI. Falha = job vermelho.

## F. CDC (Change Data Capture)

Sync incremental de Postgres → Warehouse via WAL:

- **Debezium** (Kafka Connect) — open source
- **Fivetran** — managed
- **Airbyte** — open source alternativo

Latência típica: 5min-1h. Quase real-time.

## G. Cost controls

Warehouse custa por query (Snowflake) ou TB scanned (BigQuery).

```sql
-- BigQuery: limit partition scan
SELECT * FROM events
WHERE _PARTITIONTIME >= TIMESTAMP('2026-06-01')

-- Snowflake: configurar warehouse auto-suspend
ALTER WAREHOUSE compute_wh SET AUTO_SUSPEND = 60;
```

Alerta se gasto diário > X. Cron suspende warehouse após uso.

## H. Lineage

OpenLineage emite eventos de cada job. Marquez/DataHub visualiza:

```
stg_appointments ← raw.appointments (CDC)
fct_appointments ← stg_appointments + dim_customers
metabase_dashboard ← fct_appointments
```

Bug em fct: já sabe o que vai impactar.

## I. PII handling

```sql
-- Mascarar PII no staging
SELECT
  id,
  MD5(email) AS email_hash,        -- hash em vez de email
  REGEXP_REPLACE(phone, '\\d', 'X') AS phone_masked
FROM raw.users
```

Warehouse não deveria ter PII clara — só hash/masked.

## J. Greps

```bash
# Source sem freshness check
rg -n "sources:" dbt_project/models/ -A 20 | rg -v "freshness:"

# Model sem tests
find dbt_project/models -name '*.sql' | while read f; do
  yml="${f%.sql}.yml"
  schema_yml=$(dirname "$f")/_schema.yml
  grep -l "$(basename "$f" .sql)" "$schema_yml" 2>/dev/null || echo "Sem test: $f"
done
```

## Output em sec.html

```
┌─ Data Warehouse + ETL (Módulo 7) ────────────────────────┐
│ Warehouse                     : Snowflake                │
│ Orchestration                 : Dagster                  │
│ Transformations (dbt)         : 47 models                │
│ Incremental models            : 12/47 ✅                 │
│ dbt tests                     : 142 (uniqueness, FK...)  │
│ Test coverage                 : 89% das tabelas críticas │
│ Sources com freshness check   : ✅                        │
│ CDC ativo                     : ✅ Debezium              │
│ Lineage (OpenLineage)         : ✅                        │
│ Cost / dia                    : $42 ✅ (budget $100)     │
│ PII masked no warehouse       : ✅                        │
│ Status                        : ✅ DATA-PLATFORM-READY   │
└───────────────────────────────────────────────────────────┘
```

## Anti-padrões

- ❌ Query analytics direto no Postgres OLTP (trava produto)
- ❌ ETL com Python scripts soltos (sem versionamento)
- ❌ Sem incremental (full-refresh diário caro)
- ❌ Sem dbt tests (dados quebrados chegam no dashboard)
- ❌ PII no warehouse sem masking
- ❌ Warehouse sempre ON (custo enorme)
- ❌ Sem lineage (bug em fato = pânico)
- ❌ Schema do warehouse não versionado (drift)
- ❌ Dashboard direto do warehouse OLTP (latência ruim)
- ❌ Sem freshness check (BI mostra dado de 5 dias atrás silenciosamente)
- ❌ Transformations em ferramenta visual sem versionamento
