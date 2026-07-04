#!/usr/bin/env bash
# Materializa: audit-log
BLINDAR_AGENT="check-audit-log"
source "$(dirname "$0")/_lib.sh"
log_section "Check: audit-log"

is_prisma || { emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0; }

# 1. Existe model AuditLog
HAS_MODEL=$(grep -cE "^model\s+(AuditLog|ActivityLog|Audit)" prisma/schema.prisma 2>/dev/null)
if [ "$HAS_MODEL" -eq 0 ]; then
  add_finding "high" "Sem model AuditLog/ActivityLog — exigido p/ compliance" "prisma/schema.prisma" ""
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi

# 2. Mutations sensíveis sem audit
SENSITIVE_OPS=$(rg -l "(prisma\.user|prisma\.role|prisma\.permission|prisma\.payment).*(update|delete)" --type ts '!node_modules' '!**/*.test.*' 2>/dev/null | wc -l || echo 0)
AUDIT_REFS=$(rg -l "(auditLog\.create|logAction|writeAudit)" --type ts '!node_modules' '!**/*.test.*' 2>/dev/null | wc -l || echo 0)

if [ "$SENSITIVE_OPS" -gt 0 ] && [ "$AUDIT_REFS" -eq 0 ]; then
  add_finding "high" "Mutations em user/role/payment sem auditLog.create()" "" ""
fi

emit_result "$BLINDAR_AGENT" "passed" 0
