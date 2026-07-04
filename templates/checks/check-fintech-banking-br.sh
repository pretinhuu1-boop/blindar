#!/usr/bin/env bash
# Materialização do agente: fintech-banking-br
# Audita conformidade PIX, Open Finance, BACEN 4658, FAPI, e regulações BR.
# Skip gracioso se nenhuma integração financeira BR detectada.

BLINDAR_AGENT="check-fintech-banking-br"
source "$(dirname "$0")/_lib.sh"

log_section "Check: fintech-banking-br (PIX / Open Finance / BACEN)"

if ! command -v rg >/dev/null 2>&1 && ! type rg >/dev/null 2>&1; then
  log_warn "rg ausente — skipped"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

IGNORE=(-g '!node_modules' -g '!dist' -g '!build' -g '!.next' -g '!.blindar' -g '!**/*.test.*' -g '!**/*.spec.*' -g '!**/__mocks__/**' -g '!**/__tests__/**')

# ─── Detecção: roda só se houver sinal de integração financeira BR ───
FINTECH_DETECTED=0
DETECTED_SIGNALS=()

# Sinais em package.json / pyproject.toml / requirements.txt / go.mod
for sig in "@bacen/pix" "pix-utils" "openfinance" "open-banking" "ofb-" "node-sped-nfe" "nfe-utils" "pynfe" "esocial" "@itau" "@bradesco" "@sicredi"; do
  if grep -qE "\"?$sig" package.json pyproject.toml requirements.txt go.mod 2>/dev/null; then
    FINTECH_DETECTED=1
    DETECTED_SIGNALS+=("pkg:$sig")
  fi
done

# Sinais em env vars / código
ENV_FILES=$(ls .env .env.example .env.local .env.production 2>/dev/null)
if [ -n "$ENV_FILES" ]; then
  if grep -lE "(PIX_DICT|PIX_KEY|OPENFINANCE_|OPEN_BANKING_|BACEN_|SPI_|ISPB|NFE_|ESOCIAL_)" $ENV_FILES 2>/dev/null | head -1 >/dev/null; then
    FINTECH_DETECTED=1
    DETECTED_SIGNALS+=("env:financial-vars")
  fi
fi

# Sinais em endpoints
ENDPOINT_HITS=$(rg -l "(/cob|/cobv|/pix/devolucao|/open-banking/|/openfinance/|/consents|/accounts/balances)" --type ts --type js --type py "${IGNORE[@]}" 2>/dev/null | head -5)
if [ -n "$ENDPOINT_HITS" ]; then
  FINTECH_DETECTED=1
  DETECTED_SIGNALS+=("endpoints:pix-or-openfinance")
fi

if [ "$FINTECH_DETECTED" -eq 0 ]; then
  log_info "Nenhuma integração fintech/banking BR detectada — skipped"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

log_info "Sinais detectados: ${DETECTED_SIGNALS[*]}"

FAIL=0

# ─── 1. CRIT: Chave PIX hardcoded em código ───
log_info "Buscando chave PIX hardcoded..."
TMP=$(mktemp)
# CPF formato 11 dígitos, CNPJ 14 dígitos, email/phone como string longa
rg -n "(pix.?key|chave.?pix|chavePix|pixKey)\s*[:=]\s*['\"][0-9a-zA-Z@.+-]{8,}['\"]" \
  --type ts --type js --type py "${IGNORE[@]}" > "$TMP" 2>/dev/null || true
HARDCODED=$(wc -l < "$TMP" | tr -d ' ')
if [ "${HARDCODED:-0}" -gt 0 ]; then
  while IFS=: read -r file line content; do
    [ -z "$file" ] && continue
    add_finding "crit" "Chave PIX hardcoded (deveria ser env/config): $(echo "$content" | xargs)" "$file" "$line"
  done < "$TMP"
  log_fail "$HARDCODED chave(s) PIX hardcoded — CRIT"
  FAIL=1
fi
rm -f "$TMP"

# ─── 2. CRIT: Webhook financeiro/PIX sem signature verify ───
log_info "Buscando webhook PIX/financeiro sem verify..."
TMP=$(mktemp)
rg -n "(webhook|notificacao|callback).*(pix|bancario|financeiro|openbanking)" \
  --type ts --type js --type py "${IGNORE[@]}" -A 10 2>/dev/null | \
  grep -B 10 -E "(req\.body|@Body|request\.json)" | \
  grep -v -E "(verifySignature|constructEvent|hmac|verifyHmac|x-signature|verify_signature)" | \
  grep -E "(webhook|notificacao|callback).*(pix|bancario|financeiro)" > "$TMP" 2>/dev/null || true
