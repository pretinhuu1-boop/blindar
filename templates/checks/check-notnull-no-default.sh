#!/usr/bin/env bash
# Materializa: notnull-no-default — coluna NOT NULL sem default. Bug real: coluna
# snapshot (NOT NULL) não preenchida no code → INSERT falha (checkout 500).
BLINDAR_AGENT="check-notnull-no-default"
source "$(dirname "$0")/_lib.sh"
log_section "Check: notnull-no-default (coluna NOT NULL sem default)"

if ! command -v rg >/dev/null 2>&1; then emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0; fi
IGNORE=(-g '!node_modules' -g '!dist' -g '!.git' -g '!**/*.test.*')

# SQLAlchemy: Column(..., nullable=False) sem default/server_default (e não PK/FK)
NN=$(rg -n "Column\([^)]*nullable=False[^)]*\)" --type py "${IGNORE[@]}" 2>/dev/null | grep -viE "(default=|server_default=|primary_key=True|autoincrement)" | wc -l)
if [ "$NN" -gt 0 ]; then
  add_finding "med" "$NN coluna(s) NOT NULL sem default/server_default — se o código não passar o valor no INSERT, o banco rejeita (500). Garanta preenchimento ou adicione default" "" ""
fi

[ "${#FINDINGS[@]}" -gt 0 ] && { emit_result "$BLINDAR_AGENT" "failed" 1; exit 0; }
emit_result "$BLINDAR_AGENT" "passed" 0
