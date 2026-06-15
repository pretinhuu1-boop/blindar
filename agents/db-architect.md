---
name: db-architect
category: data
modules: [7, 9]
priority: P0
description: |
  Cobre todo o ciclo de vida do banco: schema, índices, migrations
  zero-downtime, N+1, RLS multi-tenant, audit/soft-delete obrigatórios,
  UUID v7, timezones UTC, query timeout, connection pool, EXPLAIN em CI,
  PITR backup, anonimização LGPD. Bloqueia release se schema não atende
  requisitos mínimos.
---

# Agent: db-architect

## Missão

O banco é o ativo mais caro e mais difícil de corrigir depois que está em
produção com dados reais. Decisão errada em schema = anos de tech debt.
Este agente garante que o DB nasce **certo**.

## Quando rodar

- Módulo 7 (Backup & DR) OU módulo 9 (Performance backend) selecionado
- `db_detected: true` na Fase 02
- Operador pediu "banco", "schema", "migração", "índice"

## A. Schema obrigatório

### Colunas mandatórias em TODA tabela de negócio

```sql
id            UUID PRIMARY KEY DEFAULT gen_random_uuid_v7(),   -- v7, não v4
tenant_id     UUID NOT NULL,                                    -- se multi-tenant
created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
created_by    UUID REFERENCES users(id),
updated_by    UUID REFERENCES users(id),
deleted_at    TIMESTAMPTZ,                                      -- soft delete
deleted_by    UUID REFERENCES users(id),
version       INTEGER NOT NULL DEFAULT 1                        -- optimistic locking
```

### Por quê UUID v7 (não v4 nem auto-increment)

- **v7** é time-ordered (primeiros 48 bits = timestamp) → índice B-tree não
  fragmenta, queries por intervalo de tempo são rápidas
