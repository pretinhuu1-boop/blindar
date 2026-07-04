#!/usr/bin/env bash
# Materializa: session-timeout-ux — timeout de inatividade configurável pelo adm,
# popup com blur ao expirar, resume sem perder estado, timeout-limite pra fechar.
BLINDAR_AGENT="check-session-timeout-ux"
source "$(dirname "$0")/_lib.sh"
log_section "Check: session-timeout-ux (timeout inatividade + popup/blur + resume)"

if ! command -v rg >/dev/null 2>&1; then emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0; fi
IGNORE=(-g '!node_modules' -g '!dist' -g '!.git' -g '!**/*.test.*')

# Só faz sentido se há sessão/auth E frontend
HAS_AUTH=$(rg -c "(session|login|signin|jwt|auth|Cookie|useAuth|AuthProvider)" --type ts --type js "${IGNORE[@]}" 2>/dev/null | wc -l)
HAS_UI=$(rg -c "(react|vue|svelte|next|@angular)" package.json 2>/dev/null | wc -l)
if [ "$HAS_AUTH" -eq 0 ] || [ "$HAS_UI" -eq 0 ]; then
  log_info "Sem auth+UI — session-timeout-ux não se aplica — skipped"
  emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0
fi

# 1. Timeout de inatividade (idle) implementado?
HAS_IDLE=$(rg -c "(idle|inactivity|sessionTimeout|session-timeout|autoLogout|auto-logout|IdleTimer|useIdle|onIdle|InactivityTimer)" --type ts --type js "${IGNORE[@]}" 2>/dev/null | wc -l)
if [ "$HAS_IDLE" -eq 0 ]; then
  add_finding "med" "App com sessão/auth mas SEM timeout de inatividade — sessão aberta indefinidamente é risco. Implemente idle-timeout configurável pelo adm" "" ""
  emit_result "$BLINDAR_AGENT" "failed" 1; exit 0
fi

# 2. Timeout é configurável (adm)?
HAS_CONFIG=$(rg -c "(SESSION_TIMEOUT|INACTIVITY_TIMEOUT|idleTimeoutMinutes|timeoutMinutes|sessionTimeoutMs|IDLE_TIMEOUT)" --type ts --type js -g '.env*' "${IGNORE[@]}" 2>/dev/null | wc -l)
[ "$HAS_CONFIG" -eq 0 ] && add_finding "low" "Timeout de inatividade parece hardcoded — torne configurável pelo adm nas configurações" "" ""

# 3. Popup + blur ao expirar (proteção visual)
HAS_BLUR=$(rg -c "(blur|backdrop|overlay|modal.*expir|expir.*modal|SessionExpired|TimeoutModal)" --type ts --type js --type css "${IGNORE[@]}" 2>/dev/null | wc -l)
[ "$HAS_BLUR" -eq 0 ] && add_finding "low" "Sem popup/blur ao expirar sessão — ao cair, embace o fundo (proteção) e mostre modal de refresh/resume" "" ""

# 4. Resume sem perder estado (draft/autosave)
HAS_RESUME=$(rg -c "(autosave|auto-save|draft|persistState|localStorage.*form|beforeunload|restoreState|resume)" --type ts --type js "${IGNORE[@]}" 2>/dev/null | wc -l)
[ "$HAS_RESUME" -eq 0 ] && add_finding "low" "Sem persistência de estado/draft — ao expirar/refresh o usuário perde o que estava fazendo. Salve rascunho pra retomar de onde parou" "" ""

[ "${#FINDINGS[@]}" -gt 0 ] && { emit_result "$BLINDAR_AGENT" "failed" 1; exit 0; }
emit_result "$BLINDAR_AGENT" "passed" 0
