#!/usr/bin/env bash
# Materializa: security (umbrella check — helmet, sanitize, escape, eval)
BLINDAR_AGENT="check-security"
source "$(dirname "$0")/_lib.sh"
log_section "Check: security (umbrella — XSS/injection/eval)"

if ! command -v rg >/dev/null 2>&1; then emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0; fi
IGNORE=(-g '!node_modules' -g '!dist' -g '!.blindar' -g '!.git' -g '!**/*.test.*')

# 1. eval(), Function() com user input
EVAL_USER=$(rg -n "(eval|new Function)\(.*\b(req\.|input|userInput)" --type ts --type js "${IGNORE[@]}" 2>/dev/null | wc -l)
[ "$EVAL_USER" -gt 0 ] && add_finding "crit" "$EVAL_USER eval()/Function() com user input — RCE" "" ""

# 2. dangerouslySetInnerHTML com variável (não constante)
DANGEROUS=$(rg -n "dangerouslySetInnerHTML=\{\{\s*__html:\s*[a-z][a-zA-Z]*\b" --type ts 2>/dev/null | grep -vE "(sanitiz|DOMPurify)" | wc -l)
[ "$DANGEROUS" -gt 0 ] && add_finding "high" "$DANGEROUS dangerouslySetInnerHTML sem sanitização" "" ""

# 3. innerHTML = userInput
INNER_HTML=$(rg -n "\.innerHTML\s*=\s*[^'\"]" --type ts --type js "${IGNORE[@]}" 2>/dev/null | grep -vE "(sanitiz|DOMPurify|@blindar:keep)" | wc -l)
[ "$INNER_HTML" -gt 0 ] && add_finding "high" "$INNER_HTML innerHTML = variável — preferir textContent ou DOMPurify" "" ""

# 4. SQL raw string concat (não prepared)
SQL_CONCAT=$(rg -n "(SELECT|INSERT|UPDATE|DELETE).*\+.*\b(req\.|userInput|input)" --type ts --type js "${IGNORE[@]}" 2>/dev/null | wc -l)
[ "$SQL_CONCAT" -gt 0 ] && add_finding "crit" "$SQL_CONCAT SQL com concat de user input — SQL injection" "" ""

# 5. execSync/exec com user input
SHELL_INJ=$(rg -n "(exec|execSync|spawn)\(.*\b(req\.|userInput|input)" --type ts --type js "${IGNORE[@]}" 2>/dev/null | grep -vE "@blindar:safe-exec" | wc -l)
[ "$SHELL_INJ" -gt 0 ] && add_finding "crit" "$SHELL_INJ shell exec com user input — command injection" "" ""

# 6. helmet/sanitize ausente em Express
if grep -qE "\"express\":" package.json 2>/dev/null; then
  HAS_HELMET=$(rg -c "helmet" --type ts --type js "${IGNORE[@]}" 2>/dev/null | wc -l)
  [ "$HAS_HELMET" -eq 0 ] && add_finding "high" "Express sem helmet middleware" "" ""
fi

# 7. Open redirect (res.redirect com user input)
OPEN_REDIR=$(rg -n "res\.redirect\(.*\breq\." --type ts --type js "${IGNORE[@]}" 2>/dev/null | grep -v "whitelist\|allowlist" | wc -l)
[ "$OPEN_REDIR" -gt 0 ] && add_finding "med" "$OPEN_REDIR res.redirect com user input — open redirect" "" ""

# 8. document.write (XSS surface)
DOC_WRITE=$(rg -c "document\.write\(" --type ts --type js "${IGNORE[@]}" 2>/dev/null | wc -l)
[ "$DOC_WRITE" -gt 0 ] && add_finding "med" "$DOC_WRITE uso(s) de document.write — substituir" "" ""

CRITS=$(printf '%s\n' "${FINDINGS[@]}" | grep -c '"severity":"crit"' 2>/dev/null)
HIGHS=$(printf '%s\n' "${FINDINGS[@]}" | grep -c '"severity":"high"' 2>/dev/null)
if [ "$CRITS" -gt 0 ] || [ "$HIGHS" -gt 0 ]; then
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi
emit_result "$BLINDAR_AGENT" "passed" 0
