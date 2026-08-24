#!/usr/bin/env bash
# Materializa: client-bundle-secrets (segredo de provider VISÍVEL no browser)
#
# Por que este check existe, se já há gitleaks + runtime-secrets:
#   - check-secrets (gitleaks) varre FONTE e HISTÓRICO git.
#   - check-runtime-secrets varre a fonte e EXCLUI `dist`.
#   Nenhum dos dois olha o BUNDLE COMPILADO servido ao browser. Uma chave
#   inlineada em build-time (env não-pública embutida, config client com key
#   hardcoded) só aparece no JS que o navegador baixa — invisível para os dois
#   acima e visível para qualquer um que abra o DevTools. Esse é o vetor real
#   de "hardcoded Stripe/Mailgun key no frontend" que pentests acham primeiro:
#   comprometer nada, só abrir a aba Network.
#
# Escopo: SÓ chaves SECRETAS de provider (sk_live, mailgun key-, AWS AKIA, ...).
# Chaves PÚBLICAS de client (pk_live/pk_test do Stripe, NEXT_PUBLIC_, Google
# Maps browser key) são legítimas no bundle e NÃO são reportadas.
BLINDAR_AGENT="check-client-bundle-secrets"
source "$(dirname "$0")/_lib.sh"
log_section "Check: client-bundle-secrets (segredo de provider no bundle do browser)"

if ! command -v grep >/dev/null 2>&1; then
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

# Diretórios de saída SERVIDOS ao browser. `public/` entra porque é servido
# como-está. `src/` NÃO entra — quem cobre fonte é gitleaks/runtime-secrets.
CANDIDATOS=(dist build out .output/public .svelte-kit/output/client public/build public .next/static)
DIRS=()
for d in "${CANDIDATOS[@]}"; do
  [ -d "$d" ] && DIRS+=("$d")
done

if [ "${#DIRS[@]}" -eq 0 ]; then
  # Sem bundle no disco não há o que medir. NÃO é "sem segredo" — é ausência de
  # medição: o build ainda não rodou. skipped ≠ passed, e o log diz o porquê.
  log_warn "nenhum diretório de bundle encontrado (dist/build/out/.next/static/public)."
  log_warn "a exposição no browser NÃO foi verificada — rode o build e re-execute este check."
  log_warn "isto NÃO é 'nenhum segredo': é medição que não aconteceu."
  BLINDAR_MISSING_TOOL="client-build (bundle não presente)"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi
log_info "bundles a varrer: ${DIRS[*]}"

# Padrões de SEGREDO de provider — nenhum destes pode legitimamente estar num
# arquivo que o browser baixa. Rótulo|regex.
PATTERNS=(
  "Stripe secret key (sk_live)|sk_live_[0-9A-Za-z]{16,}"
  "Stripe secret key (sk_test)|sk_test_[0-9A-Za-z]{16,}"
  "Stripe restricted key (rk)|rk_(live|test)_[0-9A-Za-z]{16,}"
  "Mailgun private API key|key-[0-9a-f]{32}"
  "AWS access key id|AKIA[0-9A-Z]{16}"
  "Google API key|AIza[0-9A-Za-z_-]{35}"
  "Slack token|xox[baprs]-[0-9A-Za-z-]{10,}"
  "SendGrid API key|SG\.[A-Za-z0-9_-]{22}\.[A-Za-z0-9_-]{43}"
  "GitHub token|gh[pousr]_[0-9A-Za-z]{36}"
  "Private key block|-----BEGIN [A-Z ]*PRIVATE KEY-----"
  "OpenAI key|sk-[A-Za-z0-9]{20}T3BlbkFJ[A-Za-z0-9]{20}"
)

TOTAL=0
TETO=25
for spec in "${PATTERNS[@]}"; do
  rotulo="${spec%%|*}"
  regex="${spec#*|}"
  # -I pula binário; -o evita despejar linha minificada inteira; -n dá a linha.
  # Redigimos o valor: só o rótulo+arquivo:linha vão pro relatório, nunca a chave.
  while IFS=: read -r file line _; do
    [ -z "$file" ] && continue
    TOTAL=$((TOTAL + 1))
    [ "$TOTAL" -gt "$TETO" ] && continue
    add_finding "crit" "Segredo de provider no bundle servido ao browser ($rotulo) — qualquer um vê no DevTools" "$file" "$line"
  done < <(grep -rEIno "$regex" "${DIRS[@]}" 2>/dev/null)
done

if [ "$TOTAL" -gt "$TETO" ]; then
  add_finding "crit" "client-bundle-secrets — e mais $((TOTAL - TETO)) ocorrência(s) além das $TETO listadas" "" ""
fi

if [ "$TOTAL" -gt 0 ]; then
  log_fail "$TOTAL segredo(s) de provider no bundle do browser — mover para o servidor / env não-pública e ROTACIONAR (já vazou)"
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi

log_info "nenhum segredo de provider no bundle servido ao browser."
emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
