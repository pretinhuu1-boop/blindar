---
name: multi-region
category: resilience
module: 7
priority: P2
description: |
  DR/HA multi-region: active-passive vs active-active, replicação
  cross-region, failover DNS (Route53 health checks / Cloudflare),
  latency-based routing, conflict resolution em writes, RPO/RTO
  formais, tabletop exercises. Não é "AWS multi-AZ" — é multi-REGION.
---

# Agent: multi-region

## Missão

Region inteira do AWS/Vercel cai (raro mas acontece — us-east-1
periodicamente). Se SLA é 99.95%+, single-region não basta. Este agente
prescreve como montar multi-region sem inventar.

## Quando rodar

- Módulo 7 selecionado
- SLA alvo > 99.9% OU compliance exige DR cross-region
- Operador pediu "DR", "failover", "active-active"

## A. Modelos

| Modelo | RPO | RTO | Custo | Complexidade |
|---|---|---|---|---|
| Active-passive (warm standby) | 5min | 5-30min | 1.5x | Baixa |
| Active-passive (hot standby) | < 1min | 1-5min | 1.8x | Média |
| Active-active (read replicas) | 0 (reads) | 0 (reads) | 2x | Alta |
| Active-active (writes too) | 0 | 0 | 2.5x | Muito alta (conflicts) |

**Default razoável**: active-passive hot standby pra começar.

## B. Topologia exemplo

```
                    ┌─────────────────┐
                    │  Cloudflare DNS │  ← health check em ambos
                    │  failover policy│
                    └─────────────────┘
                          ↓     ↓ (failover)
            ┌─────────────┘     └──────────────┐
            ▼                                    ▼
    [Region primary]                      [Region secondary]
    sa-east-1 (São Paulo)                 us-east-1 (Virginia)
    - Vercel apps                         - Vercel apps (standby)
    - Postgres primary                    - Postgres read replica
    - Redis primary                        - Redis replica
    - S3 bucket (primary)                  - S3 bucket (CRR replicated)
```

## C. Database replication

### Postgres logical replication

```sql
-- Em primary
SELECT pg_create_logical_replication_slot('region_failover', 'pgoutput');

-- Em secondary
CREATE SUBSCRIPTION sub_from_primary
  CONNECTION 'host=primary.example.com port=5432 dbname=app'
  PUBLICATION pub_all;
```

Lag típico: < 1s pra writes pequenos. Monitorar.

### Managed: Aurora Global Database, Neon branching, Supabase replication, Cloudflare D1.

## D. Object storage

S3 Cross-Region Replication (CRR) automático com SSE-KMS. R2: zero-egress
entre regions Cloudflare.

## E. Failover DNS

```ts
// Cloudflare: 2 records weight + health check
// Quando primary fail, peso vai pra secondary
// TTL baixo (60s) pra propagação rápida
```

Route53: failover routing policy + health check em `/health/ready`.

## F. Application failover

```ts
// App detecta region:
const region = process.env.AWS_REGION || process.env.VERCEL_REGION;
const isPrimary = region === 'sa-east-1';

// Writes vão pro primary, reads podem usar replica local
if (operation.type === 'write') {
  await primaryDb.transaction(operation);
} else {
  await replicaDb.query(operation);  // local read
}
```

Em failover: replica vira primary.

## G. Conflict resolution (active-active writes)

```
Cenário: user edita perfil em region A, simultaneamente em region B.
Replication eventual consistency = conflito.
```

Estratégias:
1. **Last-writer-wins** (timestamp) — simples mas perde data
2. **CRDT** (Yjs/Automerge) — sem perda, mas precisa estrutura específica
3. **Versionamento** com merge manual — complexo
4. **Sharding por tenant** (cada tenant em 1 region) — evita conflito

Default: shard por tenant. Tenant A escreve só na region X.

## H. Tabletop exercise (DR drill)

Trimestral. Simula failover sem afetar prod:

```
Cenário: primary region cai às 14h00 numa sexta
Time: 4 pessoas (eng lead, devops, SRE, customer success)
Duração: 2h

1. (T+0)  PagerDuty alerta região primary down
2. (T+2)  On-call confirma — não é falso positivo
3. (T+5)  Inicia failover plan
4. (T+10) DNS swap (Cloudflare/Route53)
5. (T+15) Validar app respondendo do secondary
6. (T+20) Validar reads consistentes
7. (T+30) Status page atualizada, customer success comunica
8. (T+60) Postmortem
```

## I. RPO/RTO formais

| Métrica | Definição | Como medir |
|---|---|---|
| **RPO** (Recovery Point Objective) | Dado máximo perdido aceitável | Lag de replication entre regions |
| **RTO** (Recovery Time Objective) | Tempo máximo até voltar | DNS TTL + app boot + DB promote |

Documentar valores promessa no SLA:
- RPO: 1 minuto
- RTO: 10 minutos (com humano) / 30s (com automated failover)

## J. Custo

- Compute: 1.5-2x (standby pode ser menor)
- Egress entre regions: pode ser caro (AWS cobra)
- Storage CRR: 2x
- Monitoring: 1.2x (mais endpoints)

Não inicie multi-region prematuramente. Vale quando SLA exige.

## Output em sec.html

```
┌─ Multi-Region (Módulo 7) ────────────────────────────────┐
│ Modelo                        : Active-passive hot      │
│ Primary region                : sa-east-1 (São Paulo)   │
│ Secondary region              : us-east-1 (Virginia)    │
│ DNS failover                  : ✅ Cloudflare           │
│ Health checks                 : ✅ /health/ready (15s)  │
│ Postgres replication lag      : 240ms ✅ (meta < 1s)    │
│ S3 CRR                        : ✅                       │
│ Redis replication             : ✅                       │
│ RPO commit                    : 1 minuto                 │
│ RTO commit                    : 10 minutos              │
│ Drills realizados (ano)        : 4 ✅ (trimestral)      │
│ Último drill bem-sucedido      : 2026-04-15             │
│ Status                        : ✅ DR-READY             │
└───────────────────────────────────────────────────────────┘
```

## Anti-padrões

- ❌ Multi-region prematuro (custo sem benefício)
- ❌ Multi-AZ chamado de multi-region (AZ é dentro da mesma region)
- ❌ DNS TTL longo (failover demora pra propagar)
- ❌ Failover manual sem runbook
- ❌ Active-active sem strategy de conflict resolution
- ❌ Replication lag não-monitorado
- ❌ S3 sem CRR (perde objetos em DR)
- ❌ Drill anual (esquece como faz)
- ❌ Sem health check em endpoint que reflete dependências (só `/` retorna 200)
- ❌ Secrets diferentes em cada region (config drift)
- ❌ RPO/RTO sem teste real (numero no PowerPoint)
