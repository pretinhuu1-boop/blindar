#!/usr/bin/env bash
# Wrapper API: adversarial-reviewer — red team de findings já encontrados
BLINDAR_AGENT="check-adversarial-reviewer"
source "$(dirname "$0")/_lib.sh"
source "$(dirname "$0")/_api_wrapper.sh"

log_section "Check: adversarial-reviewer (red team via Claude API)"

# Coleta evidência: aggregate.json + sample de findings dos outros checks
EVIDENCE=""
if [ -f "${BLINDAR_DIR:-.blindar}/results/aggregate.json" ]; then
  EVIDENCE="$(cat ${BLINDAR_DIR:-.blindar}/results/aggregate.json 2>/dev/null | head -c 30000)"
elif [ -d "${BLINDAR_DIR:-.blindar}/results" ]; then
  for f in ${BLINDAR_DIR:-.blindar}/results/*.json; do
    [ -f "$f" ] && EVIDENCE+=$'\n\n'"$(cat "$f" | head -c 2000)"
  done
fi

if [ -z "$EVIDENCE" ]; then
  log_warn "Sem aggregate/results pra revisar — rode run-all primeiro"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

SYSTEM="Você é o agente adversarial-reviewer do blindar.
Sua missão: tentar REFUTAR findings encontrados por outros agentes.
Para cada finding:
1. É realmente um problema OU é falso positivo?
2. A severidade está correta?
3. Está faltando algum risco crítico que outros agentes não viram?

Default: cético. Marque como refutado se em dúvida.
Reporte APENAS findings NOVOS (não duplicados) ou refutações importantes."

blindar_api_check "$BLINDAR_AGENT" "$SYSTEM" "Aggregate de findings:
$EVIDENCE

Sua análise adversarial:"
