#!/usr/bin/env bash
# Wrapper que invoca check-tenant-isolation com o nome do MODULE-MAP
BLINDAR_AGENT="check-tenant-isolation-tests"
source "$(dirname "$0")/_lib.sh"
log_section "Check: tenant-isolation-tests"

# O portão também abre para modelo Python: multi-tenancy sem teste é promessa
# em qualquer linguagem, e o dia em que alguém esquecer o filtro de tenant nada
# avisa até um cliente ver o dado do outro.
_tenant_py() {
  command -v rg >/dev/null 2>&1 || return 1
  rg -q --type py "tenant_id|organization_id|tenantId" -g '!node_modules' . 2>/dev/null
}
if ! is_prisma && ! _tenant_py; then emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0; fi

MT=$(grep -cE "tenantId|tenant_id|organizationId" prisma/schema.prisma 2>/dev/null || echo 0)
# Sem schema.prisma, conta pelo modelo Python — o conceito é o mesmo.
if [ "${MT:-0}" -eq 0 ] && command -v rg >/dev/null 2>&1; then
  MT=$(rg -c --type py "tenant_id|organization_id" -g '!node_modules' . 2>/dev/null | wc -l || echo 0)
fi
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
