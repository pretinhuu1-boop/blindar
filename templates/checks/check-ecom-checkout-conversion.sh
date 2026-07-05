#!/usr/bin/env bash
# Materialização do agente: ecom-checkout-conversion
# Audita pontos críticos de conversão em checkout BR.
# Skip gracioso se nenhuma integração de e-commerce detectada.

BLINDAR_AGENT="check-ecom-checkout-conversion"
source "$(dirname "$0")/_lib.sh"

log_section "Check: ecom-checkout-conversion"

if ! command -v rg >/dev/null 2>&1 && ! type rg >/dev/null 2>&1; then
  log_warn "rg ausente — skipped"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

IGNORE=(-g '!node_modules' -g '!dist' -g '!build' -g '!.next' -g '!.blindar' -g '!**/*.test.*' -g '!**/*.spec.*' -g '!**/__mocks__/**' -g '!**/__tests__/**')
load_intelligence_globs "$BLINDAR_AGENT"

# ─── Detecção: roda só se houver sinal de e-commerce ───
ECOM_DETECTED=0
DETECTED_SIGNALS=()

# Sinais em package.json
for sig in "stripe" "mercadopago" "@mercadopago" "pagseguro" "cielo" "getnet" "paypal" "@adyen" "@stripe/stripe-js" "@stripe/react-stripe-js"; do
  if grep -qE "\"$sig\"|\"@[a-z-]*$sig" package.json 2>/dev/null; then
    ECOM_DETECTED=1
    DETECTED_SIGNALS+=("pkg:$sig")
  fi
done

