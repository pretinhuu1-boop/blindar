#!/usr/bin/env bash
# check-pii-encryption.sh
# Verifica envelope encryption de PII clínico (LGPD art. 46, HIPAA 164.312(a)(2)(iv)).
#
# Critérios:
#   CRIT — PII persistido sem cipher disponível (sem crypto lib ou sem uso nas rotas)
#   HIGH — PII_MASTER_KEY não referenciada em config / sem migration para colunas cifradas
#   MED  — fallback plaintext sem aviso / HMAC search ausente para campos buscáveis

BLINDAR_AGENT="check-pii-encryption"
source "$(dirname "$0")/_lib.sh"
log_section "Check: PII envelope encryption (DEK/KEK)"

if ! command -v rg >/dev/null 2>&1; then
  log_info "ripgrep ausente — skipping"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

# Globs de exclusão — passados como --glob para rg (sintaxe correta).
RG_IGNORE=(
  --glob '!node_modules/**'
  --glob '!dist/**'
  --glob '!build/**'
  --glob '!.blindar/**'
  --glob '!.git/**'
  --glob '!**/*.test.*'
  --glob '!**/*.spec.*'
  --glob '!**/__mocks__/**'
  --glob '!**/fixtures/**'
)

FAIL=0

# 1. Existe módulo de crypto com envelope (generateDek + encryptField + unwrapDek)
HAS_GENERATE_DEK=$(rg -l "generateDek|generate_dek" --type ts "${RG_IGNORE[@]}" 2>/dev/null | wc -l)
HAS_ENCRYPT_FIELD=$(rg -l "encryptField|encrypt_field|encryptPii" --type ts "${RG_IGNORE[@]}" 2>/dev/null | wc -l)
HAS_UNWRAP_DEK=$(rg -l "unwrapDek|unwrap_dek|decryptDek" --type ts "${RG_IGNORE[@]}" 2>/dev/null | wc -l)

if [ "$HAS_GENERATE_DEK" -eq 0 ] || [ "$HAS_ENCRYPT_FIELD" -eq 0 ] || [ "$HAS_UNWRAP_DEK" -eq 0 ]; then
  add_finding "crit" "Sem módulo DEK/KEK envelope encryption (generateDek + encryptField + unwrapDek) — PII em plaintext" "" "Criar lib/crypto.ts com AES-256-GCM envelope seguindo LGPD art. 46"
  FAIL=1
else
  log_pass "Módulo DEK/KEK encontrado ($HAS_GENERATE_DEK arquivo(s) com generateDek)"
fi

# 2. Rotas de pacientes usam as funções de encrypt/decrypt
ROUTES_ENCRYPT=$(rg -l "(encryptField|generateDek|decryptField|decryptPatientRow)" --type ts "${RG_IGNORE[@]}" 2>/dev/null | grep -iE "patient|paciente" | wc -l)
if [ "$ROUTES_ENCRYPT" -eq 0 ]; then
  add_finding "crit" "Rotas de pacientes não chamam encryptField/generateDek — PII gravado em plaintext" "" "Wiring DEK/KEK no handler POST/PATCH de patients"
  FAIL=1
else
  log_pass "Rotas de pacientes com encrypt/decrypt ($ROUTES_ENCRYPT arquivo(s))"
fi

# 3. PII_MASTER_KEY referenciada no config
HAS_KEK_CONFIG=$(rg -l "PII_MASTER_KEY|piiMasterKey" --type ts "${RG_IGNORE[@]}" 2>/dev/null | grep -iE "config|env|settings" | wc -l)
if [ "$HAS_KEK_CONFIG" -eq 0 ]; then
  add_finding "high" "PII_MASTER_KEY não referenciada no config — KEK não carregada em runtime" "src/config.ts" "Adicionar piiMasterKey: requiredInProd('PII_MASTER_KEY', '')"
else
  log_pass "PII_MASTER_KEY no config ($HAS_KEK_CONFIG arquivo(s))"
fi

# 4. Migration SQL com colunas DEK/cipher
HAS_MIGRATION=$(find . \( -name "*.sql" -o -name "*.up.sql" \) \
  ! -path "*/node_modules/*" ! -path "*/.git/*" ! -path "*/dist/*" 2>/dev/null \
  | xargs grep -lE "dek_ciphertext|phone_cipher|email_cipher|name_cipher" 2>/dev/null | wc -l)
if [ "$HAS_MIGRATION" -eq 0 ]; then
  add_finding "high" "Sem migration SQL para colunas dek_ciphertext/phone_cipher/email_cipher — schema em plaintext" "" "Criar migration ALTER TABLE patients ADD COLUMN dek_ciphertext BYTEA ..."
else
  log_pass "Migration com colunas cipher encontrada ($HAS_MIGRATION arquivo(s))"
fi

# 5. HMAC search para telefone (buscabilidade sem expor PII)
HAS_PHONE_HASH=$(rg -l "phoneSearchHash|phone_hash" --type ts "${RG_IGNORE[@]}" 2>/dev/null | wc -l)
if [ "$HAS_PHONE_HASH" -eq 0 ]; then
  add_finding "med" "Sem HMAC determinístico para busca por telefone — forced to scan plaintext ou abandonar busca" "" "Implementar phoneSearchHash() + coluna phone_hash + índice único"
else
  log_pass "HMAC phone_hash encontrado ($HAS_PHONE_HASH arquivo(s))"
fi

# 6. Confirma uso de AES-GCM (não ECB/CBC) no módulo de crypto próprio
# Nota: check-cryptography.sh cobre cifras fracas no monorepo todo;
# aqui verificamos apenas se o módulo DEK/KEK usa GCM especificamente.
HAS_GCM=$(rg -l "aes-256-gcm" --type ts "${RG_IGNORE[@]}" 2>/dev/null | wc -l)
if [ "$HAS_GCM" -eq 0 ]; then
  add_finding "high" "Módulo DEK/KEK não usa AES-256-GCM — verificar lib/crypto.ts" "" "Trocar modo para 'aes-256-gcm' com createCipheriv + getAuthTag"
else
  log_pass "AES-256-GCM confirmado no módulo de crypto ($HAS_GCM arquivo(s))"
fi

[ "$FAIL" -eq 1 ] && { emit_result "$BLINDAR_AGENT" "failed" "$FAIL"; exit 1; }
if [ "${#FINDINGS[@]}" -gt 0 ]; then
  HIGHS=$(printf '%s\n' "${FINDINGS[@]}" | grep -c '"severity":"high"' 2>/dev/null || true)
  HIGHS=${HIGHS:-0}
  [ "$HIGHS" -gt 0 ] && { emit_result "$BLINDAR_AGENT" "failed" 1; exit 1; }
fi
emit_result "$BLINDAR_AGENT" "passed" 0
