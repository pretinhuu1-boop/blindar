#!/usr/bin/env bash
# Wrapper que invoca check-tenant-isolation com o nome do MODULE-MAP
BLINDAR_AGENT="check-tenant-isolation-tests"
source "$(dirname "$0")/_lib.sh"
log_section "Check: tenant-isolation-tests"

is_prisma || { emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0; }

MT=$(grep -cE "tenantId|tenant_id|organizationId" prisma/schema.prisma 2>/dev/null || echo 0)
[ "${MT:-0}" -eq 0 ] && { emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0; }

# Conta findings de testes
ISO_TESTS=0
if [ -d "tests" ] || [ -d "__tests__" ] || [ -d "e2e" ]; then
  ISO_TESTS=$(find tests __tests__ e2e 2>/dev/null | grep -iE "(tenant.iso|cross.tenant|iso.tenant)" | wc -l)
fi

if [ "$ISO_TESTS" -eq 0 ]; then
  add_finding "high" "Multi-tenant sem teste de tenant-isolation (cross-tenant leak risk)" "tests/" ""
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi

log_info "$ISO_TESTS teste(s) de tenant-isolation detectados"
emit_result "$BLINDAR_AGENT" "passed" 0
