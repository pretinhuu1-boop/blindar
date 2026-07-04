#!/usr/bin/env bash
# Materializa agente: observability
# Verifica logger estruturado, audit log, health endpoints, métricas

BLINDAR_AGENT="check-observability"
source "$(dirname "$0")/_lib.sh"

log_section "Check: observability (logger + audit + health + metrics)"

if ! command -v rg >/dev/null 2>&1; then
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

IGNORE=(-g '!node_modules' -g '!dist' -g '!build' -g '!**/*.test.*')
FAIL=0

# 1. Logger estruturado (pino/winston/bunyan), não console.* em prod
log_info "Verificando logger estruturado..."
HAS_LOGGER=$(grep -E "\"(pino|winston|bunyan|@nestjs/common)\":" package.json 2>/dev/null | wc -l || echo 0)
if [ "$HAS_LOGGER" -eq 0 ]; then
  add_finding "med" "Sem logger estruturado (pino/winston) — logs serão difíceis de queryar em prod" "package.json" ""
  log_warn "Sem logger estruturado detectado"
fi

# 2. Health endpoints (live/ready/deep)
log_info "Verificando health endpoints..."
TMP=$(mktemp)
rg -l "(\/health\/live|\/healthz|\/health\/ready|\/readyz)" --type ts --type js "${IGNORE[@]}" 2>/dev/null > "$TMP" || true
HEALTH_COUNT=$(wc -l < "$TMP" || echo 0)
if [ "$HEALTH_COUNT" -eq 0 ]; then
  add_finding "high" "Sem health endpoints (/health/live, /health/ready) — K8s não consegue monitorar" "" ""
  log_fail "Sem health endpoints"
  FAIL=1
fi
rm -f "$TMP"

# 3. Métricas (Prometheus / OpenTelemetry)
log_info "Verificando métricas..."
HAS_METRICS=$(grep -E "\"(@opentelemetry|prom-client|@nestjs/terminus)\":" package.json 2>/dev/null | wc -l || echo 0)
if [ "$HAS_METRICS" -eq 0 ]; then
  add_finding "med" "Sem coleta de métricas detectada (Prometheus/OTel) — observabilidade limitada" "package.json" ""
fi

# 4. PII em log (CRIT — LGPD/GDPR)
log_info "Buscando PII em log..."
TMP=$(mktemp)
rg -n "(logger|console|print)\.(info|debug|warn|error)\(.*(password|cpf|cnpj|cvv|ssn|credit_card|email)" \
  --type ts --type js --type py "${IGNORE[@]}" > "$TMP" 2>/dev/null || true
PII_LOG=$(wc -l < "$TMP" || echo 0)
if [ "$PII_LOG" -gt 0 ]; then
  while IFS=: read -r file line content; do
    [ -z "$file" ] && continue
    add_finding "crit" "PII em log (LGPD/GDPR violation): $(echo "$content" | xargs | cut -c1-80)" "$file" "$line"
  done < "$TMP"
  log_fail "$PII_LOG log(s) com PII"
  FAIL=1
fi
rm -f "$TMP"

# 5. Audit log table presente em projeto multi-tenant
log_info "Verificando audit log..."
if grep -lE "tenantId|tenant_id" prisma/schema.prisma 2>/dev/null | head -1 | grep -q .; then
  if ! grep -lE "(model Audit|model AuditLog|audit_log)" prisma/schema.prisma 2>/dev/null | head -1 | grep -q .; then
    add_finding "med" "Multi-tenant sem tabela audit_log — investigação de incidente difícil" "prisma/schema.prisma" ""
  fi
fi

# 6. Sentry / error reporting
HAS_SENTRY=$(grep -E "\"@sentry|@bugsnag|@datadog/browser-rum\":" package.json 2>/dev/null | wc -l || echo 0)
if [ "$HAS_SENTRY" -eq 0 ]; then
  add_finding "low" "Sem error reporting (Sentry/Bugsnag/Datadog RUM) — bugs em prod invisíveis" "" ""
fi

if [ "$FAIL" -eq 1 ]; then
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi

emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
