#!/usr/bin/env bash
# Materializa: runtime-secrets (secrets em runtime/log/client)
BLINDAR_AGENT="check-runtime-secrets"
source "$(dirname "$0")/_lib.sh"
log_section "Check: runtime-secrets (vazamento em log/client/error)"

if ! command -v rg >/dev/null 2>&1 && ! command -v grep >/dev/null 2>&1; then emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0; fi

# Helper: grep seguro que exclui node_modules/dist/.blindar/.git e usa PCRE2 quando disponível.
# Fallback: grep -rP (POSIX extended + Perl compat).
_grep_src() {
  local pattern="$1"; shift
  # Usa `rg` (binário real OU fallback grep -E de _lib.sh). Os padrões deste check
  # só usam \b e alternância (ERE) — não precisam de PCRE. Evita `grep -P`, que
  # falha em locale não-UTF-8 no Git Bash ("-P supports only unibyte...").
  rg -n "$pattern" -g '!node_modules' -g '!dist' -g '!.blindar' -g '!.git' -g '!**/*.test.*' "$@" 2>/dev/null
}

# 1. process.env.X exposto pra client (NEXT_PUBLIC_ / VITE_ são OK; resto não)
PUBLIC_LEAK=$(_grep_src 'process\.env\.[A-Z_]+' --type ts 2>/dev/null | grep -vE '(NEXT_PUBLIC_|VITE_|PUBLIC_|VUE_APP_|REACT_APP_)' | grep -E '(pages/|app/|components/|client/)' | wc -l)
[ "$PUBLIC_LEAK" -gt 0 ] && add_finding "crit" "$PUBLIC_LEAK process.env não-público em arquivo client (vazará no bundle)" "" ""

# 2. console.log / logger com objeto inteiro user/token/secret
LOG_LEAK=$(_grep_src 'console\.(log|info|debug|error)\(.*\b(user|token|secret|password|apiKey|api_key)\b' --type ts --type js 2>/dev/null | wc -l)
[ "$LOG_LEAK" -gt 0 ] && add_finding "high" "$LOG_LEAK console.log com objeto sensível (user/token/etc)" "" ""

# 3. throw new Error(secret/token/password)
ERR_LEAK=$(_grep_src 'throw new Error\(.*\b(secret|token|password|apiKey)\b' --type ts --type js 2>/dev/null | wc -l)
[ "$ERR_LEAK" -gt 0 ] && add_finding "high" "$ERR_LEAK Error message com valor de secret" "" ""

# 4. JSON.stringify(req) em log (vaza headers c/ Authorization)
JSON_REQ=$(_grep_src 'JSON\.stringify\(req\b' --type ts --type js 2>/dev/null | wc -l)
[ "$JSON_REQ" -gt 0 ] && add_finding "high" "$JSON_REQ JSON.stringify(req) — pode vazar Authorization header" "" ""

# 5. Stack trace exposto em produção
STACK_EXPOSED=$(_grep_src 'res\.(send|json)\(.*err\.(stack|message)' --type ts --type js 2>/dev/null | wc -l)
[ "$STACK_EXPOSED" -gt 0 ] && add_finding "med" "$STACK_EXPOSED res.send(err.stack) — esconder em prod" "" ""

# 6. Secret em URL/query string
URL_SECRET=$(_grep_src '(url|href|fetch)\(.*\?.*\b(token|secret|api_key|password)=' --type ts --type js 2>/dev/null | wc -l)
[ "$URL_SECRET" -gt 0 ] && add_finding "crit" "$URL_SECRET secret em query string — usar header Authorization" "" ""

CRITS=$(printf '%s\n' "${FINDINGS[@]}" | grep -c '"severity":"crit"' 2>/dev/null)
HIGHS=$(printf '%s\n' "${FINDINGS[@]}" | grep -c '"severity":"high"' 2>/dev/null)
if [ "$CRITS" -gt 0 ] || [ "$HIGHS" -gt 0 ]; then
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi
emit_result "$BLINDAR_AGENT" "passed" 0
