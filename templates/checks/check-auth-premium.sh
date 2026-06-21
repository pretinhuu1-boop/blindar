#!/usr/bin/env bash
# Materializa agente: auth-premium
# Detecta bcrypt em projeto novo, JWT HS256, refresh sem rotation, JWT em localStorage

BLINDAR_AGENT="check-auth-premium"
source "$(dirname "$0")/_lib.sh"

log_section "Check: auth-premium (Argon2id, JWT RS256, refresh rotation)"

if ! command -v rg >/dev/null 2>&1; then
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

# Detecta lib auth
AUTH_DETECTED=0
for lib in jsonwebtoken jose next-auth "@auth/core" lucia better-auth passport; do
  if grep -qE "\"$lib\":|\"@.*$lib\":" package.json 2>/dev/null; then
    AUTH_DETECTED=1
    log_info "Lib auth detectada: $lib"
  fi
done

if [ "$AUTH_DETECTED" -eq 0 ]; then
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

FAIL=0
IGNORE=('!node_modules' '!dist' '!build' '!**/*.test.*' '!**/*.spec.*')

# 1. bcrypt em projeto novo (use Argon2id)
log_info "Buscando bcrypt..."
BCRYPT=$(grep -E "\"bcrypt(js)?\":" package.json 2>/dev/null | wc -l || echo 0)
ARGON=$(grep -E "\"argon2\":" package.json 2>/dev/null | wc -l || echo 0)
if [ "$BCRYPT" -gt 0 ] && [ "$ARGON" -eq 0 ]; then
  add_finding "med" "bcrypt detectado em projeto sem Argon2 — migrar pra Argon2id (memoryCost 19MB)" "package.json" ""
  log_warn "bcrypt sem Argon2 — recomendado migrar"
fi

# 2. JWT HS256 (deveria ser RS256/EdDSA em microservices)
log_info "Buscando HS256..."
TMP=$(mktemp)
rg -n "(algorithm|alg)[:\s]*['\"]HS256['\"]" --type ts --type js "${IGNORE[@]}" > "$TMP" 2>/dev/null || true
HS256=$(wc -l < "$TMP" || echo 0)
if [ "$HS256" -gt 0 ]; then
  while IFS=: read -r file line content; do
    [ -z "$file" ] && continue
    add_finding "med" "JWT HS256 (preferir RS256/EdDSA): $(echo "$content" | xargs | cut -c1-80)" "$file" "$line"
  done < "$TMP"
fi
rm -f "$TMP"

# 3. Token em localStorage (CRIT — XSS lê)
log_info "Buscando JWT em localStorage..."
TMP=$(mktemp)
rg -n "localStorage\.setItem.*['\"](token|access[_-]?token|jwt|auth)" --type ts --type tsx --type js --type jsx "${IGNORE[@]}" > "$TMP" 2>/dev/null || true
LS_TOKEN=$(wc -l < "$TMP" || echo 0)
if [ "$LS_TOKEN" -gt 0 ]; then
  while IFS=: read -r file line content; do
    [ -z "$file" ] && continue
    add_finding "crit" "Token em localStorage (XSS lê): $(echo "$content" | xargs | cut -c1-80)" "$file" "$line"
  done < "$TMP"
  log_fail "$LS_TOKEN token(s) em localStorage — usar httpOnly cookie"
  FAIL=1
fi
rm -f "$TMP"

# 4. Refresh token sem rotation
log_info "Verificando refresh token rotation..."
if rg -lE "refreshToken|refresh_token" --type ts "${IGNORE[@]}" 2>/dev/null | head -1 | grep -q .; then
  if ! rg -lE "(rotation|rotate|used_at|family_id)" --type ts "${IGNORE[@]}" 2>/dev/null | head -1 | grep -q .; then
    add_finding "high" "Refresh token sem rotation detectado (sem rotation = token roubado vira eterno)" "" ""
    log_warn "Sem indicador de refresh rotation"
  fi
fi

# 5. Argon2id memoryCost adequado (OWASP 2024: 19MB)
log_info "Verificando Argon2id memoryCost..."
TMP=$(mktemp)
rg -n "argon2\.(hash|verify)" --type ts --type js "${IGNORE[@]}" -A 10 2>/dev/null > "$TMP" || true
if grep -q "memoryCost" "$TMP"; then
  if ! grep -qE "memoryCost.*19|memoryCost.*2\*\*14" "$TMP"; then
    add_finding "med" "Argon2id memoryCost diferente do recomendado OWASP 2024 (19MB)" "" ""
  fi
fi
rm -f "$TMP"

if [ "$FAIL" -eq 1 ]; then
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi

emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
