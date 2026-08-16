## Garantias obrigatórias do padrão (não-negociáveis)

1. **Entrypoint único**: `SKILL.md` MANDA primeira ação = `bash scripts/<NOME>-run.sh`
2. **Cobertura mensurável**: orquestrador gera `.<NOME>/run-report.json` com `coverage_pct`
3. **Skipped silent é impossível** — vira `deferred` explícito no relatório
4. **Exit codes claros**: 0=PASS, 1=CONDITIONAL, 2=FAIL, 3=STRICT-FAIL, 4=ERRORED
5. **Fallback gracioso**: rg ausente → grep -rE; jq ausente → Node; API key ausente → skipped (não fail)
6. **Layout auto-detect**: orquestrador detecta skill canonical, instalado no projeto, ou via HOME
7. **Zero deps no CLI**: parseArgs nativo Node + ANSI puro (sem mri, kleur, chalk, commander)
8. **Schema versionado E validado runtime**: todo JSON output tem `"schema": "<NS>/X@v1"` + `validate-schemas.js` confere
9. **`set -uo pipefail` SEM `-e`** no `_lib.sh` — pipefail mata `rg | sort`. Cada check controla errexit local.
10. **NÃO usar `trap ERR`** — só dispara com errexit, que está desligado. Código morto.
11. **Paralelização via xargs -P** com agregação via log file (sem race em vars bash)
12. **`--since REF`** exporta `BLINDAR_CHANGED_FILES` env pros checks consumirem (PR-time)
13. **`--verbose`** preserva stdout dos checks prefixado com `[agent]` (debug)
14. **`blindar-fix` SEMPRE dry-run** por default. `--apply` é explícito. Branch separada obrigatória.
15. **SARIF output** disponível via `scripts/sarif-converter.js` pra integração GitHub Code Scanning
16. **Bash 3.2 compat** (macOS default) — auditar features bash 4+ via `docs/BASH-COMPAT.md`
17. **Wave-guardian** (opcional): gate determinístico no final de cada onda valida run-report.json
18. **Proactive-analysis** (auto se API key): rodar ao final cobrindo 8 dimensões consultivas
19. **Mandato imperativo no SKILL.md**: "você DEVE / você NÃO pode" — não deixa Claude pular
20. **`--security-only` mode**: sempre disponível pra foco puro em segurança
21. **`--fast` inclui supply-chain** (módulo 5) por default — supply chain é vetor crítico

---

## Bugs conhecidos a EVITAR (lições caras já validadas)

- ❌ `rg --type tsx/jsx` não existe (ts já cobre `.tsx`) — silent skip
- ❌ `rg` pode ser função do shell, não binário — use `type -P rg` pra detectar
- ❌ `command -v rg` em sub-shell falha se rg é função; use fallback grep
- ❌ `grep -c` retorna múltiplas linhas em multi-file → `[: 0 0 -gt 0 ]` quebra
- ❌ `set -e` + `rg | sort` (rg sem match = exit 1) → trap ERR dispara false-positive
- ❌ `trap ERR` sem `set -e` é código morto — REMOVA, não cole
- ❌ `${result_file/check-/}` remove "check-" do path inteiro, não só basename
- ❌ Node path POSIX (`/c/...`) quebra no Windows — use `cygpath -w` ou passe via argv
- ❌ `mri`/`kleur`/`chalk` precisam install — **zero deps obrigatório no CLI**
- ❌ `.git` ausente trava CLI — use `git rev-parse --is-inside-work-tree` + warn
- ❌ TODO regex sem `\b` bate em "TODOS" (PT-BR comum em README)
- ❌ `.<NOME>/` e `.git` fora de IGNORE_GLOBS → self-detection reentrante
- ❌ Variável env unbound com `set -u` → sempre `${VAR:-}`
- ❌ `declare -a NAME=()` funciona em bash 3.2, mas `mapfile`/`declare -A` não — auditar
- ❌ Resultado descartado com `>/dev/null 2>&1` torna debug impossível — `--verbose` deve preservar
- ❌ Parsing JSON via grep frágil — use jq OU Node (fallback)
- ❌ `node -e` 4× por finding = 4N processos — chame node **1x por result_json**
- ❌ Truncate em 50k chars sem cuidado pode cortar JSON no meio → API erro silencioso
- ❌ `__mocks__/`, `node_modules/`, `dist/`, `coverage/` devem estar em IGNORE_GLOBS default
- ❌ Paralelização em vars bash compartilhadas (declare -a no caller) tem race — use log file
- ❌ `xargs -P` com `bash -c '...'` precisa exportar funções (`export -f`)
- ❌ Wrappers de scanner SEM timeout travam CI eternamente — sempre `timeout 120s`
- ❌ Schema versionado sem validador é só decoração — `validate-schemas.js` é obrigatório
- ❌ `blindar-fix` sem `git apply --check` aplica patches inválidos
- ❌ `blindar-fix` em main/master = catástrofe — bloquear lista de branches protegidas
- ❌ `gtimeout` no macOS é instalado via `brew install coreutils`; sem ele, comando `timeout` não existe — testar

