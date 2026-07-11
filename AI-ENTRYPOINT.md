# AI-ENTRYPOINT — leia primeiro

> Você é uma AI que vai operar o skill `blindar` num projeto. Esta página
> te diz exatamente o que fazer agora, com decision tree determinístico.
>
> Se você é humano: este arquivo NÃO é pra você. Leia [`USAGE.md`](USAGE.md).

---

## Passo -1 — Orquestrador determinístico SEMPRE primeiro (v0.46+)

Antes de qualquer coisa deste decision tree, execute a sequência mandatória de
`SKILL.md` § "EXECUÇÃO MANDATÓRIA": `blindar-run.sh --parallel auto` →
validar frescor do `run-report.json` (`ran_at`) → **executar os agentes
deferred** (playbook-only) → apresentar resumo. O pipeline abaixo
(Fases 00–7, rounds/PRs/sec.html) é o engajamento COMPLETO de hardening — ele
consome o run-report como entrada, nunca o substitui. Se o usuário só disse
"blindar", a sequência mandatória É a entrega; o pipeline completo é opt-in.

## Ordem security-first (não-negociável, v0.45+)

Segurança não é uma fase — é gate em CADA passo. A sequência é:

1. **Analisar** — grafo de conhecimento (`graph-build.js`) + discovery. Entender
   superfície externa × interna antes de qualquer coisa.
2. **Implementar o que falta** — o que o projeto não tem, blindar cria
   (com segurança embutida, nunca mock em produção).
3. **Provar que sobe (smoke)** — `smoke-run.sh` em homolog. Boot + health +
   fluxo. Não adianta atacar o que não sobe.
4. **Atacar** — pentest + adversarial (módulo 15) + recon (17).
5. **Proteger** — corrigir o que o ataque achou.
6. **Revisar** — adversarial review final, production checklist.

Nunca pule o smoke antes do ataque. Nunca marque "verde" sem o app de pé.

## Algoritmo de execução (siga em ordem)

### Passo 0 — Identifique o MODO de execução (v0.6.0+)

Leia `.blindar/config.yml` se existir. Detecte:

| Flag | Modo | Comportamento |
|---|---|---|
| `dry_run: true` | **DRY-RUN** | Simula. Cria branches mas NÃO mergeia. Reporta o que faria. |
| `minimal_mode: true` | **MINIMAL** | Projeto pequeno. Pula discovery extensiva, usa template ATKs por stack. |
| `maintenance_mode: true` | **MAINTENANCE** | Pipeline reduzido: Fase 1 → 8 → 9 (baseline + maintenance + drift). Sem rounds extensivos. |
| (nenhuma) | **FULL** | Pipeline completo Fases 00 + 0-7. |

Em MULTI-target (`target_framework: [iso27001, soc2]`), gera coverage
report pra cada um na Fase 6.

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
          2. Comece pelo Passo 3.5 (Fase 00 — Launcher)
```

### Passo 3.5 — Launcher (Fase 00, v0.8+)

```
.blindar/config.yml existe E tem mode + selected_modules?
  ├─ SIM → pule launcher, vá pro Passo 4 (Fase 0 strategic-scan)
  │
  └─ NÃO → rode pipeline/00-launcher.md:
          1. 4 perguntas objetivas ao operador (≤30s):
             - tipo de projeto, sensibilidade, modo, rigor
          2. Mostra menu de 15 módulos com defaults inteligentes
          3. Aceita "tudo" / "defaults" / "1,3,5,7,10" / "1-8" / "tudo menos 13,14"
          4. Confirmação final (default-yes em modo AUTO, timeout 10s)
          5. Grava .blindar/config.yml com:
             - mode (auto|supervised|chosen)
             - selected_modules [1..15]
             - project_type, data_sensitivity, rigor
             - ui_detected, db_detected (preenche em Fase 02)
          6. Atualiza .blindar/state.json: phase="00-launcher-done"
```

Modos especiais:
- `--resume` → pula launcher se config.yml existir
- `--headless` → pula launcher, usa defaults (modo auto, rigor produção)
- `--reset` → apaga .blindar/ e roda launcher do zero
- `--dry-run` → roda launcher mas grava dry_run:true

### Passo 4 — Pipeline (Fases 00 → 7)

Cada fase tem arquivo em `pipeline/`. Execute em ordem. **Antes de spawnar
qualquer agente em Fases 04 e 06, consulte `pipeline/MODULE-MAP.json` e
filtre por `.blindar/config.yml > selected_modules`.**

| Fase | Arquivo | Sua tarefa |
|---|---|---|
| 00 ⭐ v0.8 | `pipeline/00-launcher.md` | 4 perguntas + menu, grava config |
| 0 ⭐ | `pipeline/00-strategic-scan.md` | Varre projeto, lista oportunidades, planeja paralelismo. Read-only. |
| 1 | `pipeline/01-baseline.md` | Validar projeto. **Para** se suite vermelha. |
| 2 | `pipeline/02-discovery.md` | 3 agents paralelos. Detecta `ui_detected`, `db_detected`. Atualiza config.yml. |
| 3 | `pipeline/03-bootstrap-sec-html.md` | Criar `sec.html` na raiz do projeto-alvo, PR único. |
| 4 | `pipeline/04-rounds-loop.md` | Loop principal. Filtra agentes por MODULE-MAP ∩ selected_modules. |
| 5 | `pipeline/05-adversarial-review.md` | A cada 10 rounds, 4 lentes + verify. |
| 6 | `pipeline/06-production-checklist.md` | Após adversarial limpa, gates finais (filtrados por módulo). |
| 7 | `pipeline/07-final-report.md` | PR final com sumário. |

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
  - production_checklist_passed: true (Fase 6)

  SIM → vá pra Fase 6 (production checklist) → Fase 7 (relatório final) → done
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
| `pipeline/MODULE-MAP.json` | Antes de spawnar agentes (filtragem por selected_modules) |
| `docs/trends-2026.md` | Curadoria semestral — consultar em agentes relevantes |
| `templates/sec.html` | Bootstrap (Fase 3) |
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
