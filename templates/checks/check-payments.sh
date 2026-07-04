#!/usr/bin/env bash
# Materialização do agente: payments
# Greps PCI-grade: NUNCA armazenar CVV/PAN, usar BigInt cents, webhook verify

BLINDAR_AGENT="check-payments"
source "$(dirname "$0")/_lib.sh"

log_section "Check: payments PCI-safe"

if ! command -v rg >/dev/null 2>&1; then
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

# Só roda se detectar gateway de pagamento
GATEWAY_DETECTED=0
for pkg in stripe mercadopago pagseguro paypal adyen; do
  if grep -qE "\"$pkg\":|\"@.*$pkg.*\":" package.json 2>/dev/null; then
    GATEWAY_DETECTED=1
    log_info "Gateway detectado: $pkg"
  fi
done

if [ "$GATEWAY_DETECTED" -eq 0 ]; then
  log_info "Nenhum gateway de pagamento detectado — skipped"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

FAIL=0
IGNORE=(-g '!node_modules' -g '!dist' -g '!build' -g '!**/*.test.*' -g '!**/*.spec.*' -g '!**/__mocks__/**')

# 1. CVV armazenado (CRIT — PCI violation)
log_info "Buscando CVV/CVC/security_code armazenado..."
TMP=$(mktemp)
rg -ni "(cvv|cvc|security_code|cid)\s*[:=]" --type ts --type js --type py "${IGNORE[@]}" > "$TMP" 2>/dev/null || true
CVV_COUNT=$(wc -l < "$TMP" || echo 0)
if [ "$CVV_COUNT" -gt 0 ]; then
  while IFS=: read -r file line content; do
    [ -z "$file" ] && continue
    add_finding "crit" "CVV em código (PCI violation): $(echo "$content" | xargs)" "$file" "$line"
  done < "$TMP"
  log_fail "$CVV_COUNT referência(s) a CVV — PCI VIOLATION"
  FAIL=1
fi
rm -f "$TMP"

# 2. PAN/card_number em log
log_info "Buscando PAN em log/console..."
TMP=$(mktemp)
rg -n "(log|console|print).*(pan|card_number|cardnumber)" --type ts --type js --type py "${IGNORE[@]}" > "$TMP" 2>/dev/null || true
PAN_LOG=$(wc -l < "$TMP" || echo 0)
if [ "$PAN_LOG" -gt 0 ]; then
  while IFS=: read -r file line content; do
    [ -z "$file" ] && continue
    add_finding "crit" "PAN em log (PCI violation): $(echo "$content" | xargs)" "$file" "$line"
  done < "$TMP"
  log_fail "$PAN_LOG log de PAN — PCI VIOLATION"
  FAIL=1
fi
rm -f "$TMP"

# 3. Money em Float/Number em vez de BigInt cents
log_info "Buscando money em Float..."
TMP=$(mktemp)
rg -n "(amount|price|total|fee)\s*:\s*(Float|number)" --type ts --type prisma "${IGNORE[@]}" > "$TMP" 2>/dev/null || true
FLOAT_MONEY=$(wc -l < "$TMP" || echo 0)
if [ "$FLOAT_MONEY" -gt 0 ]; then
  while IFS=: read -r file line content; do
    [ -z "$file" ] && continue
    add_finding "high" "Money em Float (use BigInt cents): $(echo "$content" | xargs)" "$file" "$line"
  done < "$TMP"
  log_warn "$FLOAT_MONEY campo(s) money em Float"
fi
rm -f "$TMP"

# 4. Webhook sem signature verify
log_info "Buscando webhooks sem verify..."
TMP=$(mktemp)
rg -n "(webhook|stripe.*event|@Post.*webhook)" --type ts "${IGNORE[@]}" -A 15 2>/dev/null | \
  grep -B 15 -E "(req\.body|@Body)" | \
  grep -v -E "(constructEvent|verifySignature|verifyHmac|signature)" | \
  grep -E "@Post.*webhook" > "$TMP" || true
WEBHOOK_NO_VERIFY=$(wc -l < "$TMP" || echo 0)
if [ "$WEBHOOK_NO_VERIFY" -gt 0 ]; then
  add_finding "crit" "Possível webhook sem signature verify (revisar)" "código" ""
  log_fail "Webhook(s) sem signature verify detectado(s)"
  FAIL=1
fi
rm -f "$TMP"

# 5. Endpoint payment sem idempotency
log_info "Buscando POST /payments sem Idempotency-Key..."
TMP=$(mktemp)
rg -n "@Post.*payment" --type ts "${IGNORE[@]}" -A 10 2>/dev/null | \
  grep -B 10 "@Body" | \
  grep -v -E "(Idempotency-Key|idempotency)" > "$TMP" || true
# Heurística: se aparecer "@Post...payment" mas nenhum "Idempotency-Key" nas próximas 10 linhas
PAYMENT_NO_IDEM=$(grep -c "@Post" "$TMP" 2>/dev/null)
if [ "$PAYMENT_NO_IDEM" -gt 0 ]; then
  add_finding "high" "$PAYMENT_NO_IDEM endpoint payment sem Idempotency-Key header" "código" ""
  log_warn "$PAYMENT_NO_IDEM endpoint(s) payment sem idempotency"
fi
rm -f "$TMP"

if [ "$FAIL" -eq 1 ]; then
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi

emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
