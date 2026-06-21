#!/usr/bin/env bash
# Materializa: cryptography (OWASP A02 — Cryptographic Failures)
BLINDAR_AGENT="check-cryptography"
source "$(dirname "$0")/_lib.sh"
log_section "Check: cryptography (algoritmos fracos, salt, IV)"

if ! command -v rg >/dev/null 2>&1; then emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0; fi
IGNORE=('!node_modules' '!dist' '!.blindar' '!.git' '!**/*.test.*')
FAIL=0

# 1. MD5/SHA1 pra senha ou auth
WEAK_HASH=$(rg -cE "(crypto\.createHash\(['\"](md5|sha1)['\"]\)|md5\(.*password|sha1\(.*password)" --type ts --type js "${IGNORE[@]}" 2>/dev/null | wc -l)
if [ "$WEAK_HASH" -gt 0 ]; then
  add_finding "crit" "$WEAK_HASH uso(s) de MD5/SHA1 — usar Argon2id/bcrypt pra senha, SHA256+ pra integridade" "" ""
  FAIL=1
fi

# 2. bcrypt rounds < 12
LOW_BCRYPT=$(rg -cE "bcrypt\.(hash|hashSync)\([^,]+,\s*[0-9]\b" --type ts --type js "${IGNORE[@]}" 2>/dev/null | wc -l)
[ "$LOW_BCRYPT" -gt 0 ] && add_finding "high" "$LOW_BCRYPT bcrypt com rounds < 10 — usar 12+ (Argon2id melhor)" "" ""

# 3. Cipher fraco (DES, RC4, ECB)
WEAK_CIPHER=$(rg -cE "(createCipher\(['\"]des|aes-.*-ecb|rc4)" --type ts --type js "${IGNORE[@]}" 2>/dev/null | wc -l)
if [ "$WEAK_CIPHER" -gt 0 ]; then
  add_finding "crit" "$WEAK_CIPHER cipher fraco (DES/ECB/RC4) — usar AES-256-GCM" "" ""
  FAIL=1
fi

# 4. createCipher (deprecated, sem IV)
DEPRECATED=$(rg -cE "crypto\.createCipher\(" --type ts --type js "${IGNORE[@]}" 2>/dev/null | wc -l)
[ "$DEPRECATED" -gt 0 ] && add_finding "high" "$DEPRECATED createCipher (deprecated, sem IV) — usar createCipheriv" "" ""

# 5. Math.random pra crypto/token/session
INSECURE_RANDOM=$(rg -nE "Math\.random\(\)" --type ts --type js "${IGNORE[@]}" 2>/dev/null | grep -iE "(token|secret|session|nonce|salt|password|key)" | wc -l)
[ "$INSECURE_RANDOM" -gt 0 ] && add_finding "high" "$INSECURE_RANDOM Math.random() em contexto crypto — usar crypto.randomBytes/randomUUID" "" ""

# 6. JWT com algoritmo 'none' ou HS256 sem secret forte
JWT_NONE=$(rg -cE "algorithm:\s*['\"]none['\"]" --type ts --type js "${IGNORE[@]}" 2>/dev/null | wc -l)
[ "$JWT_NONE" -gt 0 ] && { add_finding "crit" "$JWT_NONE JWT com algorithm:none" "" ""; FAIL=1; }

# 7. Hardcoded IV/salt
HARDCODED_IV=$(rg -cE "(iv|salt)\s*=\s*['\"][a-zA-Z0-9+/=]{8,}['\"]" --type ts --type js "${IGNORE[@]}" 2>/dev/null | wc -l)
[ "$HARDCODED_IV" -gt 0 ] && add_finding "high" "$HARDCODED_IV IV/salt hardcoded — sempre gerar por sessão" "" ""

[ "$FAIL" -eq 1 ] && { emit_result "$BLINDAR_AGENT" "failed" 1; exit 1; }
HIGHS=$(printf '%s\n' "${FINDINGS[@]}" | grep -c '"severity":"high"' 2>/dev/null || echo 0)
[ "$HIGHS" -gt 0 ] && { emit_result "$BLINDAR_AGENT" "failed" 1; exit 1; }
emit_result "$BLINDAR_AGENT" "passed" 0
