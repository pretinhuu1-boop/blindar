---
name: cost-observability
category: ops
module: 6
priority: P2
description: |
  Visibilidade de custo em runtime: cloud (AWS/GCP/Vercel), DB (queries
  caras), 3rd-party (LLM, payment gateway, SMS, storage), com alertas
  automáticos antes da fatura chegar. Inclui budgets por feature/tenant,
  detecção de anomalias e cost dashboards.
---

# Agent: cost-observability

## Missão

Custo cloud silencioso é a #1 causa de startup queimar caixa. Query
ruim que escala linear com users → fatura cresce sem ninguém ver até
o boleto chegar. Este agente prescreve **alerta antes do dano**.

## Quando rodar

- Módulo 6 selecionado
- Tipo do projeto ∈ {saas, ecom, api} com tráfego crescente
- Operador mencionou "custo", "cloud", "AWS", "budget"

## A. Categorias de custo a monitorar

| Categoria | Sinal de alerta |
|---|---|
| **Compute** (EC2/Lambda/Cloud Run/Vercel) | CPU/RAM sustained > 70% por 24h |
| **DB** | Query > 1s, table > 10GB sem partition, IOPS alto |
| **Storage** (S3/R2/CloudFlare) | Crescimento > 20%/mês sem motivo aparente |
| **Egress** (banda saída) | > 1TB/mês inesperado (vídeo? hotlink?) |
| **CDN** | Cache hit rate < 80% (lib pagando origin desnecessariamente) |
| **LLM** (OpenAI/Anthropic/Gemini) | $ por user > meta, tokens/request alto |
| **Payment gateway** | Taxa por transação + adicionais (3DS, chargeback) |
| **Email/SMS** | Volume crescendo desproporcional a users |
| **Search engine** (Algolia/Meilisearch managed) | Records ou requests por mês |
| **Analytics** (PostHog/Mixpanel) | Events/mês cresce, plan estoura |

## B. Alertas obrigatórios

### Cloud provider native

```yaml
# AWS Budgets (CDK / Terraform)
budget:
  amount: 5000   # USD/mês
  alerts:
    - threshold: 50%    # alerta cedo
    - threshold: 80%
    - threshold: 100%
    - threshold: 120%   # vazou — investigar urgente
  recipients: [finance@x.com, eng@x.com, ceo@x.com]
```

GCP: `gcloud billing budgets`, Vercel: dashboard + Slack webhook, Cloudflare:
billing alerts.

### Anomalias (não threshold fixo)

- AWS Cost Anomaly Detection (built-in)
- Datadog Cost Anomaly
- Custom: comparar gasto últimas 24h com média dos últimos 7d, alerta se > 2σ

## C. LLM/AI cost tracking

Maior risco de fatura surpresa em apps com IA. Tracking obrigatório:

```ts
async function callLLM(messages: Message[], userId: string) {
  const start = Date.now();
  const res = await openai.chat.completions.create({ model: 'gpt-4o', messages });
  const duration = Date.now() - start;

  await db.llmUsage.create({
    data: {
      userId, tenantId, feature,    // qual feature da app
      model: 'gpt-4o',
      inputTokens: res.usage.prompt_tokens,
      outputTokens: res.usage.completion_tokens,
      costUsd: calculateCost(res.usage, 'gpt-4o'),
      durationMs: duration,
      cachedTokens: res.usage.prompt_tokens_details?.cached_tokens ?? 0
    }
  });

  // Alerta se user específico está queimando
  await checkUserDailyBudget(userId);
}
```

### Rate limit por user (anti-abuso)

```sql
-- Quotas por plano
plan_free:    100 LLM calls/day
plan_pro:     1000 LLM calls/day
plan_enterprise: 10000

-- Validar antes de cada call
SELECT count(*) FROM llm_usage
WHERE user_id = ? AND created_at > now() - interval '1 day';
```

### Prompt caching (Anthropic, Gemini)

Reduz custo 50-90% em prompts com contexto repetido. Cobrar uso real, não
estimado.

## D. DB cost optimization

### Queries caras

```sql
-- Detectar slow queries em prod
SELECT query, calls, total_exec_time / calls as avg_ms,
       total_exec_time, rows
FROM pg_stat_statements
WHERE total_exec_time > 1000
ORDER BY total_exec_time DESC LIMIT 20;
```

Cada query > 100ms em hot path = revisar (index? N+1? scan?).

### Tabela inchada

- TOAST overhead em colunas JSONB grandes
- Bloat por UPDATE pesado sem VACUUM
- Índices não-usados (custam escrita, não rendem leitura):
  ```sql
  SELECT indexrelname, pg_size_pretty(pg_relation_size(indexrelid))
  FROM pg_stat_user_indexes WHERE idx_scan = 0;
  ```

