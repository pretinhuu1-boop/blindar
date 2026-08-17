#!/usr/bin/env bash
# Materializa: soft-delete (deletedAt em entidades principais)
BLINDAR_AGENT="check-soft-delete"
source "$(dirname "$0")/_lib.sh"

# ─── O portão também abre para ORM de Python ───
# Antes: só `prisma/schema.prisma`. Num projeto Django ou SQLAlchemy o check
# saía `skipped`, e `skipped` no meio de 108 resultados não é lido por
# ninguém como "esta regra não foi verificada aqui".
#
# As regras internas já entendem `.objects.filter(...).delete()` e
# `session.delete(...)`; faltava deixá-las rodar.
tem_orm_python() {
  command -v rg >/dev/null 2>&1 || return 1
  rg -q --type py "(from django|django\.db|models\.Model|declarative_base|DeclarativeBase|sqlalchemy|SQLModel|Base\.metadata)" \
     -g "!node_modules" . 2>/dev/null
}
log_section "Check: soft-delete (deletedAt)"

if ! is_prisma && ! tem_orm_python; then emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0; fi

SCHEMA="prisma/schema.prisma"
[ ! -f "$SCHEMA" ] && ! tem_orm_python && { emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0; }

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
RAW_DELETE=$(rg -c "prisma\.\w+\.delete\(|prisma\.\w+\.deleteMany\(|session\.delete\(|\.objects\.filter\([^)]*\)\.delete\(\)|\.filter\([^)]*\)\.delete\(\)" --type ts --type py -g '!node_modules' -g '!**/*.test.*' 2>/dev/null | wc -l || echo 0)
[ "$RAW_DELETE" -gt 0 ] && add_finding "med" "$RAW_DELETE chamadas prisma.delete() — preferir update deletedAt" "" ""

[ "${#FINDINGS[@]}" -gt 0 ] && { emit_result "$BLINDAR_AGENT" "failed" 1; exit 0; }
emit_result "$BLINDAR_AGENT" "passed" 0