---

## Comando único pra rodar (canonical)

```bash
# Hardening completo (com proactive-analysis auto no fim se API key)
bash ~/.claude/skills/<NOME>/scripts/<NOME>-run.sh [--fast] [--strict]

# Foco SEGURANÇA (módulos 2 + 5 + 15)
bash ~/.claude/skills/<NOME>/scripts/<NOME>-run.sh --security-only --parallel auto

# PR-time (só arquivos mudados)
bash ~/.claude/skills/<NOME>/scripts/<NOME>-run.sh --since HEAD~1 --parallel auto

# Debug humanizado
bash ~/.claude/skills/<NOME>/scripts/<NOME>-run.sh --verbose

# Hardening + evolução de produto
bash ~/.claude/skills/<NOME>/scripts/<NOME>-run.sh --with-evolution

# Sem proactive (CI puro sem token cost)
bash ~/.claude/skills/<NOME>/scripts/<NOME>-run.sh --no-proactive

# Output SARIF pra GitHub Code Scanning
bash ~/.claude/skills/<NOME>/scripts/<NOME>-run.sh --json
node ~/.claude/skills/<NOME>/scripts/sarif-converter.js --input .<NOME>/results > sarif.json

# Auto-fix de findings via LLM
bash ~/.claude/skills/<NOME>/scripts/<NOME>-fix.sh --auto-all --dry-run
```

Ou via Claude Code:
```
<NOME>
```

---

## Tabela "Escopos por contexto" (recomendar no README)

| Contexto | Comando | Tempo | Custo token |
|---|---|---|---|
| **Daily commit/PR** | `<NOME>-run.sh --fast --since HEAD~1 --no-proactive` | <30s | 0 |
| **PR completo** | `<NOME>-run.sh --since main --parallel auto` | 1-2min | 0 |
| **Pre-deploy** | `<NOME>-run.sh --strict --parallel auto` | 2-5min | $ (proactive) |
| **Foco segurança** | `<NOME>-run.sh --security-only --parallel auto` | 1-3min | $ (proactive) |
| **Fim de sprint** | `<NOME>-run.sh --with-evolution` | 5-8min | $$ |
| **Sprint planning** | `<NOME>-evolve.sh` | 3-5min | $$ |
| **CI gate** | `<NOME>-run.sh --strict --json --parallel auto --no-proactive` | 1-2min | 0 |
| **Auto-fix** | `<NOME>-fix.sh --auto-all --dry-run` | 2-5min | $$ |
| **Debug check** | `<NOME>-run.sh --module N --verbose --no-proactive` | <30s | 0 |

---

## Workflow de evolução da skill

1. **Adicionar agente novo** → cria `agents/<a>.md` (playbook)
2. **Materializar** → escolha 1:
   - `templates/checks/check-<a>.sh` (determinístico — regex/grep)
   - `templates/checks/check-<a>.api.sh` (wrapper Claude API)
   - `templates/checks/check-<a>.sh` que wraps scanner externo (Semgrep/OSV/etc)
