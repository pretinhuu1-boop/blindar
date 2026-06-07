# Fase 0 — Strategic Scan & Planning

**Duração**: ~3 min
**Nova em**: v0.7.0
**Bloqueia**: Fase 1 (Baseline) só roda após o operador aprovar o plano.

## Objetivo

Antes de blindar qualquer coisa, **olhar o projeto** e responder:

1. **Que tipo de projeto é este?** (auth presente? DB ou JSON?)
2. **Quais anti-patterns flagram?** (segredos em código, JSON-as-DB, etc.)
3. **O que faz sentido o blindar tocar?** (lista numerada pra operador escolher)
4. **Como executar mais rápido?** (hardware atual → plano de paralelismo)

Sem essa fase, blindar pode gastar 10 rounds resolvendo coisas que o operador
nem queria mexer.

## Sub-fases

### 0.1 — Architectural smell test (~1 min)

Agente `strategic-scanner` ([`agents/strategic-scanner.md`](../agents/strategic-scanner.md))
varre o projeto procurando padrões em **14 categorias**:

| # | Categoria | Detecta |
|---|---|---|
| 1 | **Autenticação** | tipo (password/oauth/jwt), MFA, hash de senha |
| 2 | **Autorização** | RBAC, ownership check, decorators |
| 3 | **Storage** | DB real vs JSON-as-DB, migrations, índices |
| 4 | **Secrets** | .env no repo, hardcoded keys, secrets vault |
| 5 | **Frontend** | build, CSP, inline scripts, framework |
| 6 | **API** | docs (OpenAPI), validação, versionamento |
| 7 | **Testes** | suite presente, tipos (unit/int/e2e), coverage |
| 8 | **CI/CD** | presença, secret scanning, pinning de deps |
| 9 | **Logging** | estruturado, PII handling, correlation IDs |
| 10 | **Dependências** | total, age, CVE conhecidas |
| 11 | **Arquitetura** | monolito tamanho, separação de concerns |
| 12 | **Performance** | cache, async, N+1 patterns |
| 13 | **Resiliência** | retries, breakers, timeouts |
| 14 | **Observabilidade** | métricas, traces, health endpoints |

### 0.2 — Generate findings report (~30s)

Saída em `.blindar/scan-report.md` (formato em
[`templates/scan-report.md`](../templates/scan-report.md)).

Cada finding tem:

```
[N] Categoria · Severidade · Esforço
    Encontrado: <descrição do que tem hoje>
    Sugerido:   <o que blindar faria>
    Agente:     <qual agent.md atacaria>
    Estimativa: <X rounds, ~Y min>
```

### 0.3 — Interactive selection (~1 min)

Skill apresenta:

```
═══════════════════════════════════════════════════════════
SCAN COMPLETO — encontrei 18 oportunidades
═══════════════════════════════════════════════════════════

CRITICAS (recomendado aplicar):
  [1]  Senhas em texto plano no DB
  [2]  .env commitado no git history
  [3]  JSON file como banco principal

ALTAS (forte recomendação):
  [4]  Sem rate-limit em /login
  [5]  Sem MFA disponivel
  [6]  CORS aberto (*)
  ...

MEDIAS (recomendado):
  [10] Sem CSP header
  [11] innerHTML sem sanitization
  ...

INFO (otimizações):
  [16] Logs em texto livre
  [17] Sem health endpoints
  [18] Sem audit chain

═══════════════════════════════════════════════════════════
Quais aplicar? Responda:
  • Números separados por vírgula: "1,2,3,7,10"
  • Range: "1-5,10-12"
  • "all" pra tudo
  • "crit" pra só críticas
  • "crit+high" pra críticas e altas
  • "none" pra cancelar e sair

→ _
═══════════════════════════════════════════════════════════
```

⚠ Em modo `dry_run: true` ou `BLINDAR_NON_INTERACTIVE=1`, skill assume
`crit+high` e segue.

### 0.4 — Resource detection & parallelism plan (~30s)

