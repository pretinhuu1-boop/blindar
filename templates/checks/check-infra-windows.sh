#!/usr/bin/env bash
# Materializa: infra-windows — footguns de .bat/cmd. Bug real: .bat com parênteses
# no echo dentro de if() quebrava; sintaxe bash em .bat.
BLINDAR_AGENT="check-infra-windows"
source "$(dirname "$0")/_lib.sh"
log_section "Check: infra-windows (.bat/cmd footguns)"

if ! command -v rg >/dev/null 2>&1; then emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0; fi

BAT=$(ls *.bat scripts/*.bat *.cmd scripts/*.cmd 2>/dev/null)
if [ -z "$BAT" ]; then
  log_info "sem .bat/.cmd — skipped"; emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0
fi

# 1. echo com parênteses — cmd trata () como bloco e quebra dentro de if()
PAREN=$(rg -c "echo.*[()]" $BAT 2>/dev/null | wc -l)
[ "$PAREN" -gt 0 ] && add_finding "med" "echo com parênteses em .bat — cmd interpreta () como bloco e quebra dentro de if(). Escape ^( ^) ou reescreva" "" ""

# 2. Sintaxe bash num .bat (\$VAR, [ -f ], &&, export) — cmd não entende
BASHISM=$(rg -c "(\\\$[A-Za-z_{]|\[ +-[fedxzns] |&&| \|\| |^export |#!/)" $BAT 2>/dev/null | wc -l)
[ "$BASHISM" -gt 0 ] && add_finding "med" "Sintaxe bash em arquivo .bat (\$VAR, [ -f ], &&, export, shebang) — cmd não entende. Use %VAR%, 'if exist', chamadas separadas" "" ""

[ "${#FINDINGS[@]}" -gt 0 ] && { emit_result "$BLINDAR_AGENT" "failed" 1; exit 0; }
emit_result "$BLINDAR_AGENT" "passed" 0
