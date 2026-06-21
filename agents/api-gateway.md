---
name: api-gateway
category: api
module: 4
priority: P2
description: |
  Kong/Tyk/AWS API Gateway/Apigee: routing, rate limit per consumer,
  API keys/JWT validation no gateway (não no app), plans + quotas,
  transformação request/response, monetização (paywall API),
  analytics. Quando API vira produto vendido a terceiros.
---

# Agent: api-gateway

## Missão

API exposta a terceiros não pode ter rate limit no controller. Cada
caller precisa de identidade, quota, billing, analytics. Gateway dedicado
resolve. Este agente prescreve quando + como.

## Quando rodar

- Módulo 4 selecionado
- API exposta a terceiros / partners (não só frontend próprio)
- Operador pediu "API gateway", "monetizar API", "plans/quotas"

## A. Quando usar

| Vale | NÃO vale |
|---|---|
| API pública / B2B / parceiros | Frontend próprio único consumer |
| Múltiplos planos com quotas | API interna entre services |
| Billing por uso | API simples sem monetização |
| Múltiplos backends consolidados | Monolito único |

## B. Opções

| Gateway | Quando |
|---|---|
| **Kong** (open source + enterprise) | Self-hosted, flexível |
| **Tyk** | Self-hosted, dashboard rico |
| **AWS API Gateway** | All-in AWS |
| **Apigee** (Google) | Enterprise, analytics |
| **Cloudflare API Shield** | DDoS + bot protection |
| **Hono + manual** | Edge-first, leve |

## C. Features que gateway DEVE ter

- **Authentication**: API key, JWT, OAuth2, mTLS
- **Rate limiting** por consumer (não só IP)
- **Quotas** mensais com hard/soft limit
- **Caching** de responses
- **Request transformation** (renomear campos, defaults)
- **Response transformation** (filtrar campos por plan)
- **Logging + analytics** por consumer
- **Versioning** (rotear /v1/ pra backend antigo, /v2/ pro novo)
- **Circuit breaking** pra backends caídos
- **WAF** integrado

## D. API key management

```sql
CREATE TABLE api_keys (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid_v7(),
  consumer_id     UUID NOT NULL,                -- usuário/empresa
  key_hash        TEXT UNIQUE NOT NULL,         -- bcrypt da key real
  key_prefix      TEXT NOT NULL,                -- 'sk_live_abc123' (mostrar parcialmente)
  plan            TEXT NOT NULL,                -- free/pro/enterprise
  scopes          TEXT[],                       -- ['read:appointments', 'write:clients']
  rate_limit_rpm  INTEGER NOT NULL DEFAULT 60,
  quota_monthly   INTEGER NOT NULL,
  expires_at      TIMESTAMPTZ,
  last_used_at    TIMESTAMPTZ,
  revoked_at      TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

UI pra consumer:
- Criar key (mostra UMA vez, depois só prefix)
- Revogar
- Ver uso atual
- Ver histórico de chamadas

## E. Rate limit (sliding window por key)

```ts
// Kong / Redis-based
const key = `rl:${api_key}:${Math.floor(Date.now() / 60_000)}`;  // por minuto
const count = await redis.incr(key);
if (count === 1) await redis.expire(key, 120);
if (count > limit) return res.status(429).header('Retry-After', '60').json({ error: 'rate_limited' });
```

Headers obrigatórios:
```
RateLimit-Limit: 100
RateLimit-Remaining: 87
RateLimit-Reset: 1718365000
```

## F. Quota mensal

```ts
const monthKey = `quota:${api_key}:${new Date().toISOString().slice(0, 7)}`;
const used = await redis.incr(monthKey);
if (used > plan.quota) {
  if (plan.hard_limit) return res.status(402).json({ error: 'quota_exceeded' });
  // soft: alerta mas deixa passar (cobra extra)
}
```

## G. Plans

```sql
CREATE TABLE api_plans (
  name            TEXT PRIMARY KEY,
  rate_limit_rpm  INTEGER NOT NULL,
  quota_monthly   INTEGER NOT NULL,
  hard_limit      BOOLEAN NOT NULL DEFAULT true,
  price_usd       DECIMAL(10,2) NOT NULL,
  scopes          TEXT[] NOT NULL,
  overage_price_per_1000 DECIMAL(10,4)
);

-- Free:       60 rpm, 1000/mês, hard limit
-- Pro:        300 rpm, 50000/mês, soft (overage $0.10/1000)
-- Enterprise: 5000 rpm, ilimitado, custom
```

## H. Documentação pública (Developer Portal)

- OpenAPI live em `/developers/docs`
- API keys self-service
- Sandbox env (não conta na quota)
- Playground (try it out)
- SDKs em 5+ linguagens
- Status page
- Changelog público de breaking changes
- Webhooks documentation

## I. Versionamento

```
/v1/appointments → backend v1 (manter 12 meses após deprecation)
/v2/appointments → backend v2 (current)
```

Headers:
```
Sunset: Wed, 31 Dec 2026 23:59:59 GMT
Deprecation: true
Link: <https://docs.example.com/migrate-to-v2>; rel="deprecation"
```

## J. Greps

```bash
# Rate limit no controller (deveria ser no gateway)
rg -n "@RateLimit|@Throttle" --type ts -g 'src/modules/'

# API key em URL (vaza em logs)
rg -n "\\?api_?key=" --type ts

# Sem auth em endpoint sensível
rg -n "@Post\(['\"]/api" --type ts -A 5 | rg -v "@Auth|@UseGuards"
```

## Output em sec.html

```
┌─ API Gateway (Módulo 4) ─────────────────────────────────┐
│ Gateway                       : Kong (self-hosted)        │
│ Auth (API key + JWT)          : ✅                         │
│ Rate limit per consumer       : ✅ sliding window         │
│ Quotas mensais                : ✅ free/pro/enterprise    │
│ Headers RateLimit-*           : ✅ IETF draft             │
│ Plans configurados            : 3 (free/pro/enterprise)   │
│ Consumers ativos              : 247                       │
│ Top consumer (mês)            : 87% da quota              │
│ Caching de GET                : ✅ 60s default            │
│ Circuit breaker pra backends  : ✅                         │
│ Developer portal              : ✅ /developers           │
│ Sandbox env                   : ✅                         │
│ SDKs gerados                  : 5 (TS, Python, Go, Java, Ruby)│
│ Status                        : ✅ MONETIZABLE            │
└───────────────────────────────────────────────────────────┘
```

## Anti-padrões

- ❌ Rate limit no controller (cada deploy mexe, performance ruim)
- ❌ API key em URL (vaza em logs/proxy/referer)
- ❌ API key sem prefix (não consegue identificar visualmente)
- ❌ API key gerada em código próprio sem entropia suficiente
- ❌ Sem revogação (key vazada vira eterna)
- ❌ Sem plans (todos consumers iguais = uns abusam, outros pagam)
- ❌ Quota sem soft/hard distinction (perde upsell de Enterprise)
- ❌ Documentação só em PDF (auto-gerar de OpenAPI)
- ❌ Sem sandbox (consumer testa em prod = vira incidente)
- ❌ Versionamento sem deprecation timeline (consumer não sabe quando upgrade)
- ❌ Mudança breaking sem comunicação prévia
