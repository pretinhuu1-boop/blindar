---
name: chaos-engineering
category: resilience
module: 13
priority: P2
description: |
  Resiliência testada de VERDADE. Derruba propositalmente DB, cache,
  network, dependência externa em ambiente controlado e mede se sistema
  se recupera. Ferramentas: Chaos Mesh, Gremlin, Litmus, ou scripts
  manuais. GameDays mensais com runbook. Confirma que breakers,
  retries, fallbacks REALMENTE funcionam — não só existem em teoria.
---

# Agent: chaos-engineering

## Missão

"Temos breaker" no ppt vira "DB caiu, app inteira foi junto" em prod.
Resiliência só existe se foi testada quebrando de verdade. Este agente
prescreve experimentos controlados + GameDays.

## Quando rodar

- Módulo 13 selecionado
- Rigor: `production` ou `compliance`
- Time já fez 6+ meses de produção (não é pra MVP)

## A. Pré-requisitos (NÃO pular)

- Ambiente staging que **espelha** prod (mesmo schema, mesmas integrações)
- Observability completa (logs, métricas, traces) — sem isso, não vê o que quebrou
- On-call rotation definida
- Runbook de incidente real
- Aprovação de tech lead

NÃO rodar chaos em produção sem todos esses checks.

## B. Hipóteses (sempre testar uma)

Cada experimento testa **uma** hipótese:

| Hipótese | Experimento |
|---|---|
| "Sistema continua respondendo se DB primary cair" | Mata primary, mede tempo de failover pra replica |
| "Sistema graceful degrada se Redis cair" | Mata Redis, verifica que app não trava (sem cache, mas funciona) |
| "Retry com backoff cobre falha intermitente da API X" | Injeta 50% de 500 em /external/x, mede taxa de sucesso final |
| "Sob 2x carga, p95 latency < 1s" | k6 gera 2x tráfego, mede p95 |
| "Pod morre, K8s restart sem perder request" | `kubectl delete pod`, mede 0 requests perdidas |

## C. Ferramentas

| Ferramenta | Bom pra |
|---|---|
| **Chaos Mesh** (K8s) | Network delay, pod kill, IO chaos, stress |
| **Gremlin** (managed) | UI, agenda, audit, multi-cloud |
| **Litmus** (CNCF) | Open source, K8s-native |
| **AWS Fault Injection Simulator** | AWS |
| **Scripts manuais** | Projetos pequenos, controle total |

## D. Experimentos comuns (com runbook)

### D.1 DB primary down

```yaml
# Chaos Mesh
apiVersion: chaos-mesh.org/v1alpha1
kind: PodChaos
metadata: { name: db-primary-kill }
spec:
  action: pod-kill
  mode: one
  selector:
    namespaces: [production-clone]
    labelSelectors: { app: postgres, role: primary }
  duration: '30s'
```

Esperado:
- Replica vira primary em < 30s
- App reconecta em < 60s
- Requests durante failover retornam 503 com `Retry-After`
- Sem perda de dados commitados

Falhou se: app fica down > 2min, retorna 500 em vez de 503, perde dados.

### D.2 Network delay 500ms

```yaml
kind: NetworkChaos
spec:
  action: delay
  selector: { labelSelectors: { app: api } }
  delay: { latency: '500ms', jitter: '100ms' }
  target: { selector: { labelSelectors: { app: database } } }
```

Esperado:
- p95 sobe mas sistema responde
- Connection timeout configurado (5s) entra em ação se delay > 5s
- Não cascade failure pra cliente final

### D.3 Dependência externa cai

```ts
// Toxiproxy ou similar — injetar falha em /payments/stripe
toxiproxy.add({
  name: 'stripe-down',
  listen: '0.0.0.0:443',
  upstream: 'api.stripe.com:443',
  enabled: true,
});
await toxiproxy.populate({ stripe: { type: 'timeout', toxicity: 1.0 } });
```

