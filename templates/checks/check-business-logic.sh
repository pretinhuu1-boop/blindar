#!/usr/bin/env bash
# Materializa: business-logic (OWASP ASVS V11)
BLINDAR_AGENT="check-business-logic"
source "$(dirname "$0")/_lib.sh"
log_section "Check: business-logic (ASVS V11 — preço/desconto/race)"

if ! command -v rg >/dev/null 2>&1; then emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0; fi

IGNORE=('!node_modules' '!dist' '!**/*.test.*')
FAIL=0

# 1. Preço/desconto calculado no client (deveria ser server-side)
TMP=$(mktemp)
rg -nE "(amount|price|total|discount)\s*=\s*.*req\.(body|query|params)" --type ts "${IGNORE[@]}" > "$TMP" 2>/dev/null || true
CLIENT_PRICING=$(wc -l < "$TMP" || echo 0)
[ "$CLIENT_PRICING" -gt 0 ] && add_finding "crit" "$CLIENT_PRICING — preço/desconto do client aceito sem validar no DB" "" "" && FAIL=1
rm -f "$TMP"

# 2. Optimistic locking (version column) ausente
HAS_VERSION=$(rg -c "version\s+Int.*@default" prisma/schema.prisma 2>/dev/null || echo 0)
if is_prisma && [ "$HAS_VERSION" -eq 0 ]; then
  add_finding "med" "Sem coluna 'version' pra optimistic locking — lost update" "prisma/schema.prisma" ""
fi

# 3. Race condition em atomicidade (read-then-write sem transaction)
TMP=$(mktemp)
rg -nB 5 "\.update\(" --type ts "${IGNORE[@]}" 2>/dev/null | grep -B 5 "findUnique\|findFirst" | grep -v "transaction\|\$transaction" | head -20 > "$TMP" || true
RACE=$(grep -c "findUnique\|findFirst" "$TMP" 2>/dev/null || echo 0)
[ "$RACE" -gt 0 ] && add_finding "med" "$RACE read-then-write sem transaction (race condition risk)" "" ""
rm -f "$TMP"

[ "$FAIL" -eq 1 ] && { emit_result "$BLINDAR_AGENT" "failed" 1; exit 1; }
emit_result "$BLINDAR_AGENT" "passed" 0