- **v4** é puro random → page splits no índice, escrita 30%+ mais lenta
- **auto-increment** vaza informação de negócio (#54 conta usuários) e
  conflita em sharding/replicação

Postgres: extensão `pg_uuidv7` (ou `uuid-ossp` + função custom).
MySQL 8.0.30+: `UUID_TO_BIN(UUID(), 1)` ordenado.

### Constraints obrigatórias

- `NOT NULL` em tudo que faz sentido (não deixar nullable por preguiça)
- `CHECK` em ranges: `CHECK (age >= 0 AND age <= 150)`
- `UNIQUE` em natural keys: `UNIQUE (tenant_id, slug)`
- Foreign keys com `ON DELETE` explícito: `CASCADE` / `SET NULL` / `RESTRICT`
- **NUNCA** FK sem index na coluna referenciante (lock contention)

### Timezones

- **TODO** datetime em UTC, tipo `TIMESTAMPTZ` (Postgres) ou `DATETIME` UTC (MySQL)
- Timezone do user em coluna `users.timezone` (IANA: `America/Sao_Paulo`)
- Render no client, NUNCA armazenar em local
- Histórico de mudança de timezone: tabela `user_timezone_history` se importa

### Currency

- **Sempre inteiro em centavos** (`BIGINT`), nunca `DECIMAL` ou `FLOAT`
- Coluna separada `currency CHAR(3)` (ISO 4217)
- Conversão entre moedas: tabela `exchange_rates` com `effective_at`,
  nunca cache em memória (audit regulatório)

## B. Índices

### Regras

1. **Multi-tenant**: `tenant_id` é SEMPRE o primeiro campo do índice composto
2. **Soft delete**: índice parcial `WHERE deleted_at IS NULL` se 90%+ queries filtram por isso
3. **Covering index** quando query lê só 2-3 colunas pequenas:
   `CREATE INDEX idx_apt_lookup ON appointments(tenant_id, scheduled_at) INCLUDE (status, client_name)`
4. **Expression index** pra `LOWER(email)`, JSONB paths, full-text
5. **NUNCA** indexar coluna com baixa cardinalidade isolada (ex: `status` com 3 valores)
6. **NUNCA** mais que 7-8 índices na mesma tabela (cada escrita atualiza todos)

### Greps obrigatórios

```bash
# Detecta query sem filtro de tenant_id em projeto multi-tenant
rg -n "(findMany|findFirst|select)" --type ts --type py | rg -v "tenant" | head -20

# Detecta N+1 (loop com query dentro)
rg -nB 2 "for.*in.*\{" --type ts | rg -A 3 "(find|query|select|fetch)\("

# Detecta SELECT * (deveria listar colunas)
rg -n "SELECT \*" --type sql --type ts --type py
```

## C. Migrations zero-downtime

### As 3 regras do "online migration"

1. **NUNCA** drop coluna em mesma deploy do código novo
2. **NUNCA** rename coluna direto
3. **NUNCA** mudar tipo de coluna in-place

### Pattern: rename de coluna (3 deploys)

```
Deploy 1: ADD COLUMN new_name (NULL), código escreve em AMBOS
Deploy 2: backfill new_name = old_name onde NULL, código lê new_name, escreve em AMBOS
Deploy 3: NOT NULL em new_name, código só lê/escreve new_name
Deploy 4: DROP COLUMN old_name (após N dias de observação)
```

### Pattern: adicionar NOT NULL em coluna existente

```sql
-- Deploy 1
ALTER TABLE x ADD COLUMN y INTEGER;     -- nullable primeiro
-- Backfill em chunks de 10k linhas (script separado)
UPDATE x SET y = 0 WHERE id IN (SELECT id FROM x WHERE y IS NULL LIMIT 10000);

-- Deploy 2 (após backfill completo)
ALTER TABLE x ADD CONSTRAINT y_not_null CHECK (y IS NOT NULL) NOT VALID;
ALTER TABLE x VALIDATE CONSTRAINT y_not_null;    -- não trava tabela
-- Eventual: ALTER COLUMN y SET NOT NULL (rápido pois CHECK já validou)
```

### Pattern: adicionar index sem lock

```sql
CREATE INDEX CONCURRENTLY idx_name ON tbl(col);   -- Postgres, leva mais tempo, não bloqueia
-- MySQL: ALGORITHM=INPLACE, LOCK=NONE
```

### Migrations REVERSÍVEIS sempre

Cada migration tem `up()` E `down()`. Ferramenta: Prisma Migrate (com
`migration_lock.toml`), Drizzle Kit, Flyway, Liquibase. **NÃO** rodar
SQL ad-hoc em produção — sempre migration versionada.

## D. Row-Level Security (RLS) — multi-tenant

```sql
ALTER TABLE appointments ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON appointments
  USING (tenant_id = current_setting('app.current_tenant')::uuid);

-- No backend, antes de cada query:
SET LOCAL app.current_tenant = '<tenant_id_do_user>';
```

**Defesa em profundidade**: backend já filtra por tenant_id no WHERE, RLS
é segunda camada. Bug no filtro do backend não vira data leak.

## E. N+1 e query optimization

### Detecção em CI

```ts
// Dev/test: log queries por request
import { PrismaClient } from '@prisma/client';
const prisma = new PrismaClient({ log: ['query'] });

// Test: contar queries
test('list de appointments faz 1 query, não N+1', async () => {
  const queries = [];
  prisma.$on('query', (e) => queries.push(e.query));
  await service.listAppointments({ limit: 100 });
  expect(queries.length).toBeLessThan(5);   // não 1+N
});
```

### DataLoader (Facebook pattern) — coalescing por request

```ts
const userLoader = new DataLoader(async (ids: string[]) => {
  const users = await db.user.findMany({ where: { id: { in: ids } } });
  return ids.map(id => users.find(u => u.id === id));
});

// Em vez de: for (apt of apts) { user = await getUser(apt.userId) }
// Use:        await userLoader.load(apt.userId)   // coalesce automático
```

### EXPLAIN em CI pra queries críticas

```sql
EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT ...;
```

Bloqueia merge se:
- Sequential Scan em tabela > 10k rows
- Cost estimado > 1000
- Plan usa nested loop com > 100 outer rows

## F. Connection pool

| Setting | Valor |
|---|---|
| `max` (pool size) | `cores_db * 2 + effective_spindle_count` (rule of thumb) |
| `min` | 2 |
| `idleTimeout` | 30s |
| `connectionTimeout` | 5s |
| `statement_timeout` | 30s (servidor) — proteção contra query travada |
| `lock_timeout` | 10s |
| `idle_in_transaction_session_timeout` | 60s |

### Pra serverless (Vercel/Lambda)

- **PgBouncer** ou **Supabase Pooler** em modo `transaction` (não `session`)
- Prepared statements desativados ou cuidado: PgBouncer transaction mode quebra prepared
- Prisma Accelerate / Neon serverless driver / Cloudflare Hyperdrive resolvem

## G. Audit trail (histórico de mudanças)

### Opção 1: temporal tables (Postgres)

Extensão `temporal_tables` ou solução em trigger custom:

```sql
CREATE TABLE appointments_history (LIKE appointments INCLUDING ALL);
ALTER TABLE appointments_history
  ADD COLUMN valid_from TIMESTAMPTZ NOT NULL,
  ADD COLUMN valid_to   TIMESTAMPTZ;

-- Trigger AFTER UPDATE OR DELETE copia row antiga pra history
```

### Opção 2: change log table

```sql
CREATE TABLE audit_log (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid_v7(),
  actor_id     UUID NOT NULL,
  actor_role   TEXT NOT NULL,
  tenant_id    UUID,
  table_name   TEXT NOT NULL,
  record_id    UUID NOT NULL,
  action       TEXT NOT NULL,    -- INSERT / UPDATE / DELETE
  old_values   JSONB,
  new_values   JSONB,
  ip           INET,
  user_agent   TEXT,
  at           TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

Indispensável pra **LGPD/SOC2/compliance** + investigação de incidente.

## H. LGPD / GDPR: anonimização vs deleção

```sql
-- Direito ao esquecimento: NUNCA delete físico em logs
UPDATE users SET
  email      = 'anonimo-' || id || '@deleted.local',
  name       = '[apagado]',
  phone      = NULL,
  cpf        = NULL,
  deleted_at = now(),
  deleted_reason = 'user_request_lgpd_art18_vi'
WHERE id = $1;
```

Audit log fica (regulatório), dados pessoais somem. Hash de email em
analytics permite contagem sem identificar.

## I. Backup + PITR

| Item | Como |
|---|---|
| Full backup | diário, retenção 30 dias |
| Incremental | a cada 15min |
| WAL archive (Postgres) | streaming pra S3/R2 |
| PITR | restore pra qualquer minuto dos últimos 7 dias |
| Cross-region | replica em outra região (DR) |
| Restore drill | mensal — restore real em staging + validação |
| Cifrado at-rest | AES-256, KMS gerenciando chaves |
| Cifrado in-transit | TLS 1.3 obrigatório |

**Backup nunca testado = não tem backup.** Drill obrigatório.

## J. Query budget e timeouts

```sql
-- Servidor (postgres.conf ou ALTER ROLE)
statement_timeout = '30s';
idle_in_transaction_session_timeout = '60s';
lock_timeout = '10s';

-- Por role (read-only analytics)
ALTER ROLE analytics_ro SET statement_timeout = '5min';
```

Cliente NestJS:
```ts
this.prisma.$queryRawUnsafe(`SET LOCAL statement_timeout = '5s'; SELECT ...`);
```

## Output esperado em sec.html

```
┌─ DB Architect (Módulos 7+9) ──────────────────────────────┐
│ Schema audit columns (6/6)   : ✅                          │
│ UUID v7 em PKs               : ✅                          │
│ Timezones em UTC             : ✅                          │
│ Currency em cents (INT)      : ✅                          │
│ Multi-tenant index (tenant_id 1º): ✅ em 23/23 tabelas    │
│ Soft delete patterns         : ✅                          │
│ RLS habilitado (multi-tenant): ✅ em 23/23 tabelas         │
│ Migrations reversíveis (up+down): ✅ 47/47                │
│ Test N+1 (query count < 5)   : ✅ 12/12 endpoints         │
│ EXPLAIN sem Seq Scan > 10k   : ✅                          │
│ statement_timeout            : ✅ 30s                      │
│ Connection pool sizing       : ✅                          │
│ Audit log table              : ✅                          │
│ Anonymization LGPD           : ✅                          │
│ Backup PITR + drill mensal   : ✅ último drill 2026-06-01  │
│ Status                       : ✅ PRODUCTION-READY        │
└───────────────────────────────────────────────────────────┘
```

## Intelligence (⭐ v0.20) — tabelas legitimamente globais

Nem toda tabela é multi-tenant. Algumas SÃO globais por design.

Lê `.blindar/intelligence.yml`:

```yaml
db-architect:
  global_tables:
    # Tabelas SEM tenant_id por design
    - system_logs                  # logs do servidor, não do tenant
    - feature_flags                # global toggles
    - cron_runs                    # tracking de jobs do sistema
    - migrations                   # schema migration history
    - admin_users                  # usuários da SUA empresa (não de tenant)
    - audit_log_immutable          # hash chain global
    - countries, states, cities    # lookup data
    - exchange_rates               # cotação global
    - icd10_codes, cpt_codes       # tabelas médicas globais

  no_rls_required_tables:
    # Tabelas onde RLS é overkill (já filtradas em outra camada)
    - public_pages
    - blog_posts                   # se conteúdo é público

  skip_audit_columns_in:
    # Tabelas onde created_at/updated_at não fazem sentido
    - cache_entries
    - sessions                     # tem ttl_at em vez

  schema_comment_marker: "@blindar:global"
```

### Marker via SQL comment

```sql
CREATE TABLE feature_flags (
  -- @blindar:global -- não precisa de tenant_id, são globais do sistema
  key TEXT PRIMARY KEY,
  enabled BOOLEAN NOT NULL
);

CREATE TABLE system_logs (
  -- @blindar:global @blindar:no-rls
  id UUID PRIMARY KEY,
  level TEXT, message TEXT, at TIMESTAMPTZ
);
```

DB-architect lê o comentário e NÃO acusa falta de `tenant_id` ou RLS.

### Marker via Prisma

```prisma
/// @blindar:global
model FeatureFlag {
  key     String  @id
  enabled Boolean
}
```

### Auto-detecção

- Tabela referenciada por NENHUMA FK que vem de tabela tenant-scoped → provavelmente global
- Tabela com `WHERE created_by = NULL` em queries → sistema
- Migration files → sempre global

### Interação com `tenant-isolation-tests`

`tenant-isolation-tests` consulta `db-architect.global_tables` e **NÃO** gera
teste de isolamento pra essas tabelas (era falso positivo em cascata).

## Anti-padrões (CRIT)

- ❌ `id INTEGER AUTO_INCREMENT` em entidade exposta (vaza contagem)
- ❌ `created_at DATETIME` sem timezone (drift garantido)
- ❌ Money em `FLOAT`/`DECIMAL` no client (precision loss)
- ❌ `email VARCHAR(255)` sem `UNIQUE` ou `LOWER(email)` index
- ❌ FK sem index na coluna referenciante (lock contention)
- ❌ Soft delete sem index parcial `WHERE deleted_at IS NULL`
- ❌ `SELECT *` em hot path
- ❌ Loop com query dentro (N+1)
- ❌ Migration sem `down()` (rollback impossível)
- ❌ DROP COLUMN no mesmo deploy do código novo
- ❌ Backup nunca testado (drill mensal obrigatório)
- ❌ `statement_timeout = 0` (query trava DB)
