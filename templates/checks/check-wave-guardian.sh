#!/usr/bin/env bash
# Materializa: wave-guardian — valida run-report.json + bloqueia onda
#
# Uso (chamado pelo rounds-loop):
#   WAVE_NUMBER=2 \
#   WAVE_AGENTS="mock-killer,security,access-control" \
#   MIN_COVERAGE_PCT=90 \
#   bash check-wave-guardian.sh
#
# Lê: .blindar/run-report.json (precisa ter sido gerado por blindar-run.sh)
# Grava: .blindar/wave-<N>-guardian.md + .blindar/results/check-wave-guardian.json

BLINDAR_AGENT="check-wave-guardian"
source "$(dirname "$0")/_lib.sh"
log_section "Check: wave-guardian (gate de onda)"

RUN_REPORT="${BLINDAR_DIR:-.blindar}/run-report.json"
WAVE_NUMBER="${WAVE_NUMBER:-0}"
WAVE_AGENTS="${WAVE_AGENTS:-}"
MIN_COVERAGE_PCT="${MIN_COVERAGE_PCT:-90}"
GUARDIAN_MD="${BLINDAR_DIR:-.blindar}/wave-${WAVE_NUMBER}-guardian.md"

if [ ! -f "$RUN_REPORT" ]; then
  log_warn "run-report.json não encontrado — rode bash scripts/blindar-run.sh primeiro"
  add_finding "high" "wave-guardian sem run-report.json — pré-requisito ausente" "" ""
  emit_result "$BLINDAR_AGENT" "failed" 1
  cat > "$GUARDIAN_MD" <<EOF
# Wave $WAVE_NUMBER Guardian Report

**Status: BLOCKED** ❌

