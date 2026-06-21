#!/usr/bin/env bash
# Materializa: access-control (OWASP A01 — Broken Access Control)
BLINDAR_AGENT="check-access-control"
source "$(dirname "$0")/_lib.sh"
log_section "Check: access-control (RBAC + ownership + IDOR)"

if ! command -v rg >/dev/null 2>&1; then emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0; fi
IGNORE=('!node_modules' '!dist' '!.blindar' '!.git' '!**/*.test.*')
FAIL=0

# 1. Endpoints sensíveis sem auth/role guard
NO_GUARD=0
TMP=$(mktemp)
rg -nE "(app\.(get|post|put|delete|patch)|router\.(get|post|put|delete|patch)|@(Get|Post|Put|Delete|Patch)\()" --type ts --type js "${IGNORE[@]}" 2>/dev/null > "$TMP" || true
while IFS=: read -r file line content; do
  [ -z "$file" ] && continue
  ctx=$(sed -n "$((line-3)),$((line+8))p" "$file" 2>/dev/null)
  echo "$ctx" | grep -qE "(auth|@UseGuards|@Roles|requireAuth|isAuthenticated|withAuth|@blindar:public-ok)" || NO_GUARD=$((NO_GUARD+1))
done < "$TMP"
rm -f "$TMP"
[ "$NO_GUARD" -gt 3 ] && add_finding "high" "$NO_GUARD endpoints sem guard de auth/role detectável" "" ""

# 2. req.params.id sem verificação de ownership
TMP=$(mktemp)
rg -nE "req\.(params|query)\.id" --type ts --type js "${IGNORE[@]}" 2>/dev/null > "$TMP" || true
NO_OWN=0
while IFS=: read -r file line content; do
  [ -z "$file" ] && continue
  ctx=$(sed -n "$line,$((line+10))p" "$file" 2>/dev/null)
  echo "$ctx" | grep -qE "(userId|user\.id|ownerId|tenantId|@blindar:public-resource)" || NO_OWN=$((NO_OWN+1))
done < "$TMP"
rm -f "$TMP"
[ "$NO_OWN" -gt 0 ] && add_finding "high" "$NO_OWN req.params.id sem ownership check (IDOR)" "" ""

# 3. Roles harcoded como string
HARD_ROLES=$(rg -cE "(role|roles)\s*[:=]\s*['\"](admin|root|super)['\"]" --type ts --type js "${IGNORE[@]}" 2>/dev/null | wc -l)
[ "$HARD_ROLES" -gt 0 ] && add_finding "med" "$HARD_ROLES roles hardcoded como string — usar enum/constante" "" ""

# 4. Default-allow (if !blocked) anti-pattern
DEFAULT_ALLOW=$(rg -cE "if\s*\(!.*\.(blocked|denied|banned)\)" --type ts --type js "${IGNORE[@]}" 2>/dev/null | wc -l)
[ "$DEFAULT_ALLOW" -gt 0 ] && add_finding "med" "$DEFAULT_ALLOW padrão default-allow detectado — preferir default-deny" "" ""

[ "$FAIL" -eq 1 ] && { emit_result "$BLINDAR_AGENT" "failed" 1; exit 1; }

# Findings high/crit failam
HIGHS=$(printf '%s\n' "${FINDINGS[@]}" | grep -c '"severity":"high"' 2>/dev/null || echo 0)
[ "$HIGHS" -gt 0 ] && { emit_result "$BLINDAR_AGENT" "failed" 1; exit 1; }
emit_result "$BLINDAR_AGENT" "passed" 0
