#!/usr/bin/env bash
# Materializa: secrets-rotation (90d policy)
BLINDAR_AGENT="check-secrets-rotation"
source "$(dirname "$0")/_lib.sh"
log_section "Check: secrets rotation"

# 1. Hardcoded secrets (grosseiro)
# ATENÇÃO: exclusões vão como `-g '!glob'`. A forma posicional ('!node_modules')
# NÃO é sintaxe do ripgrep — o rg real trata cada uma como PATH a pesquisar, não
# acha, sai com erro 2 e stdout vazio; o `2>/dev/null` esconde o erro e o `|| true`
# mascara o exit → o check reportava passed mesmo com secret hardcoded.
IGNORE=(-g '!node_modules' -g '!.git' -g '!dist' -g '!build' -g '!.blindar')
TMP=$(mktemp)
rg -n "(sk_live_|pk_live_|ghp_|xox[baprs]-|AIza[0-9A-Za-z\-_]{35}|AKIA[0-9A-Z]{16})" \
  --type ts --type js --type yaml --type env \
  "${IGNORE[@]}" 2>/dev/null > "$TMP" || true

COUNT=$(wc -l < "$TMP" || echo 0)
if [ "$COUNT" -gt 0 ]; then
  while IFS=: read -r file line _; do
    [ -z "$file" ] && continue
    add_finding "crit" "Possível secret hardcoded" "$file" "$line"
  done < "$TMP"
  rm -f "$TMP"
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi
rm -f "$TMP"

# 2. .env existe sem .env.example
if [ -f ".env" ] && [ ! -f ".env.example" ]; then
  add_finding "med" ".env existe mas falta .env.example pra onboarding seguro" ".env" ""
fi

# 3. README cita rotação
if [ -f README.md ] && ! grep -qiE "(rotação|rotation|secret.rotate|key.rotate)" README.md; then
  add_finding "low" "README não documenta política de rotação de secrets (90d recomendado)" "README.md" ""
fi

emit_result "$BLINDAR_AGENT" "passed" 0
