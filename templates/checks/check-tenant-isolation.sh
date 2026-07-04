#!/usr/bin/env bash
# Materialização do agente: tenant-isolation-tests
# Detecta queries sem tenant_id em código multi-tenant.

BLINDAR_AGENT="check-tenant-isolation"
source "$(dirname "$0")/_lib.sh"

log_section "Check: tenant isolation"

if ! command -v rg >/dev/null 2>&1; then
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

# Detecta se é multi-tenant (tem coluna tenantId/tenant_id em algum schema)
IS_MULTITENANT=0
if grep -lE "tenantId|tenant_id" prisma/schema.prisma 2>/dev/null; then
  IS_MULTITENANT=1
elif grep -rlE "tenantId|tenant_id" src/ apps/ 2>/dev/null | head -1; then
  IS_MULTITENANT=1
fi

if [ "$IS_MULTITENANT" -eq 0 ]; then
  log_info "Não multi-tenant — skipped"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

IGNORE=(-g '!node_modules' -g '!dist' -g '!build' -g '!**/*.test.*' -g '!**/*.spec.*')

# 1. findMany/findFirst/findUnique sem where tenantId
log_info "Buscando queries sem tenant_id..."
TMP=$(mktemp)
rg -n "\.(findMany|findFirst|findUnique|count|aggregate)\(\{" --type ts "${IGNORE[@]}" -A 5 2>/dev/null | \
  awk '/findMany|findFirst|findUnique|count|aggregate/ {
    block=$0; getline; for(i=0;i<5;i++) { block=block " " $0; getline }
    if (block !~ /tenantId|tenant_id|@blindar:global/) print FILENAME":"FNR": "block
  }' > "$TMP" || true

ORPHAN_QUERIES=$(wc -l < "$TMP" || echo 0)
if [ "$ORPHAN_QUERIES" -gt 5 ]; then  # tolera alguns por contexto (admin, system, etc)
  add_finding "high" "$ORPHAN_QUERIES queries Prisma potencialmente sem tenant_id filter" "" ""
  log_warn "$ORPHAN_QUERIES queries Prisma sem tenant filter (revisar manual ou marcar @blindar:global)"
fi
rm -f "$TMP"

# 2. queryRawUnsafe sem tenant param (alto risco)
log_info "Buscando \$queryRawUnsafe perigosos..."
TMP=$(mktemp)
rg -n "\\\$queryRawUnsafe" --type ts "${IGNORE[@]}" > "$TMP" 2>/dev/null || true
UNSAFE=$(wc -l < "$TMP" || echo 0)
if [ "$UNSAFE" -gt 0 ]; then
  while IFS=: read -r file line content; do
    [ -z "$file" ] && continue
    add_finding "crit" "queryRawUnsafe (alto risco SQL injection): $(echo "$content" | xargs | cut -c1-80)" "$file" "$line"
  done < "$TMP"
  log_fail "$UNSAFE \$queryRawUnsafe — revisar URGENTE"
fi
rm -f "$TMP"

# 3. Verifica se existe arquivo de teste de isolation
log_info "Verificando tenant-isolation tests..."
if find tests/ test/ __tests__/ -name "*tenant*isolation*" -o -name "*isolation*tenant*" 2>/dev/null | head -1 | grep -q .; then
  log_pass "tests de isolamento detectados"
else
  add_finding "high" "Nenhum teste de tenant-isolation detectado" "tests/" ""
  log_fail "Sem testes de tenant-isolation em projeto multi-tenant"
fi

# 4. RLS no Postgres
if has_file "prisma/schema.prisma"; then
  log_info "Verificando RLS hints..."
  if grep -q "ROW LEVEL SECURITY\|@@rls\|enable_rls" prisma/schema.prisma 2>/dev/null; then
    log_pass "RLS detectado no schema"
  else
    add_finding "med" "RLS Postgres não detectado no schema.prisma — defesa em profundidade ausente" "prisma/schema.prisma" ""
  fi
fi

TOTAL=${#FINDINGS[@]}
CRITS=$(printf '%s\n' "${FINDINGS[@]}" | grep -c '"severity":"crit"')
HIGHS=$(printf '%s\n' "${FINDINGS[@]}" | grep -c '"severity":"high"')
if [ "$CRITS" -gt 0 ] || [ "$HIGHS" -gt 0 ]; then
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi

emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
