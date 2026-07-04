#!/usr/bin/env bash
# Materializa: soft-delete (deletedAt em entidades principais)
BLINDAR_AGENT="check-soft-delete"
source "$(dirname "$0")/_lib.sh"
log_section "Check: soft-delete (deletedAt)"

is_prisma || { emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0; }

SCHEMA="prisma/schema.prisma"
[ ! -f "$SCHEMA" ] && { emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0; }

# Lista models e detecta quais não têm deletedAt
MODELS=$(grep -E "^model\s+" "$SCHEMA" | awk '{print $2}')
MISSING=()
for m in $MODELS; do
  # Pula models obviamente transient
  case "$m" in
    Session|Token|RefreshToken|VerificationToken|AuditLog|RateLimit|*Log) continue ;;
  esac
  # Extrai bloco do model
  HAS=$(awk -v m="$m" '$1=="model" && $2==m {flag=1; next} flag && /^}/ {flag=0} flag' "$SCHEMA" | grep -cE "(deletedAt|deleted_at)")
  [ "$HAS" -eq 0 ] && MISSING+=("$m")
done

if [ "${#MISSING[@]}" -gt 0 ]; then
  for m in "${MISSING[@]}"; do
    add_finding "med" "Model $m sem 'deletedAt' — hard delete em entidade principal" "$SCHEMA" ""
  done
fi

# Hard delete crus em código
RAW_DELETE=$(rg -c "prisma\.\w+\.delete\(|prisma\.\w+\.deleteMany\(" --type ts -g '!node_modules' -g '!**/*.test.*' 2>/dev/null | wc -l || echo 0)
[ "$RAW_DELETE" -gt 0 ] && add_finding "med" "$RAW_DELETE chamadas prisma.delete() — preferir update deletedAt" "" ""

[ "${#FINDINGS[@]}" -gt 0 ] && { emit_result "$BLINDAR_AGENT" "failed" 1; exit 0; }
emit_result "$BLINDAR_AGENT" "passed" 0