WH_NO_VERIFY=$(wc -l < "$TMP" | tr -d ' ')
if [ "${WH_NO_VERIFY:-0}" -gt 0 ]; then
  add_finding "crit" "Webhook PIX/financeiro sem signature verify aparente (revisar manualmente)" "código" ""
  log_fail "$WH_NO_VERIFY webhook(s) financeiro(s) possivelmente sem verify — CRIT"
  FAIL=1
fi
rm -f "$TMP"

# ─── 3. CRIT: Sem audit log em transações financeiras ───
log_info "Verificando audit log em handlers financeiros..."
TMP=$(mktemp)
# Pega arquivos com endpoint financeiro
rg -l "(/cob|/pix|/transferencia|/devolucao|/open-banking)" --type ts --type js --type py "${IGNORE[@]}" 2>/dev/null > "$TMP" || true
FILES_FIN=$(wc -l < "$TMP" | tr -d ' ')
NO_AUDIT_COUNT=0
if [ "${FILES_FIN:-0}" -gt 0 ]; then
  while IFS= read -r file; do
    [ -z "$file" ] && continue
    if ! grep -qE "(auditLog|audit_log|AuditLog|audit\.log|paymentEvent|payment_event)" "$file" 2>/dev/null; then
      add_finding "crit" "Handler financeiro sem audit log (BACEN 4658 exige 5 anos)" "$file" ""
      NO_AUDIT_COUNT=$((NO_AUDIT_COUNT + 1))
    fi
  done < "$TMP"
fi
if [ "$NO_AUDIT_COUNT" -gt 0 ]; then
  log_fail "$NO_AUDIT_COUNT arquivo(s) com handler financeiro sem audit log — CRIT"
  FAIL=1
fi
rm -f "$TMP"

# ─── 4. HIGH: PIX sem idempotência (sem X-Idempotency-Key, sem txid imutável) ───
log_info "Buscando POST PIX/cob sem idempotência..."
TMP=$(mktemp)
rg -n "(\.post|@Post|@POST|app\.post|router\.post).*(/cob|/cobv|/pix/devolucao|/transferencia)" \
  --type ts --type js --type py "${IGNORE[@]}" -A 15 2>/dev/null | \
  grep -B 15 -E "(@Body|req\.body|request\.json)" | \
  grep -v -E "(idempoten|endToEndId|end_to_end_id|txid|X-Idempotency)" | \
  grep -E "/cob|/cobv|/pix/devolucao|/transferencia" > "$TMP" 2>/dev/null || true
PIX_NO_IDEM=$(wc -l < "$TMP" | tr -d ' ')
if [ "${PIX_NO_IDEM:-0}" -gt 0 ]; then
  add_finding "high" "$PIX_NO_IDEM endpoint(s) PIX/transferência sem idempotência (double-spend risk)" "código" ""
  log_warn "$PIX_NO_IDEM endpoint(s) PIX sem idempotência — HIGH"
fi
rm -f "$TMP"

# ─── 5. HIGH: Open Finance endpoint sem headers FAPI ───
log_info "Verificando headers FAPI em Open Finance..."
TMP=$(mktemp)
rg -l "(openfinance|open-banking|openBanking)" --type ts --type js --type py "${IGNORE[@]}" 2>/dev/null > "$TMP" || true
OF_FILES=$(wc -l < "$TMP" | tr -d ' ')
NO_FAPI=0
if [ "${OF_FILES:-0}" -gt 0 ]; then
  while IFS= read -r file; do
    [ -z "$file" ] && continue
    if ! grep -qE "(x-fapi-interaction-id|x-fapi-auth-date|x-fapi-customer)" "$file" 2>/dev/null; then
      add_finding "high" "Integração Open Finance sem headers FAPI obrigatórios (x-fapi-*)" "$file" ""
      NO_FAPI=$((NO_FAPI + 1))
    fi
  done < "$TMP"
fi
if [ "$NO_FAPI" -gt 0 ]; then
  log_warn "$NO_FAPI arquivo(s) Open Finance sem headers FAPI — HIGH"
fi
rm -f "$TMP"

# ─── 6. HIGH: JWT com algoritmo fraco em Open Finance ───
log_info "Buscando JWT com alg fraco (HS256/RS256/none) em contexto Open Finance..."
TMP=$(mktemp)
rg -n "algorithm[s]?\s*[:=]\s*\[?\s*['\"](HS256|RS256|none|HS384|HS512)['\"]" \
  --type ts --type js --type py "${IGNORE[@]}" > "$TMP" 2>/dev/null || true