# Sinais em rotas/arquivos
ROUTES_HITS=$(rg -l "(/checkout|/cart|/carrinho|/finalizar-compra|/sacola)" --type ts --type tsx --type js --type jsx "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null | head -5)
if [ -n "$ROUTES_HITS" ]; then
  ECOM_DETECTED=1
  DETECTED_SIGNALS+=("routes:checkout-or-cart")
fi

# Componentes
COMP_HITS=$(rg -l "(<Checkout|<Cart|<PaymentForm|<CartItem|useCart)" --type ts --type tsx --type jsx "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null | head -5)
if [ -n "$COMP_HITS" ]; then
  ECOM_DETECTED=1
  DETECTED_SIGNALS+=("components:checkout-or-cart")
fi

if [ "$ECOM_DETECTED" -eq 0 ]; then
  log_info "Nenhuma integração e-commerce detectada — skipped"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

log_info "Sinais detectados: ${DETECTED_SIGNALS[*]}"

FAIL=0

# ─── 1. HIGH: Checkout multi-step > 3 etapas ───
log_info "Verificando número de etapas do checkout..."
TMP=$(mktemp)
# Heurística: arquivos de checkout com referência a step/etapa numerada
rg -l "(checkout|cart|carrinho)" --type ts --type tsx --type jsx "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null > "$TMP" || true
MAX_STEPS=0
while IFS= read -r file; do
  [ -z "$file" ] && continue
  # Conta referências como step1..stepN, etapa1..etapaN, ou totalSteps={N}
  STEPS=$(grep -oiE "(step|etapa)[\s_-]?[0-9]+" "$file" 2>/dev/null | grep -oE "[0-9]+" | sort -nu | tail -1)
  STEPS_NUM=$(grep -oiE "totalSteps[\s:=]+[0-9]+|steps?\.length[^=]*=[\s]*[0-9]+|numSteps[\s:=]+[0-9]+" "$file" 2>/dev/null | grep -oE "[0-9]+" | sort -nu | tail -1)
  CUR=${STEPS:-0}
  CUR2=${STEPS_NUM:-0}
  [ "$CUR2" -gt "$CUR" ] && CUR=$CUR2
  [ "$CUR" -gt "$MAX_STEPS" ] && MAX_STEPS=$CUR
done < "$TMP"
if [ "$MAX_STEPS" -gt 3 ]; then
  add_finding "high" "Checkout com $MAX_STEPS etapas (>3 reduz conversão ~7%/etapa)" "checkout" ""
  log_warn "Checkout com $MAX_STEPS etapas — HIGH"
fi
rm -f "$TMP"

# ─── 2. MED: Form de cartão sem autocomplete cc-* ───
log_info "Verificando autocomplete cc-* em form de cartão..."
TMP=$(mktemp)
rg -n "<input[^>]*name=['\"]?(card|cc|cardnumber|card_number|cardNumber)" \
  --type tsx --type jsx --type html "${IGNORE[@]}" "${INTEL_GLOBS[@]}" > "$TMP" 2>/dev/null || true
CC_INPUTS=$(wc -l < "$TMP" | tr -d ' ')
NO_AUTOCOMPLETE=0
if [ "${CC_INPUTS:-0}" -gt 0 ]; then
  while IFS=: read -r file line content; do
    [ -z "$file" ] && continue
    if ! echo "$content" | grep -qiE "autocomplete[\s=]+['\"]?(cc-number|cc-exp|cc-csc|cc-name)"; then
      add_finding "medium" "Input de cartão sem autocomplete cc-* (bloqueia auto-fill): $(echo "$content" | xargs)" "$file" "$line"
      NO_AUTOCOMPLETE=$((NO_AUTOCOMPLETE + 1))
    fi
  done < "$TMP"
fi
if [ "$NO_AUTOCOMPLETE" -gt 0 ]; then
  log_warn "$NO_AUTOCOMPLETE input(s) cartão sem autocomplete — MED"
fi
rm -f "$TMP"

# ─── 3. HIGH: Sem 3DS2 em pagamento (presumido > R$ 500) ───
log_info "Verificando 3DS2 configurado..."
TMP=$(mktemp)
rg -l "(paymentIntents|payment_intents|stripe\.confirm|payment_method_types)" --type ts --type tsx --type js "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null > "$TMP" || true
HAS_PAYMENT=$(wc -l < "$TMP" | tr -d ' ')
HAS_3DS=$(rg -l "(three_d_secure|3ds|3DSecure|handleCardAction|request_three_d_secure)" --type ts --type tsx --type js "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null | head -1)
if [ "${HAS_PAYMENT:-0}" -gt 0 ] && [ -z "$HAS_3DS" ]; then
  add_finding "high" "Pagamento sem suporte a 3DS2 (risco fraude + BCB 3978 exige > R$ 500)" "código" ""
  log_warn "Sem suporte a 3DS2 detectado — HIGH"
fi
rm -f "$TMP"

# ─── 4. MED: Apple Pay / Google Pay ausentes ───
log_info "Verificando Apple Pay / Google Pay..."
HAS_APPLEPAY=$(rg -l "(PaymentRequestButton|applepay|apple-pay|ApplePay)" --type ts --type tsx --type js --type jsx "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null | head -1)
HAS_GPAY=$(rg -l "(googlepay|google-pay|GooglePay|google\.payments)" --type ts --type tsx --type js --type jsx "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null | head -1)
if [ -z "$HAS_APPLEPAY" ] && [ -z "$HAS_GPAY" ]; then
  add_finding "medium" "Sem Apple Pay nem Google Pay configurado (conversão mobile cai ~50%)" "código" ""
  log_warn "Wallets mobile ausentes — MED"
fi

# ─── 5. HIGH: Cart sem persist (refresh perde carrinho) ───
log_info "Verificando persist do carrinho..."
TMP=$(mktemp)
rg -l "(useCart|cartStore|CartContext|CartProvider)" --type ts --type tsx --type jsx "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null > "$TMP" || true
CART_FILES=$(wc -l < "$TMP" | tr -d ' ')
NO_PERSIST=0
if [ "${CART_FILES:-0}" -gt 0 ]; then
  while IFS= read -r file; do
    [ -z "$file" ] && continue
    if ! grep -qE "(localStorage|persist|hydrate|sessionStorage|IndexedDB|cookies\.set)" "$file" 2>/dev/null; then
      # Verifica também nos arquivos do mesmo dir
      DIR=$(dirname "$file")
      if ! grep -rqE "(localStorage|persist|hydrate)" "$DIR" 2>/dev/null; then
        add_finding "high" "Carrinho sem persist (refresh = perde itens)" "$file" ""
        NO_PERSIST=$((NO_PERSIST + 1))
      fi
    fi
  done < "$TMP"
fi
if [ "$NO_PERSIST" -gt 0 ]; then
  log_warn "$NO_PERSIST arquivo(s) cart sem persist — HIGH"
fi
rm -f "$TMP"

# ─── 6. MED: Sem retry com método alternativo em pagamento falho ───
log_info "Verificando retry com método alternativo..."
TMP=$(mktemp)
rg -l "(payment.?fail|payment.?error|paymentDeclined|card.?declined)" --type ts --type tsx "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null > "$TMP" || true
FAIL_FILES=$(wc -l < "$TMP" | tr -d ' ')
NO_FALLBACK=0
if [ "${FAIL_FILES:-0}" -gt 0 ]; then
  while IFS= read -r file; do
    [ -z "$file" ] && continue
    if ! grep -qiE "(pix|boleto|pagamento.?alternativo|alternative.?payment|try.?again.?with)" "$file" 2>/dev/null; then
      NO_FALLBACK=$((NO_FALLBACK + 1))
    fi
  done < "$TMP"
fi
if [ "$NO_FALLBACK" -gt 0 ]; then
  add_finding "medium" "$NO_FALLBACK handler(s) de falha sem oferecer PIX/boleto como fallback" "código" ""
  log_warn "$NO_FALLBACK fluxo(s) sem fallback alternativo — MED"
fi
rm -f "$TMP"

# ─── 7. LOW: Currency display sem locale pt-BR ───
log_info "Verificando formato de currency..."
TMP=$(mktemp)
rg -n "toFixed\(2\)" --type ts --type tsx --type js --type jsx "${IGNORE[@]}" "${INTEL_GLOBS[@]}" > "$TMP" 2>/dev/null || true
TOFIXED=$(wc -l < "$TMP" | tr -d ' ')
NO_LOCALE=0
if [ "${TOFIXED:-0}" -gt 0 ]; then
  while IFS=: read -r file line content; do
    [ -z "$file" ] && continue
    # Se NO mesmo arquivo NÃO houver Intl.NumberFormat ou toLocaleString pt-BR → suspeito
    if ! grep -qE "(toLocaleString.*pt-BR|Intl\.NumberFormat.*pt-BR|format-currency-br)" "$file" 2>/dev/null; then
      NO_LOCALE=$((NO_LOCALE + 1))
    fi
  done < "$TMP"
fi
if [ "$NO_LOCALE" -gt 3 ]; then
  add_finding "low" "$NO_LOCALE uso(s) de toFixed(2) sem locale pt-BR (R\$ 1,234.56 vs R\$ 1.234,56)" "código" ""
  log_warn "$NO_LOCALE currency sem locale — LOW"
fi
rm -f "$TMP"

# ─── 8. HIGH: Frete não calculado pré-checkout ───
log_info "Verificando cálculo de frete na sacola..."
HAS_SHIPPING=$(rg -l "(calcFrete|calcularFrete|calculate.?shipping|shippingCost|viaCorreios|melhorEnvio|frenet)" --type ts --type tsx "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null | head -1)
HAS_CART=$(rg -l "(cart|carrinho|sacola)" --type ts --type tsx "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null | head -1)
if [ -n "$HAS_CART" ] && [ -z "$HAS_SHIPPING" ]; then
  add_finding "high" "Sem cálculo de frete detectado (deveria estar na sacola/produto, não no fim do checkout)" "código" ""
  log_warn "Frete não calculado pré-checkout — HIGH"
fi

# ─── 9. LOW: CEP sem ViaCEP/BrasilAPI fallback ───
log_info "Verificando autocomplete de CEP..."
HAS_CEP_INPUT=$(rg -l "(<input[^>]*cep|name=['\"]?cep)" --type tsx --type jsx --type html "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null | head -1)
HAS_VIACEP=$(rg -l "(viacep\.com\.br|brasilapi\.com\.br|cep.*correios)" --type ts --type tsx --type js "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null | head -1)
if [ -n "$HAS_CEP_INPUT" ] && [ -z "$HAS_VIACEP" ]; then
  add_finding "low" "Campo de CEP sem ViaCEP/BrasilAPI autocomplete (UX de form longa)" "código" ""
  log_warn "CEP sem autocomplete — LOW"
fi

CRITS=$(printf '%s\n' "${FINDINGS[@]}" | grep -c '"severity":"crit"')
HIGHS=$(printf '%s\n' "${FINDINGS[@]}" | grep -c '"severity":"high"')
if [ "$FAIL" -eq 1 ] || [ "$CRITS" -gt 0 ] || [ "$HIGHS" -gt 0 ]; then
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi

emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
