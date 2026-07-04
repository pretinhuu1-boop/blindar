#!/usr/bin/env bash
# Materialização do agente: db-architect (parcial)
# Valida schema.prisma: audit columns + UUID + tenant_id + global_tables intelligence

BLINDAR_AGENT="check-prisma-schema"
source "$(dirname "$0")/_lib.sh"

log_section "Check: db-architect (Prisma schema)"

if ! is_prisma; then
  log_info "Prisma não detectado — skipped"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

SCHEMA="prisma/schema.prisma"
FAIL=0

# 1. UUID v7 em PKs
log_info "Verificando UUID v7 em PKs..."
NON_UUID=$(grep -c "^\s*id\s\+Int\s\+@id" "$SCHEMA" 2>/dev/null)
if [ "$NON_UUID" -gt 0 ]; then
  add_finding "high" "$NON_UUID model(s) usando Int autoincrement — usar UUID v7" "$SCHEMA" ""
  log_fail "$NON_UUID PKs com Int autoincrement"
  FAIL=1
else
  log_pass "Todos PKs são UUID"
fi

# 2. Audit columns em models de negócio
log_info "Verificando audit columns (createdAt, updatedAt, deletedAt)..."
TMP=$(mktemp)
awk '/^model / { model=$2; in_model=1; has_created=0; has_updated=0; has_global=0 }
     /\/\/\/ @blindar:global/ { has_global=1 }
     /createdAt/ { has_created=1 }
     /updatedAt/ { has_updated=1 }
     /^}/ && in_model {
       if (!has_global && (!has_created || !has_updated))
         print model
       in_model=0
     }' "$SCHEMA" > "$TMP"

MISSING=$(wc -l < "$TMP" || echo 0)
if [ "$MISSING" -gt 0 ]; then
  while read -r model; do
    [ -z "$model" ] && continue
    add_finding "med" "Model '$model' sem createdAt/updatedAt (marque /// @blindar:global se intencional)" "$SCHEMA" ""
  done < "$TMP"
  log_warn "$MISSING model(s) sem audit columns"
fi
rm -f "$TMP"

# 3. tenant_id em models tenant-scoped (excluindo @blindar:global)
log_info "Verificando tenant_id em models multi-tenant..."
TMP=$(mktemp)
awk '/^model / { model=$2; in_model=1; has_tenant=0; has_global=0 }
     /\/\/\/ @blindar:global/ { has_global=1 }
     /tenantId|tenant_id/ { has_tenant=1 }
     /^}/ && in_model {
       if (!has_global && !has_tenant)
         print model
       in_model=0
     }' "$SCHEMA" > "$TMP"

MISSING_TENANT=$(wc -l < "$TMP" || echo 0)
if [ "$MISSING_TENANT" -gt 0 ]; then
  while read -r model; do
    [ -z "$model" ] && continue
    add_finding "high" "Model '$model' sem tenantId (marque /// @blindar:global se for global)" "$SCHEMA" ""
  done < "$TMP"
  log_fail "$MISSING_TENANT model(s) sem tenantId em projeto multi-tenant"
  FAIL=1
fi
rm -f "$TMP"

# 4. DateTime sem timezone (Prisma DateTime é tz-aware no Postgres, OK; só alerta se @db.Time sem tz)
log_info "Verificando timezones..."
NON_TZ=$(grep -c "@db\.Time\b" "$SCHEMA" 2>/dev/null)
if [ "$NON_TZ" -gt 0 ]; then
  add_finding "med" "Use @db.Timestamptz em vez de @db.Time" "$SCHEMA" ""
  log_warn "$NON_TZ campo(s) com @db.Time (sem timezone)"
fi

# 5. Money fields em Decimal em vez de BigInt
log_info "Verificando currency em BigInt..."
DEC_MONEY=$(grep -E "(price|amount|salary|cost|fee|total)\s+Decimal" "$SCHEMA" 2>/dev/null | wc -l || echo 0)
if [ "$DEC_MONEY" -gt 0 ]; then
  add_finding "high" "$DEC_MONEY campo(s) de dinheiro em Decimal — usar BigInt em centavos" "$SCHEMA" ""
  log_fail "$DEC_MONEY campos de dinheiro em Decimal"
  FAIL=1
fi

if [ "$FAIL" -eq 1 ] || [ "${#FINDINGS[@]}" -gt 0 ]; then
  emit_result "$BLINDAR_AGENT" "failed" 1
  [ "$FAIL" -eq 1 ] && exit 1
  exit 0
fi

emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
