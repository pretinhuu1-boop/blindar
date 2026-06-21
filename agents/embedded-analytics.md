---
name: embedded-analytics
category: frontend
module: 10
priority: P2
description: |
  Dashboards de analytics dentro da app pra cliente final (B2B SaaS):
  Metabase/Cube/Apache Superset/embed Looker, RLS por tenant em queries
  BI, cache de dashboards, drill-down, white-label, download CSV/Excel.
  Sem isso, cliente B2B abandona porque precisa "exportar pra Excel
  pra entender o próprio negócio".
---

# Agent: embedded-analytics

## Missão

Cliente B2B exige relatórios sobre o próprio uso. Sem dashboards
embarcados, eles montam Excel paralelo = abandono. Este agente prescreve
a stack de BI embarcado correta + isolamento multi-tenant.

## Quando rodar

- Módulo 10 selecionado
- Projeto SaaS B2B com cliente que precisa relatório
- Operador pediu "dashboard pra cliente", "BI embarcado"

## A. Stack

| Ferramenta | Quando |
|---|---|
| **Metabase** (open source) | Default. Embed via signed JWT. Fácil. |
| **Cube** (semantic layer + API) | Headless. Você desenha UI. Mais controle |
| **Apache Superset** | Open source, mais features |
| **Looker** (embedded) | Enterprise, caro |
| **Hex / Sigma / Mode** | Notebooks-as-dashboard |
| **Próprio com Recharts/Tremor** | Controle total mas dev pesado |

## B. Multi-tenant isolation (CRÍTICO)

O bug mais comum: query do cliente A vê dado do cliente B. Soluções:

### B.1 Signed JWT com claim

```ts
// Backend assina JWT com tenant_id
const token = jwt.sign({
  resource: { dashboard: 5 },
  params: { tenant_id: req.user.tenantId },   // FORÇA filtro
  exp: Math.floor(Date.now() / 1000) + 600,
}, METABASE_SECRET);

return res.redirect(`https://bi.example.com/embed/dashboard/${token}#bordered=true&titled=false`);
```

Metabase recusa render se `tenant_id` não bater com row-level access.

### B.2 RLS no DB (defesa em profundidade)

```sql
-- Habilitar em TODAS tabelas analytics-source
ALTER TABLE appointments ENABLE ROW LEVEL SECURITY;
CREATE POLICY analytics_tenant ON appointments
  USING (tenant_id = current_setting('analytics.tenant_id')::uuid);
```

Conexão do BI tem role read-only com RLS forçada. Bug no JWT não vira leak.

## C. Cache de dashboard

```yaml
# Metabase
question:
  cache_ttl: 60   # segundos. Dashboard re-render cacheado.
```

Sem cache, cada user abrindo dashboard = nova query pesada.

## D. Semantic layer (Cube.js exemplo)

Define métricas em código, reusa em N dashboards:

```js
cube('Appointments', {
  sql: `SELECT * FROM appointments WHERE tenant_id = '${SECURITY_CONTEXT.tenantId}'`,
  measures: {
    count: { sql: 'id', type: 'count' },
    revenue: { sql: 'price_cents', type: 'sum' }
  },
  dimensions: {
    status:      { sql: 'status', type: 'string' },
    createdAt:   { sql: 'created_at', type: 'time' }
  }
});
```

UI consome via API. Mudança numa métrica propaga em todos os dashboards.

## E. Download CSV/Excel

Cliente sempre vai querer exportar. Implementar:

```ts
@Get('analytics/:reportId/export')
async export(@Param('reportId') id, @Query('format') format, @Req() req) {
  const data = await runReport(id, req.user.tenantId);
  if (format === 'csv') return toCsv(data);
  if (format === 'xlsx') return toExcel(data);
  if (format === 'pdf') return toPdf(data);
}
```

Limite de linhas (10k) pra evitar OOM. Pra exports maiores: async + email.

## F. Drill-down

Click em "Vendas: Junho R$ 50k" → vê lista detalhada das transações.

Cube/Metabase: configurar `drillthrough` em cada widget.

## G. White-label (B2B SaaS)

Cliente vê dashboard com a marca DELE, não a sua:

```ts
// Override theme via URL params ou JWT claim
{
  appearance: {
    color_brand: tenant.brand_color,
    color_text: tenant.text_color,
    title_text: tenant.brand_name,
  }
}
```

Logo, cores, fontes — tudo do tenant.

## H. Refresh automático

Dashboard live (refresh a cada N segundos) pra operação. Configurável.

## I. Permissões dentro do dashboard

- ADMIN do tenant: vê tudo
- GERENCIAL: vê só agregados do salão
- OPERACIONAL: vê só os próprios números

JWT claim com role → Metabase aplica filtro adicional.

## J. Audit log de queries pesadas

```sql
CREATE TABLE analytics_queries_log (
  id          UUID PRIMARY KEY,
  tenant_id   UUID NOT NULL,
  user_id     UUID NOT NULL,
  query_hash  TEXT NOT NULL,
  duration_ms INTEGER NOT NULL,
  rows_returned INTEGER,
  at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

Alertar queries > 5s. Otimizar ou pre-aggregate.

## K. Greps

```bash
# Dashboard sem tenant_id no JWT
rg -n "embed/dashboard" --type ts -B 5 | rg -v "tenant_id"

# Query analytics sem RLS check
rg -n "(metabase|cube|superset).*query" --type ts | rg -v "tenant"

# Export sem limite de linhas
rg -n "toCsv|toExcel|toPdf" --type ts -A 3 | rg -v "limit|take"
```

## Output em sec.html

```
┌─ Embedded Analytics (Módulo 10) ─────────────────────────┐
│ Plataforma                    : Metabase + Cube semantic  │
│ Embed via signed JWT          : ✅                         │
│ Tenant isolation (RLS + JWT)  : ✅ defesa em profundidade │
│ Cache de dashboards           : ✅ 60s TTL                │
│ Semantic layer                : ✅ 12 cubes               │
│ Drill-down                    : ✅                         │
│ Export CSV/XLSX/PDF           : ✅                         │
│ White-label (brand do tenant) : ✅                         │
│ Refresh automático            : ✅ 30s configurável       │
│ Permissões por role           : ✅                         │
│ Queries auditadas             : ✅                         │
│ Slow query alerts             : ✅ > 5s                   │
│ Status                        : ✅ DATA-VISIBLE          │
└───────────────────────────────────────────────────────────┘
```

## Anti-padrões

- ❌ Embed sem JWT (qualquer um vê dashboard alheio)
- ❌ Confiar só no JWT (sem RLS no DB)
- ❌ Query analytics na role de write (deveria ser read-only)
- ❌ Sem cache (cada open re-roda query pesada)
- ❌ Sem semantic layer (lógica de métrica copy-paste em N lugares)
- ❌ Export sem limite (gera CSV de 1M linhas → OOM)
- ❌ White-label que vaza marca da SUA empresa em algum canto
- ❌ Dashboard slow sem alerta (cliente reclama primeiro)
- ❌ Sem drill-down (cliente exporta CSV pra investigar)
- ❌ Refresh muito agressivo (custo de query alto)
- ❌ Sem audit (não consegue investigar "quem rodou query X?")