WEAK_JWT=$(wc -l < "$TMP" | tr -d ' ')
if [ "${WEAK_JWT:-0}" -gt 0 ]; then
  while IFS=: read -r file line content; do
    [ -z "$file" ] && continue
    # Só conta como HIGH se aparecer perto de openfinance / fapi / pix
    if grep -qE "(openfinance|open-banking|fapi|pix|bacen)" "$file" 2>/dev/null; then
      add_finding "high" "JWT com alg fraco em contexto financeiro (use PS256/ES256): $(echo "$content" | xargs)" "$file" "$line"
    fi
  done < "$TMP"
  log_warn "$WEAK_JWT ocorrência(s) JWT alg fraco verificadas — HIGH se em contexto Open Finance"
fi
rm -f "$TMP"

# ─── 7. HIGH: Valor monetário em float (perde precisão) ───
log_info "Buscando valor monetário em Float..."
TMP=$(mktemp)
rg -n "(valor|amount|montante|saldo|preco|price|fee|tarifa)\s*:\s*(Float|number|float|double)" \
  --type ts --type prisma --type py "${IGNORE[@]}" > "$TMP" 2>/dev/null || true
FLOAT_COUNT=$(wc -l < "$TMP" | tr -d ' ')
if [ "${FLOAT_COUNT:-0}" -gt 0 ]; then
  while IFS=: read -r file line content; do
    [ -z "$file" ] && continue
    add_finding "high" "Valor monetário em float (use BIGINT cents / Decimal): $(echo "$content" | xargs)" "$file" "$line"
  done < "$TMP"
  log_warn "$FLOAT_COUNT campo(s) money em float — HIGH"
fi
rm -f "$TMP"

# ─── 8. MED: Sem retry com backoff em chamada PIX ───
log_info "Buscando chamadas PIX sem retry/backoff..."
TMP=$(mktemp)
rg -l "(/cob|/cobv|/pix/)" --type ts --type js --type py "${IGNORE[@]}" 2>/dev/null > "$TMP" || true
NO_RETRY=0
while IFS= read -r file; do
  [ -z "$file" ] && continue
  if ! grep -qE "(retry|backoff|p-retry|axios-retry|tenacity|exponential)" "$file" 2>/dev/null; then
    NO_RETRY=$((NO_RETRY + 1))
  fi
done < "$TMP"
if [ "$NO_RETRY" -gt 0 ]; then
  add_finding "medium" "$NO_RETRY arquivo(s) com chamada PIX sem retry/backoff (idempotente — dá pra retry)" "código" ""
  log_warn "$NO_RETRY arquivo(s) PIX sem retry — MED"
fi
rm -f "$TMP"

# ─── 9. MED: Limites de horário noturno PIX sem validação ───
log_info "Verificando validação de limite noturno PIX..."
TMP=$(mktemp)
rg -l "(transferencia|/cob|pix.?send|enviar.?pix)" --type ts --type js --type py "${IGNORE[@]}" 2>/dev/null > "$TMP" || true
NO_NIGHT_LIMIT=0
while IFS= read -r file; do
  [ -z "$file" ] && continue
  if ! grep -qiE "(limite.?noturno|night.?limit|horario.?noturno|20:00|06:00|getHours\(\))" "$file" 2>/dev/null; then
    NO_NIGHT_LIMIT=$((NO_NIGHT_LIMIT + 1))
  fi
done < "$TMP"
if [ "$NO_NIGHT_LIMIT" -gt 0 ]; then
  add_finding "medium" "$NO_NIGHT_LIMIT handler(s) PIX sem validação de limite noturno (20h-06h)" "código" ""
  log_warn "$NO_NIGHT_LIMIT handler(s) sem limite noturno — MED"
fi
rm -f "$TMP"

# ─── 10. LOW: Currency hardcoded sem suporte multi-currency ───
log_info "Buscando currency hardcoded..."
TMP=$(mktemp)
rg -n "currency\s*[:=]\s*['\"]BRL['\"]" --type ts --type js --type py "${IGNORE[@]}" > "$TMP" 2>/dev/null || true
HARD_CURRENCY=$(wc -l < "$TMP" | tr -d ' ')
if [ "${HARD_CURRENCY:-0}" -gt 3 ]; then
  add_finding "low" "$HARD_CURRENCY ocorrência(s) de BRL hardcoded (considere config se multi-currency)" "código" ""
  log_warn "$HARD_CURRENCY currency hardcoded — LOW"
fi
rm -f "$TMP"

if [ "$FAIL" -eq 1 ]; then
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi

emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