3. **Registrar** em `pipeline/MODULE-MAP.json` no módulo certo
4. **Smoke test**: `bash scripts/<NOME>-run.sh --module <N> --verbose`
5. **Bump VERSION** + entry no CHANGELOG.md
6. **Commit** local + tag (push só se publicado)
7. **Adicionar fixture** em `tests/fixtures/` se for check determinístico (regression test)

**Pra evoluir mais rápido**: use multi-agente paralelo via Agent tool. Cada agente cuida de 1-3 arquivos diferentes (sem conflito). Wall-clock cai pela metade.

---

## Cobertura de testes (`tests/`)

```bash
# tests/run-tests.sh
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"

# Cada caso: "fixture | check | expected_status"
TEST_CASES=(
  "clean-project | check-<agente1>.sh | passed"
  "bad-project   | check-<agente1>.sh | failed"
)

PASS=0; FAIL=0
for tc in "${TEST_CASES[@]}"; do
  IFS='|' read -r fixture check expected <<< "$tc"
  fixture=$(echo "$fixture" | xargs); check=$(echo "$check" | xargs); expected=$(echo "$expected" | xargs)

  fixture_dir="$SCRIPT_DIR/fixtures/$fixture"
  check_script="$SKILL_DIR/templates/checks/$check"

  [ ! -d "$fixture_dir" ] && { echo "SKIP: $fixture"; continue; }
  [ ! -f "$check_script" ] && { echo "SKIP: $check"; continue; }

  (cd "$fixture_dir" && bash "$check_script" >/dev/null 2>&1)
  rc=$?
  actual=$([ $rc -eq 0 ] && echo "passed" || echo "failed")
  if [ "$actual" = "$expected" ]; then
    echo "✓ $fixture / $check"; PASS=$((PASS+1))
  else
    echo "✗ $fixture / $check (expected=$expected, got=$actual)"; FAIL=$((FAIL+1))
  fi
done

echo ""
echo "Passed: $PASS / Failed: $FAIL"
[ "$FAIL" -eq 0 ]
```

Cada fixture é um projeto mini real (com/sem o problema que o agente detecta).

---

## Proactive-analysis (OBRIGATÓRIO — análise consultiva ao final)

Diferente de checks tradicionais que buscam findings, este agente **opina nas 8 dimensões** de produção real ao final do orquestrador. Roda automático se `ANTHROPIC_API_KEY` existe.

**Arquivos**:
- `agents/proactive-analysis.md` (playbook)
- `templates/checks/check-proactive-analysis.api.sh` (wrapper API)
- Integração no fim de `scripts/<NOME>-run.sh`

**8 dimensões obrigatórias**:

| # | Dimensão | Perguntas chave |
|---|---|---|
| 1 | **Segurança** | Ataques possíveis? Dados sensíveis expostos? RBAC falho? Audit log? |
| 2 | **Arquitetura** | Bounded contexts faltando? Acoplamentos perigosos? Módulos sugeridos? |
| 3 | **Qualidade/Testes** | Cobertura? Tipos faltantes (unit/e2e/load/chaos)? Quality gates? |
| 4 | **Performance** | Bottlenecks reais detectáveis no código? Métricas p95/p99 sugeridas? |
| 5 | **Compliance** | LGPD/GDPR/HIPAA/PCI gaps específicos da stack? |
| 6 | **Acessibilidade** | WCAG AA? Cognitive load? Keyboard nav? i18n? |
| 7 | **Custos/FinOps** | Cloud spend? Token spend LLM? Per-feature cost? |
| 8 | **DX/Operação** | Onboarding dev novo? Runbooks? Automações possíveis? |

**Cada dimensão entrega**:
- **Riscos** (severity crit/high/med/low + mitigation)
- **Oportunidades** (ROI alto/médio/baixo + trade-offs + complexity S/M/L)
- **Quem decide** (CTO/PO/Eng/Compliance/Legal)

**Schema custom forçado via tool_use** (não o schema padrão de findings):