Detecta hardware atual:

| OS | Comando |
|---|---|
| Windows | `(Get-CimInstance Win32_Processor).NumberOfLogicalProcessors` |
| Linux | `nproc` |
| macOS | `sysctl -n hw.logicalcpu` |

Calcula concorrência ótima:

```
max_parallel_agents = min(16, cores - 2)
                       └─ Workflow API cap
```

| Hardware | Parallelism | Tempo estimado (50 rounds) |
|---|---|---|
| 4 cores / 8GB | 2 agentes | ~4-6h |
| 8 cores / 16GB | 6 agentes | ~2-3h |
| 16 cores / 32GB | **14 agentes** | ~1.5-2h |
| 32+ cores | 16 (cap) | ~1.5h |

### 0.5 — Save execution plan (~10s)

`.blindar/plan.json`:

```json
{
  "blindar_version": "0.7.0",
  "generated_at": "2026-06-07T15:00:00Z",
  "selected_findings": [1, 2, 3, 4, 5, 7, 10, 11, 16],
  "skipped_findings": [6, 8, 9, 12, 13, 14, 15, 17, 18],
  "hardware": {
    "cpu_cores": 16,
    "ram_gb": 32,
    "os": "windows"
  },
  "execution": {
    "max_parallel_agents": 14,
    "estimated_rounds": 28,
    "estimated_time_min": 90,
    "parallel_groups": [
      ["business-logic", "access-control", "cryptography"],
      ["frontend", "network-security", "observability"],
      ["supply-chain", "patch-management"]
    ]
  }
}
```

## Estratégia de paralelismo inteligente

### Agentes que PODEM rodar paralelos com segurança

| Grupo | Razão |
|---|---|
| Discovery (inventory + threats + arch) | Read-only, sem conflito |
| Adversarial lenses (security + races + failmodes + regression) | Cada lens vê códigos diferentes |
| Rounds de categorias **independentes** | access-control + observability + crypto não tocam mesmos arquivos |

### Agentes que **NÃO** podem paralelos

| Grupo | Razão |
|---|---|
| Rounds que tocam mesmo arquivo | Conflito de merge |
| Rounds que mudam schema do sec.html | Race no JSON state |
| Rounds que requerem o anterior (ex: crypto → key-rotation) | Dependência |

### Implementação no orquestrador

**Claude Code** (Workflow API):
```javascript
phase('Rounds (round 1-3 paralelos)')
await parallel([
  () => agent('access-control round R001', {...}),
  () => agent('observability round R002', {...}),
  () => agent('crypto round R003', {...}),
])
```

**Outras AIs** (sequencial): paralelismo simulado por turnos rápidos.
Tempo aumenta mas resultado é o mesmo.

## Gate

Operador aprovou o plano → vai pra Fase 1 (Baseline).
Operador respondeu `none` → skill sai com código 0 e mensagem clara.
Operador respondeu inválido → reprompt 1x, depois sai com erro.

## Output

| Arquivo | Conteúdo |
|---|---|
| `.blindar/scan-report.md` | Findings numeradas, legível por humano |
| `.blindar/plan.json` | Plano de execução, parseável pelo orquestrador |
| `.blindar/state.json` | inicializado com `phase: "baseline"` (próxima) |

## Limitações honestas

- **Findings dependem da qualidade do scan** — agente lê código, pode
  perder padrões em projetos enormes (>100k LOC). Mitigação: roda em
  paralelo por subdiretório.
- **Resource detection é estática** — não detecta se outro processo está
  pesado na máquina. Ajuste manual via `.blindar/config.yml` →
  `max_parallel_agents: N`.
- **Time estimation é heurística** — varia muito por CI duration.
  Considere ±50% do estimado.

## Ver também

- [`agents/strategic-scanner.md`](../agents/strategic-scanner.md) — o agente
- [`templates/scan-report.md`](../templates/scan-report.md) — formato do output
- [`schemas/plan.schema.json`](../schemas/plan.schema.json) — schema do plan.json