### Connection pool ruim

PgBouncer mal configurado → cada cliente abre conexão = DB CPU alto =
máquina maior = $$.

## E. Storage / egress

```bash
# Alerta de crescimento anormal
aws s3 ls --recursive --summarize s3://my-bucket | tail -2
# Compare semanal

# Lifecycle policies obrigatórias
# - Objetos temp/* → delete após 24h
# - Logs > 90d → Glacier
# - Backups antigos → expire
```

### Egress (saída de banda)

- Cloudflare R2 / Backblaze B2 → zero egress (alternativa a S3)
- CDN aggressive cache (immutable assets com hash no filename)
- Imagem servida com `Cache-Control: public, max-age=31536000, immutable`

## F. Per-feature cost attribution

```sql
CREATE TABLE feature_costs (
  feature       TEXT NOT NULL,        -- 'whatsapp-sync', 'pdf-export'
  date          DATE NOT NULL,
  cost_usd      DECIMAL(10,4) NOT NULL,
  calls         BIGINT NOT NULL,
  source        TEXT NOT NULL,        -- 'openai', 'twilio', 'aws-lambda'
  PRIMARY KEY (feature, date, source)
);
```

Dashboard "cost per feature" → mostra qual feature está pesando no orçamento.
Permite decidir: subir preço do plano? cortar feature? otimizar?

## G. Cost dashboard (Grafana / Looker / built-in)

Métricas pra mostrar diariamente:
- $/dia (rolling 30d)
- $/usuário ativo (custo unitário — métrica chave de SaaS)
- $/transação processada
- Top 5 features mais caras
- Top 5 tenants mais caros (se multi-tenant)
- Anomalias detectadas (lista)
- Forecast fim do mês (extrapolação)

## H. Greps em código

```bash
# LLM calls sem track de custo
rg -n "openai\.|anthropic\.|gemini\." --type ts | rg -v "track|usage|cost"

# Storage upload sem TTL
rg -n "s3\.putObject|r2\.put" --type ts | rg -v "Expires|TTL|lifecycle"

# SMS/email sem rate limit
rg -n "twilio|sendgrid|resend|aws-sdk.*ses" --type ts | rg -v "rateLimit|throttle"
```

## I. Budget por tenant (multi-tenant)

```sql
CREATE TABLE tenant_budgets (
  tenant_id     UUID PRIMARY KEY,
  monthly_usd   DECIMAL(10,2) NOT NULL,
  alert_at_pct  SMALLINT[] DEFAULT '{50,80,100}',
  hard_limit    BOOLEAN DEFAULT false,    -- bloqueia ações ao atingir 100%?
  current_usd   DECIMAL(10,2) DEFAULT 0,
  period_start  DATE NOT NULL
);
```

Tenant freemium pode ter `monthly_usd = 5, hard_limit = true` (bloqueia ao
atingir). Enterprise: `hard_limit = false` (avisa mas não bloqueia).

## Output esperado em sec.html

```
┌─ Cost Observability (Módulo 6) ──────────────────────────┐
│ Cloud budget + alertas        : ✅ AWS Budgets (50/80/100%)│
│ Anomaly detection             : ✅ AWS Cost Anomaly       │
│ LLM cost tracking per user    : ✅ tabela llm_usage       │
│ LLM rate limit por plan       : ✅ free/pro/enterprise    │
│ Slow query alerts             : ✅ > 1s avg               │
│ Storage lifecycle policies    : ✅                         │
│ CDN cache hit rate            : 94% ✅                     │
│ Per-feature cost              : ✅ tabela + dashboard      │
│ Per-tenant budget (multi)     : ✅ + hard limit em free   │
│ $/usuario ativo (30d)         : R$ 3,47 (meta < R$ 5,00) ✅│
│ Status                        : ✅ MONITORED              │
└───────────────────────────────────────────────────────────┘
```

## Anti-padrões

- ❌ Cloud sem budget alert (descobre no boleto)
- ❌ LLM sem track de tokens (não sabe quanto cada feature custa)
- ❌ Sem rate limit em endpoint que chama LLM (1 user pode queimar $$)
- ❌ S3 sem lifecycle policy (storage cresce eterno)
- ❌ Egress alto sem CDN/cache
- ❌ Métrica de cost só agregada (não consegue atribuir a feature/tenant)
- ❌ Alerta só em 100% (já vazou)
- ❌ Slow query nunca olhada (CPU do DB sempre crescendo)
- ❌ Sem cost por usuário ativo (não sabe unit economics)
