#!/usr/bin/env bash
BLINDAR_AGENT="check-api-frontend-coverage"
source "$(dirname "$0")/_lib.sh"
source "$(dirname "$0")/_api_wrapper.sh"
log_section "Check: api-frontend-coverage (APIs órfãs)"

# Coleta endpoints
ENDPOINTS=""
ENDPOINTS+=$(rg -nE "(app|router)\.(get|post|put|delete|patch)\(['\"]" --type ts --type js '!node_modules' '!dist' 2>/dev/null | head -50)
ENDPOINTS+=$'\n'$(rg -nE "@(Get|Post|Put|Delete|Patch)\(" --type ts '!node_modules' 2>/dev/null | head -30)
ENDPOINTS+=$'\n'$(find app/api pages/api -name "route.ts" -o -name "*.ts" 2>/dev/null | head -30)

# Coleta chamadas client
CLIENT=""
CLIENT+=$(rg -nE "(fetch|axios\.|useQuery|useMutation|trpc\.)" --type ts --type tsx '!node_modules' 2>/dev/null | head -50)

if [ -z "$ENDPOINTS$CLIENT" ]; then
  log_warn "Sem código TS/JS pra analisar"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

SYSTEM="Você é o agente api-frontend-coverage do blindar.
Compare endpoints servidor com chamadas client. Identifique APIs órfãs
(servidor expõe, client não chama). Pra cada uma, proponha tela/componente
alinhado com o stack atual. Não invente endpoints. Não proponha UI grandiosa
pra endpoint trivial."

blindar_api_check "$BLINDAR_AGENT" "$SYSTEM" "ENDPOINTS SERVIDOR (parcial):
$ENDPOINTS

CHAMADAS CLIENT (parcial):
$CLIENT

Cruze e reporte APIs órfãs com proposta de UI."
