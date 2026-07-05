#!/usr/bin/env bash
# Materializa: frontend (CSP/XSS/SRI/Trusted Types hardening)
BLINDAR_AGENT="check-frontend"
source "$(dirname "$0")/_lib.sh"
log_section "Check: frontend hardening (CSP/Trusted Types/SRI)"

if ! command -v rg >/dev/null 2>&1; then emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0; fi

# Só roda se UI
HAS_UI=0
for sig in "next.config" "vite.config" "vue.config" "svelte.config" "astro.config" "remix.config"; do
  ls ${sig}.* 2>/dev/null | head -1 | grep -q . && HAS_UI=1
done
[ "$HAS_UI" -eq 0 ] && { emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0; }

IGNORE=(-g '!node_modules' -g '!dist' -g '!.blindar' -g '!.git' -g '!**/*.test.*')
load_intelligence_globs "$BLINDAR_AGENT"

# 1. CSP nonce-based ou hash? (não unsafe-inline)
HAS_CSP=$(rg -c "Content-Security-Policy" --type ts --type js --type json --type html "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null | wc -l)
if [ "$HAS_CSP" -eq 0 ]; then
  add_finding "high" "Sem CSP — defesa principal contra XSS" "" ""
fi

# 2. Trusted Types não configurado
TT=$(rg -c "require-trusted-types-for" --type ts --type js --type json --type html "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null | wc -l)
[ "$TT" -eq 0 ] && add_finding "med" "Sem Trusted Types — anti-XSS moderno (Chrome 83+)" "" ""

# 3. Subresource Integrity em <script src=cdn>
TMP=$(mktemp)
rg -n "<script[^>]+src=['\"]https://(cdn|unpkg|jsdelivr)" --type html --type tsx "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null > "$TMP" || true
while IFS=: read -r file line content; do
  [ -z "$file" ] && continue
  echo "$content" | grep -q "integrity=" || add_finding "high" "Script CDN sem SRI integrity" "$file" "$line"
done < "$TMP"
rm -f "$TMP"

# 4. target="_blank" sem rel="noopener noreferrer"
NO_NOOPENER=$(rg -n 'target=["\x27]_blank["\x27]' --type tsx --type ts --type html "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null | grep -v "noopener" | wc -l)
[ "$NO_NOOPENER" -gt 0 ] && add_finding "med" "$NO_NOOPENER target=_blank sem rel=noopener (tabnabbing)" "" ""

# 5. <iframe> sem sandbox
IFRAME_NO_SANDBOX=$(rg -n "<iframe\b" --type tsx --type ts --type html "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null | grep -v "sandbox=" | wc -l)
[ "$IFRAME_NO_SANDBOX" -gt 0 ] && add_finding "med" "$IFRAME_NO_SANDBOX <iframe> sem sandbox attribute" "" ""

# 6. window.postMessage sem origin check
POST_MSG=$(rg -n "addEventListener\(['\"]message" --type ts --type js "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null | wc -l)
SAFE_POST=$(rg -n "event\.origin\s*[=!]==" --type ts --type js "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null | wc -l)
if [ "$POST_MSG" -gt 0 ] && [ "$SAFE_POST" -eq 0 ]; then
  add_finding "high" "postMessage listener sem origin check" "" ""
fi

CRITS=$(printf '%s\n' "${FINDINGS[@]}" | grep -c '"severity":"crit"' 2>/dev/null)
HIGHS=$(printf '%s\n' "${FINDINGS[@]}" | grep -c '"severity":"high"' 2>/dev/null)
if [ "$CRITS" -gt 0 ] || [ "$HIGHS" -gt 0 ]; then
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi
emit_result "$BLINDAR_AGENT" "passed" 0
