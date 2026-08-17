#!/usr/bin/env bash
# Materializa: audit-log
BLINDAR_AGENT="check-audit-log"
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
log_section "Check: audit-log"

if ! is_prisma && ! tem_orm_python; then emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0; fi

# 1. Existe model AuditLog
HAS_MODEL=$(grep -cE "^model\s+(AuditLog|ActivityLog|Audit)" prisma/schema.prisma 2>/dev/null)
if [ "$HAS_MODEL" -eq 0 ]; then
  add_finding "high" "Sem model AuditLog/ActivityLog — exigido p/ compliance" "prisma/schema.prisma" ""
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi

# 2. Mutations sensíveis sem audit
SENSITIVE_OPS=$(rg -l "(prisma\.(user|role|permission|payment)|query\((User|Role|Permission|Payment)\)|(User|Role|Permission|Payment)\.objects).*(update|delete)" --type ts --type py -g '!node_modules' -g '!**/*.test.*' 2>/dev/null | wc -l || echo 0)
AUDIT_REFS=$(rg -l "(auditLog\.create|logAction|writeAudit|AuditLog\(|audit_log|LogEntry\.objects\.create)" --type ts --type py -g '!node_modules' -g '!**/*.test.*' 2>/dev/null | wc -l || echo 0)

if [ "$SENSITIVE_OPS" -gt 0 ] && [ "$AUDIT_REFS" -eq 0 ]; then
  add_finding "high" "Mutations em user/role/payment sem auditLog.create()" "" ""
fi

emit_result "$BLINDAR_AGENT" "passed" 0