```json
{
  "type": "object",
  "required": ["dimensions"],
  "properties": {
    "dimensions": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["name", "risks", "opportunities"],
        "properties": {
          "name": {"enum": ["security","architecture","quality","performance","compliance","accessibility","costs","dx_ops"]},
          "risks": {"type": "array", "items": {
            "type": "object",
            "properties": {
              "severity": {"enum":["crit","high","med","low"]},
              "description": {"type":"string"},
              "mitigation": {"type":"string"}
            }
          }},
          "opportunities": {"type": "array", "items": {
            "type": "object",
            "properties": {
              "roi": {"enum":["alto","medio","baixo"]},
              "description": {"type":"string"},
              "tradeoffs": {"type":"string"},
              "complexity": {"enum":["S","M","L"]},
              "decider": {"enum":["CTO","PO","Eng","Compliance","Legal"]}
            }
          }}
        }
      }
    }
  }
}
```

**Outputs (2 arquivos)**:
- `.<NOME>/results/check-proactive-analysis.json` — padrão pra agregação no run-report
- `.<NOME>/proactive-analysis.md` — relatório markdown legível com tabelas por dimensão (este é o que Claude lê no passo 4 do mandato)

**Mapeamento de findings**: cada risco crit/high vira `add_finding` no run-report (visibility). Oportunidades NÃO viram findings — só vão pro `.md`.

**Flags pra desligar**:
- `--no-proactive` no orquestrador
- Env `BLINDAR_SKIP_PROACTIVE=1`

**Bloco de integração no `<NOME>-run.sh`** (ao final, antes do exit):

```bash
# ─── Análise proativa (auto se ANTHROPIC_API_KEY) ───
if [ -n "${ANTHROPIC_API_KEY:-}" ] && [ "${SKIP_PROACTIVE:-0}" -eq 0 ] && [ -f "$CHECKS_DIR/check-proactive-analysis.api.sh" ]; then
  log ""
  log_section "Análise proativa (8 dimensões)"
  bash "$CHECKS_DIR/check-proactive-analysis.api.sh" 2>&1 | tail -5
  if [ -f "${BLINDAR_DIR:-$PROJECT_DIR/.<NOME>}/proactive-analysis.md" ]; then
    log "Relatório consultivo: ${BLINDAR_DIR:-$PROJECT_DIR/.<NOME>}/proactive-analysis.md"
  fi
fi
```

**Por que separar do schema padrão de findings**: opportunities/trade-offs/decider não cabem no formato `{severity, message, file, line}`. Schema custom mantém estrutura útil.

---

## Modes de filtro (orquestrador)

Hoje o `<NOME>-run.sh` aceita 4 modes de filtro:

| Mode | Módulos | Quando usar |
|---|---|---|
| `--fast` | `1,2,5,11,12,15` | Daily commit/PR — críticos + segurança + supply-chain |
| `--security-only` | `2,5,15` | Foco exclusivo em segurança |
| `--module N,N` | livre | Investigação pontual |
| (default) | `all` | Pre-release completo |

**Mutex** `--security-only` com `--module` (exit 64 se ambos).

Pra security-first verdadeiro, **inclua módulo 5 (supply-chain) no `--fast`** — supply chain é vetor de ataque crítico em 2026.

---

## Wave-guardian (opcional — gate determinístico de onda)

Pra skills com rounds-loop ou ondas iterativas. Cria `agents/wave-guardian.md` + `templates/checks/check-wave-guardian.sh` que:

1. Lê `.<NOME>/run-report.json` da última execução
2. Valida:
   - `errored > 0` → BLOCK
   - `failed` com severity crit → BLOCK
   - `deferred > 0` sem playbook executado → BLOCK
   - `coverage_pct < min_coverage_pct` → WARN
3. Gera `.<NOME>/wave-<N>-guardian.md` com decisão estruturada
4. Impede onda fechar com gap invisível

Invocação:
```bash
WAVE_NUMBER=2 \
WAVE_AGENTS="agent1,agent2,agent3" \
MIN_COVERAGE_PCT=90 \
bash templates/checks/check-wave-guardian.sh
```

---

## Módulo 16 — Product Evolution (opt-in, escopo separado)

Se a skill tem propósito de auditoria de produto (não só hardening), crie um módulo separado com:

