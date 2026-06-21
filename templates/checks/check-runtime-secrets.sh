#!/usr/bin/env bash
# Materializa: runtime-secrets (secrets em runtime/log/client)
BLINDAR_AGENT="check-runtime-secrets"
source "$(dirname "$0")/_lib.sh"
log_section "Check: runtime-secrets (vazamento em log/client/error)"

if ! command -v rg >/dev/null 2>&1; then emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0; fi
IGNORE=('!node_modules' '!dist' '!.blindar' '!.git' '!**/*.test.*')

# 1. process.env.X exposto pra client (NEXT_PUBLIC_ é OK; resto não)
PUBLIC_LEAK=$(rg -nE "process\.env\.[A-Z_]+" --type tsx --type ts 2>/dev/null | grep -vE "(NEXT_PUBLIC_|VITE_|PUBLIC_|VUE_APP_|REACT_APP_)" | grep -E "(pages/|app/|components/|client/)" | wc -l)
[ "$PUBLIC_LEAK" -gt 0 ] && add_finding "crit" "$PUBLIC_LEAK process.env não-público em arquivo client (vazará no bundle)" "" ""

# 2. console.log / logger com objeto inteiro user/token/secret
LOG_LEAK=$(rg -nE "console\.(log|info|debug|error)\(.*\b(user|token|secret|password|apiKey|api_key)\b" --type ts --type js "${IGNORE[@]}" 2>/dev/null | wc -l)
[ "$LOG_LEAK" -gt 0 ] && add_finding "high" "$LOG_LEAK console.log com objeto sensível (user/token/etc)" "" ""

# 3. throw new Error(secret/token/password)
ERR_LEAK=$(rg -cE "throw new Error\(.*\b(secret|token|password|apiKey)\b" --type ts --type js "${IGNORE[@]}" 2>/dev/null | wc -l)
[ "$ERR_LEAK" -gt 0 ] && add_finding "high" "$ERR_LEAK Error message com valor de secret" "" ""

# 4. JSON.stringify(req) em log (vaza headers c/ Authorization)
JSON_REQ=$(rg -cE "JSON\.stringify\(req\b" --type ts --type js "${IGNORE[@]}" 2>/dev/null | wc -l)
[ "$JSON_REQ" -gt 0 ] && add_finding "high" "$JSON_REQ JSON.stringify(req) — pode vazar Authorization header" "" ""

# 5. Stack trace exposto em produção (sentry/server)
STACK_EXPOSED=$(rg -cE "res\.(send|json)\(.*err\.(stack|message)" --type ts --type js "${IGNORE[@]}" 2>/dev/null | wc -l)
[ "$STACK_EXPOSED" -gt 0 ] && add_finding "med" "$STACK_EXPOSED res.send(err.stack) — esconder em prod" "" ""

# 6. Secret em URL/query string
URL_SECRET=$(rg -cE "(url|href|fetch)\(.*\?.*\b(token|secret|api_key|password)=" --type ts --type js "${IGNORE[@]}" 2>/dev/null | wc -l)
[ "$URL_SECRET" -gt 0 ] && add_finding "crit" "$URL_SECRET secret em query string — usar header Authorization" "" ""

CRITS=$(printf '%s\n' "${FINDINGS[@]}" | grep -c '"severity":"crit"' 2>/dev/null || echo 0)
HIGHS=$(printf '%s\n' "${FINDINGS[@]}" | grep -c '"severity":"high"' 2>/dev/null || echo 0)
if [ "$CRITS" -gt 0 ] || [ "$HIGHS" -gt 0 ]; then
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi
emit_result "$BLINDAR_AGENT" "passed" 0
