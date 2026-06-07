# AI-ENTRYPOINT — leia primeiro

> Você é uma AI que vai operar o skill `blindar` num projeto. Esta página
> te diz exatamente o que fazer agora, com decision tree determinístico.
>
> Se você é humano: este arquivo NÃO é pra você. Leia [`USAGE.md`](USAGE.md).

---

## Algoritmo de execução (siga em ordem)

### Passo 1 — Identifique seu modo de operação

```
Você tem acesso a Workflow API (paralelo nativo, ex: Claude Code)?
  ├─ SIM → modo NATIVO. Vá pro Passo 2.
  └─ NÃO → modo MANUAL. Leia MULTI-AI.md primeiro, depois volte aqui.
```

### Passo 2 — Pre-flight do projeto-alvo

Execute (ou peça pro humano executar):

```powershell
# Windows
.\scripts\preflight.ps1
```

Se algum check falhar, **PARE**. Reporte ao humano o que faltou e
aguarde resolução. Não tente blindar projeto que falha preflight — é
contra os princípios do skill.

### Passo 3 — Verifique estado existente

```
.blindar/state.json existe no projeto-alvo?
  ├─ SIM → modo RESUMING.
  │       1. Leia .blindar/state.json (valide contra schemas/state.schema.json)
  │       2. Identifique campo "phase"
  │       3. Continue do início dessa fase (ou do current_round se houver)
  │
  └─ NÃO → modo FRESH START.
          1. Crie .blindar/ no projeto-alvo
          2. Se .blindar/config.yml existir, leia overrides
          3. Comece pelo Passo 4 (Fase 0 — Baseline)
```

### Passo 4 — Pipeline (Fases 0 → 6)

Cada fase tem arquivo em `pipeline/`. Execute em ordem:

| Fase | Arquivo | Sua tarefa |
|---|---|---|
| 0 | `pipeline/00-baseline.md` | Validar projeto. **Para** se suite vermelha. |
| 1 | `pipeline/01-discovery.md` | 3 agents paralelos. **Use schemas/** pra validar saída. |
| 2 | `pipeline/02-bootstrap-sec-html.md` | Criar `sec.html` na raiz do projeto-alvo, PR único. |
| 3 | `pipeline/03-rounds-loop.md` | Loop principal. Cada round = 1 PR mergeado. |
| 4 | `pipeline/04-adversarial-review.md` | A cada 10 rounds, 4 lentes + verify. |
| 5 | `pipeline/05-production-checklist.md` | Após adversarial limpa, gates finais. |
| 6 | `pipeline/06-final-report.md` | PR final com sumário. |

### Passo 5 — Após CADA round (Fase 3)

```
1. Atualize .blindar/state.json:
   - last_updated = agora
   - rounds_completed += 1
   - rounds_since_last_adversarial += 1
   - current_round = null
2. Atualize sec.html no projeto-alvo (arrays JS no topo)
3. Verifique termination:
   - rounds_since_last_adversarial >= adversarial_cadence?
     SIM → vá pra Fase 4
     NÃO → vá pro próximo round
```

### Passo 6 — Termination check (após CADA adversarial)

Use o critério em `schemas/state.schema.json` (objeto `termination_check`):

```yaml
TODAS verdadeiras?
  - zero_crit_confirmed: true
  - high_count_acknowledged: <= 2
  - critical_categories_coverage_pct: >= 80
  - runbooks_generated: contém incident-response.md, key-rotation.md, supply-chain.md
  - ci_green_streak: >= 3
  - production_checklist_passed: true (Fase 5)

  SIM → vá pra Fase 6 (relatório final) → done
  NÃO → continue rounds
```

### Passo 7 — Done

```
1. Marque phase = "done" em .blindar/state.json
2. PR final mergeado com sumário (Fase 6)
3. Notifique o humano no terminal
4. Pare. Não inicie novo ciclo automaticamente.
```

---

## Regras invioláveis

1. **NUNCA** modifique sem teste real (≥3 asserts).
2. **NUNCA** mergeie com CI vermelha ou `--no-verify`.
3. **NUNCA** quebra defesa existente sem registrar em `.accept-risk.md`.
4. **NUNCA** invente conteúdo de scalability/frontend-performance sem
   evidência observada — princípio "pago em PR vermelho mergeado".
5. **Security-first** — em empate de severidade, agent de segurança vence.
6. **Schema da `sec.html` é commitado UMA vez.** Não muda entre rounds.

## Recursos

| Arquivo | Quando ler |
|---|---|
| `SKILL.md` | Princípios e defaults — ler 1x no começo |
| `pipeline/*.md` | Cada fase, no momento |
| `agents/<categoria>.md` | Quando spawn agent dessa categoria |
| `schemas/*.json` | Antes de qualquer output JSON |
| `frameworks/<alvo>.md` | Se config.target_framework definido |
| `templates/sec.html` | Bootstrap (Fase 2) |
| `templates/pr-message.md` | Cada PR de round |
| `stacks.md` | Categorias extras conforme stack detectada |
| `CONTRACT.md` | Estrutura completa de `.blindar/` no projeto-alvo |
| `MULTI-AI.md` | Se você NÃO é Claude Code com Workflow API |

## Decisão: confiança em finding adversarial

```
verdict.confidence == "low"?
  → trate como refuted (princípio: refute is the safe default)
verdict.isReal == true E confidence >= "medium"?
  → enfileire como novo round
```

## Decisão: pick do próximo gap (Fase 3)

```
Ordem:
1. Severity DESC (crit > high > med > low)
2. Em empate de sev: categoria de segurança vence (security-first)
3. Em empate de sev+categoria: coverage ratio ASC da categoria
   (categoria mais descoberta primeiro)
4. Em empate completo: ATK_ID lexicográfico
```

## Decisão: stop pra reportar (vs continuar)

```
Encontrou condição que o humano precisa decidir?
  Ex: framework conflitante, escopo expandiu inesperadamente,
      dep depreciada sem substituto óbvio
  → marque current_round.blocked_reason em state.json
  → notifique humano no terminal
  → AGUARDE (não tente "resolver criativamente")

Encontrou bug bloqueante no skill?
  → reporte como issue no repo do skill
  → pause até resposta
```

---

**Fim.** Comece pelo Passo 1. Toda decisão tem regra determinística aqui;
nenhuma decisão "criativa" é necessária pra completar o ciclo.
