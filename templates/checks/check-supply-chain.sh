#!/usr/bin/env bash
# Materializa: supply-chain
BLINDAR_AGENT="check-supply-chain"
source "$(dirname "$0")/_lib.sh"
log_section "Check: supply-chain (lockfile + audit + provenance)"

is_nodejs || { emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0; }

# 1. Lockfile presente
HAS_LOCK=0
for lf in package-lock.json yarn.lock pnpm-lock.yaml bun.lockb; do
  [ -f "$lf" ] && HAS_LOCK=1
done
if [ "$HAS_LOCK" -eq 0 ]; then
  add_finding "crit" "Sem lockfile — builds não-reprodutíveis, supply chain risk" "" ""
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi

# 2. npm audit (se npm)
if [ -f "package-lock.json" ] && command -v npm >/dev/null 2>&1; then
  log_info "Rodando npm audit..."
  AUDIT=$(npm audit --json 2>/dev/null || true)
  if [ -n "$AUDIT" ]; then
    CRITS_DEPS=$(echo "$AUDIT" | grep -oE '"critical":\s*[0-9]+' | head -1 | grep -oE '[0-9]+' || echo 0)
    HIGHS_DEPS=$(echo "$AUDIT" | grep -oE '"high":\s*[0-9]+' | head -1 | grep -oE '[0-9]+' || echo 0)
    [ "${CRITS_DEPS:-0}" -gt 0 ] && add_finding "crit" "$CRITS_DEPS vulnerabilidades críticas em deps (npm audit)" "" ""
    [ "${HIGHS_DEPS:-0}" -gt 0 ] && add_finding "high" "$HIGHS_DEPS vulnerabilidades high em deps" "" ""
  fi
fi

# 3. Deps em git URL (não pinned)
GIT_DEPS=$(grep -cE "\"[^\"]+\":\s*\"(git\+|github:|gitlab:)" package.json 2>/dev/null || echo 0)
[ "$GIT_DEPS" -gt 0 ] && add_finding "med" "$GIT_DEPS dep em git URL — pin SHA ou publicar npm" "" ""

# 4. Wildcard versions
WILDCARD=$(grep -cE "\"[^\"]+\":\s*\"\*\"" package.json 2>/dev/null || echo 0)
[ "$WILDCARD" -gt 0 ] && add_finding "high" "$WILDCARD dep com versão '*' — pin range específico" "" ""

CRITS=$(printf '%s\n' "${FINDINGS[@]}" | grep -c '"severity":"crit"' 2>/dev/null || echo 0)
HIGHS=$(printf '%s\n' "${FINDINGS[@]}" | grep -c '"severity":"high"' 2>/dev/null || echo 0)
if [ "$CRITS" -gt 0 ] || [ "$HIGHS" -gt 0 ]; then
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi
emit_result "$BLINDAR_AGENT" "passed" 0