- 5 agentes-tipo: `api-frontend-coverage`, `user-journey-simulator`, `feature-gap-analyzer`, `growth-opportunities`, `product-critic`
- Todos `.api.sh` (precisam de LLM)
- Orquestrador dedicado: `scripts/<NOME>-evolve.sh`
- Output: `.<NOME>/evolution-report.md` consolidado (markdown legível)
- REQUER `ANTHROPIC_API_KEY`

NÃO entra no `--fast` nem no fluxo padrão. É invocado via `--with-evolution` ou diretamente.

Razão: hardening (core) = determinístico, exit code, CI gate. Evolution = subjetivo, exploração estratégica. Misturar dilui "exit 0 = release".

---

## Pronto para executar

Depois das 5 perguntas iniciais respondidas, execute esta sequência sem pedir confirmação a cada passo:

1. Cria toda a estrutura de pastas
2. `SKILL.md` com frontmatter + seção ENTRYPOINT + nota sobre `<NOME>-evolve.sh`
3. `VERSION` = `0.1.0`
4. `CHANGELOG.md` com `## [0.1.0]` inicial
5. `README.md` + `GETTING-STARTED.md` com tabela "Escopos por contexto"
6. `pipeline/MODULE-MAP.json` com módulos iniciais
7. `pipeline/00-launcher.md` com **5 perguntas** + menu
8. `schemas/check-result.schema.json` + `schemas/run-report.schema.json`
9. `templates/checks/_lib.sh` (esqueleto completo + rg fallback + bash version warn)
10. `templates/checks/_api_wrapper.sh` (parsing 1x via Node)
11. `scripts/<NOME>-run.sh` (orquestrador completo — auto-detect, paralelização, --since, --verbose, --with-evolution)
12. `scripts/sarif-converter.js` (zero deps)
13. `scripts/validate-schemas.js` (zero deps, AJV opcional)
14. Se aplicável: `scripts/<NOME>-evolve.sh` + 5 agentes evolution `.api.sh`
15. Agentes iniciais: `.md` em `agents/` + `.sh` ou `.api.sh` em `templates/checks/`
16. Se cabível: wrappers de scanners externos (Semgrep/OSV/Trivy/Gitleaks) seguindo template
17. **OBRIGATÓRIO**: `agents/proactive-analysis.md` + `templates/checks/check-proactive-analysis.api.sh` (8 dimensões consultivas)
18. **OBRIGATÓRIO**: integrar bloco de chamada do proactive ao FINAL do `<NOME>-run.sh`
19. `cli/bin/<NOME>.js` + `cli/lib/colors.js` + `cli/commands/version.js` + `cli/commands/help.js` + `cli/commands/check.js`
20. `cli/package.json` (sem dependencies)
21. `tests/run-tests.sh` + 1 fixture exemplo
22. `docs/BASH-COMPAT.md` (auditoria de features bash 4+)
23. `.gitignore` com `.<NOME>/` ignorado
24. Smoke final: `bash scripts/<NOME>-run.sh --fast --parallel auto --verbose --no-proactive`
25. Smoke security: `bash scripts/<NOME>-run.sh --security-only --parallel auto --no-proactive`
26. Confirma cobertura ≥ 70% (deferred não conta como erro)
27. Confirma `✓ Schemas válidos` no fim
28. `git init` + `git add -A` + commit inicial `feat(v0.1.0): bootstrap agentic-harness`

Reporta ao final:
- Estrutura criada (tree visual)
- Quantos agentes determinísticos vs API-wrapped vs scanner-wrapper vs playbook-only
- Cobertura executável do smoke
- Próximo passo sugerido (qual agente materializar primeiro)

---

## Multi-agente paralelo (acelera evolução)

Quando precisar adicionar 5+ agentes ou fazer refactor amplo, NÃO faça sequencial. Spawn agentes Claude em paralelo:

- Group A: agentes/files que NÃO conflitam com Group B
- Group B: idem
- Group C: idem

Padrão validado: 4-5 sub-agentes em paralelo, cada um em arquivos diferentes, ~50% redução de wall-clock vs sequencial. Sem worktree necessária se cada agente toca arquivos distintos.

Após retornarem, o orquestrador principal (você) faz:
1. Smoke test integrado
2. Atualiza MODULE-MAP
3. Bump VERSION + CHANGELOG
4. Commit + tag