run-report.json ausente. Rode \`bash scripts/blindar-run.sh\` antes de fechar a onda.
EOF
  exit 1
fi

# Extrai métricas (jq se disponível, fallback grep/sed)
extract() {
  local field="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -r ".$field // 0" "$RUN_REPORT" 2>/dev/null
  else
    grep -oE "\"$field\"[[:space:]]*:[[:space:]]*[0-9]+" "$RUN_REPORT" | head -1 | sed -E 's/.*:[[:space:]]*([0-9]+).*/\1/'
  fi
}

PASSED=$(extract passed)
FAILED=$(extract failed)
SKIPPED=$(extract skipped)
DEFERRED=$(extract deferred)
ERRORED=$(extract errored)
COVERAGE=$(extract coverage_pct)
TOTAL=$(extract total_agents)

PASSED=${PASSED:-0}; FAILED=${FAILED:-0}; SKIPPED=${SKIPPED:-0}
DEFERRED=${DEFERRED:-0}; ERRORED=${ERRORED:-0}; COVERAGE=${COVERAGE:-0}; TOTAL=${TOTAL:-0}

log_info "Métricas: passed=$PASSED failed=$FAILED skipped=$SKIPPED deferred=$DEFERRED errored=$ERRORED coverage=${COVERAGE}%"

# ─── Decisão ───
BLOCK=0
declare -a BLOCK_REASONS=()

# 1. Errored = sempre bloqueia (lê arquivos reais para evitar falso-positivo do run-report)
REAL_ERRORED=0
if [ -d "${BLINDAR_DIR:-.blindar}/results" ]; then
  REAL_ERRORED=$(for f in "${BLINDAR_DIR:-.blindar}/results"/*.json; do
    [ "$(basename "$f")" = "check-wave-guardian.json" ] && continue
    grep -l '"status":"errored"' "$f" 2>/dev/null
  done | wc -l | tr -d ' ')
fi
if [ "${REAL_ERRORED:-0}" -gt 0 ]; then
  BLOCK=1
  BLOCK_REASONS+=("$REAL_ERRORED agente(s) com erro de execução (bug em script blindar)")
  add_finding "crit" "$REAL_ERRORED agente(s) errored — fix scripts blindar antes de fechar onda" "" ""
fi

# 2. Failed com severidade crit
if [ "$FAILED" -gt 0 ]; then
  # Conta crits via grep nos result files
  CRITS=0
  if [ -d "${BLINDAR_DIR:-.blindar}/results" ]; then
    # Exclui o próprio arquivo do wave-guardian para evitar referência circular.
    CRITS=$(for f in "${BLINDAR_DIR:-.blindar}/results"/*.json; do
      [ "$(basename "$f")" = "check-wave-guardian.json" ] && continue
      grep -h '"severity":"crit"' "$f" 2>/dev/null
    done | wc -l)
  fi
  if [ "${CRITS:-0}" -gt 0 ]; then
    BLOCK=1
    BLOCK_REASONS+=("$CRITS finding(s) críticos — não pode fechar onda")
    add_finding "crit" "$CRITS findings críticos detectados na onda" "" ""
  fi
fi

# 3. Deferred não-cobertos
if [ "$DEFERRED" -gt 0 ]; then
  # Verifica se há playbook execution markers (.blindar/playbook-executed/<agent>.json)
  COVERED=0
  if [ -d "${BLINDAR_DIR:-.blindar}/playbook-executed" ]; then
    COVERED=$(ls "${BLINDAR_DIR:-.blindar}/playbook-executed/" 2>/dev/null | wc -l)
  fi
  UNCOVERED=$((DEFERRED - COVERED))
  if [ "$UNCOVERED" -gt 0 ]; then
    BLOCK=1
    BLOCK_REASONS+=("$UNCOVERED agente(s) deferred sem playbook executado")
    add_finding "high" "$UNCOVERED playbook(s) pendente(s) — Claude precisa executar antes de fechar onda" "" ""
  fi
fi

# 4. Coverage abaixo do threshold (warn, não block)
if [ "$COVERAGE" -lt "$MIN_COVERAGE_PCT" ]; then
  add_finding "med" "Cobertura $COVERAGE% < threshold $MIN_COVERAGE_PCT% (warn, não bloqueia)" "" ""
fi

# ─── Gera relatório markdown ───
if [ "$BLOCK" -eq 1 ]; then
  cat > "$GUARDIAN_MD" <<EOF
# Wave $WAVE_NUMBER Guardian Report

- **Ran at**: $(date -u +%Y-%m-%dT%H:%M:%SZ)
- **Status: BLOCKED** ❌

## Métricas

| | |
|---|---|
| Total agentes | $TOTAL |
| Passed | $PASSED |
| Failed | $FAILED |
| Skipped | $SKIPPED |
| Deferred | $DEFERRED |
| Errored | $ERRORED |
| Cobertura | ${COVERAGE}% |

## Motivos do bloqueio

EOF
  for r in "${BLOCK_REASONS[@]}"; do
    echo "- $r" >> "$GUARDIAN_MD"
  done
  cat >> "$GUARDIAN_MD" <<EOF

## Ação requerida

1. Examine \`.blindar/run-report.json\` e \`.blindar/results/*.json\`
2. Corrija erros / playbooks pendentes
3. Re-rode \`bash scripts/blindar-run.sh --strict --module <ondas>\`
4. Re-invoque wave-guardian
5. Só feche a onda quando este relatório virar PASS
EOF
  log_fail "Wave $WAVE_NUMBER BLOCKED"
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi

# PASS
cat > "$GUARDIAN_MD" <<EOF
# Wave $WAVE_NUMBER Guardian Report

- **Ran at**: $(date -u +%Y-%m-%dT%H:%M:%SZ)
- **Status: PASS** ✅

## Métricas

| | |
|---|---|
| Total agentes | $TOTAL |
| Passed | $PASSED |
| Failed | $FAILED |
| Skipped | $SKIPPED |
| Deferred | $DEFERRED |
| Errored | $ERRORED |
| Cobertura | ${COVERAGE}% |

Onda pode fechar. Gere wave-${WAVE_NUMBER}-report.md + checkpoint de merge.
EOF

log_pass "Wave $WAVE_NUMBER PASS — pode fechar"
emit_result "$BLINDAR_AGENT" "passed" 0
