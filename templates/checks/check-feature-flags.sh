#!/usr/bin/env bash
# Materializa: feature-flags — flag inline, sem owner, flag estável > 30d
BLINDAR_AGENT="check-feature-flags"
source "$(dirname "$0")/_lib.sh"
log_section "Check: feature-flags (sistema dedicado + cleanup)"

if ! command -v rg >/dev/null 2>&1; then emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0; fi

IGNORE=(-g '!node_modules' -g '!dist' -g '!**/*.test.*' -g '!**/*.config.*')

# 1. process.env.NEW_FEATURE / ENABLE inline (anti-pattern)
TMP=$(mktemp)
rg -n "process\.env\.(NEW_|ENABLE_|FEATURE_)[A-Z_]+" --type ts --type js "${IGNORE[@]}" > "$TMP" 2>/dev/null || true
INLINE_FLAGS=$(wc -l < "$TMP" || echo 0)
if [ "$INLINE_FLAGS" -gt 2 ]; then
  add_finding "med" "$INLINE_FLAGS process.env feature flag inline — use sistema dedicado (DB ou LaunchDarkly)" "" ""
fi
rm -f "$TMP"

# 2. if (true)/if (false) hardcoded
HARDCODED=$(rg -c "if\s*\(\s*(true|false)\s*\)" --type ts "${IGNORE[@]}" 2>/dev/null | wc -l || echo 0)
[ "$HARDCODED" -gt 5 ] && add_finding "med" "$HARDCODED if(true/false) hardcoded — flag morta?" "" ""

# 3. Comment "TEMP" ou "remover depois"
TMP=$(mktemp)
rg -ni "(TEMP|temporary|remover depois|remove later).*flag" --type ts "${IGNORE[@]}" > "$TMP" 2>/dev/null || true
TEMP_FLAGS=$(wc -l < "$TMP" || echo 0)
[ "$TEMP_FLAGS" -gt 0 ] && add_finding "low" "$TEMP_FLAGS flag marcado como temporário (provável dívida)" "" ""
rm -f "$TMP"

# 4. Tabela feature_flags ausente em projeto com flags
if [ "$INLINE_FLAGS" -gt 0 ] && is_prisma; then
  if ! grep -qE "model FeatureFlag|model feature_flag" prisma/schema.prisma 2>/dev/null; then
    add_finding "med" "Flags inline mas sem tabela feature_flags no schema — sem rollout gradual nem kill switch" "" ""
  fi
fi

emit_result "$BLINDAR_AGENT" "passed" 0