Esperado:
- Circuit breaker abre após 5 falhas
- App não tenta mais por 60s (cool-down)
- Cliente recebe mensagem amigável "Pagamento temporariamente indisponível"
- Job de retry processa quando voltar

### D.4 Pod OOMKill

```yaml
kind: StressChaos
spec:
  stressors:
    memory: { workers: 1, size: '512MB' }
  duration: '2m'
```

Esperado:
- K8s reinicia pod (liveness)
- Graceful shutdown drena requests em vôo
- LB tira pod do pool antes do kill
- 0 request perdida

## E. GameDay (exercício planejado)

Mensal. 2-4 horas. Time inteiro.

```markdown
# GameDay — Junho/2026

## Hipótese
Sistema sobrevive ao DB primary caindo às 14h00 de uma sexta com carga normal.

## Pré-condições
- [ ] Backup recente (< 1h) verificado
- [ ] On-call avisado
- [ ] Status page preparada
- [ ] Customer success briefado (sem cliente afetado real)

## Procedimento (timestamps reais durante o evento)
- T+0:    [scribe registra] Kill DB primary
- T+0:30  Esperado: Replica promovida
- T+1:00  Esperado: App reconecta
- T+3:00  Esperado: p95 latency volta ao normal
- T+5:00  Restaura ambiente, escreve postmortem

## Sucesso = todos os esperados aconteceram
## Falha = abre tickets pra cada gap
```

## F. Auto-rollback (kill switch)

```ts
const chaos = new ChaosClient();
const guard = setInterval(async () => {
  const errorRate = await metrics.getErrorRate({ window: '1m' });
  if (errorRate > 0.5) {
    await chaos.killAll();                   // mata todos os experimentos
    await alert.page('chaos_auto_rollback', { errorRate });
  }
}, 30_000);
```

NÃO rodar experimento sem auto-rollback configurado.

## G. Métricas

- MTTR (mean time to recovery) por classe de falha
- Hipóteses testadas / mês
- % de experimentos com sucesso na 1ª tentativa
- Issues criadas a partir de experiments (sinal de aprendizado)

## H. Greps

```bash
# Breaker sem timeout (falha silenciosa)
rg -n "(circuitBreaker|breaker)\(" --type ts | rg -v "timeout"

# Retry sem cap (loop infinito)
rg -n "retry\(" --type ts | rg -v "(attempts|maxAttempts):"

# Sem fallback em chamada externa
rg -nB 2 "await fetch\(['\"]https?://(?!localhost)" --type ts | rg -v "(catch|fallback)"
```

## Output em sec.html

```
┌─ Chaos Engineering (Módulo 13) ──────────────────────────┐
│ Ferramenta                    : Chaos Mesh (staging)      │
│ GameDays realizados (ano)     : 11                        │
│ Hipóteses testadas (mês)      : 4                         │
│ Auto-rollback configurado     : ✅                        │
│ Observability completa        : ✅                        │
│ MTTR (DB down)                : 47s ✅ (meta < 60s)       │
│ MTTR (cache down)             : 12s ✅                    │
│ MTTR (external API down)      : 0 (degrade gracioso)      │
│ Issues criadas via chaos      : 23 (aprendizado real)     │
│ Status                        : ✅ TESTED RESILIENCE      │
└───────────────────────────────────────────────────────────┘
```

## Anti-padrões

- ❌ Chaos em prod sem aprovação + on-call avisado
- ❌ Sem auto-rollback (experimento foge de controle)
- ❌ Testar hipótese vaga ("ver o que acontece")
- ❌ Sem observability (vê fumaça mas não acha o fogo)
- ❌ GameDay sem postmortem (perde aprendizado)
- ❌ Pular pré-reqs ("staging é só uma máquina")
- ❌ Experimentar em sexta às 17h (péssimo timing)
- ❌ Não documentar resultados (próximo time refaz tudo)
- ❌ Não criar issue pra cada gap encontrado
- ❌ Pular GameDays "porque está corrido" (= dívida silenciosa)
