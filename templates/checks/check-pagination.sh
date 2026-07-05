#!/usr/bin/env bash
# Materializa: pagination (findMany sem take/limit)
BLINDAR_AGENT="check-pagination"
source "$(dirname "$0")/_lib.sh"
log_section "Check: pagination obrigatória"

if ! command -v rg >/dev/null 2>&1; then emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0; fi

IGNORE=(-g '!node_modules' -g '!dist' -g '!**/*.test.*')
load_intelligence_globs "$BLINDAR_AGENT"

# Prisma findMany sem take
TMP=$(mktemp)
rg -n "findMany\(\s*\{?" --type ts "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null > "$TMP" || true
NO_TAKE=0
while IFS=: read -r file line content; do
  [ -z "$file" ] && continue
  # Lê 5 linhas após pra detectar take/limit
  CTX=$(sed -n "${line},$((line+8))p" "$file" 2>/dev/null)
  echo "$CTX" | grep -qE "(take:|limit:|first:|cursor:)" || {
    add_finding "med" "findMany sem take/limit/cursor" "$file" "$line"
    NO_TAKE=$((NO_TAKE+1))
  }
done < "$TMP"
rm -f "$TMP"

[ "$NO_TAKE" -gt 5 ] && log_warn "$NO_TAKE findMany sem paginação detectados"

[ "${#FINDINGS[@]}" -gt 0 ] && { emit_result "$BLINDAR_AGENT" "failed" 1; exit 0; }
emit_result "$BLINDAR_AGENT" "passed" 0
