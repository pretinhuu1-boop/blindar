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

# ─── Achado precisa dizer ONDE ───
# Os seis padrões abaixo contavam com `wc -l` e chamavam add_finding com file e
# line VAZIOS. O relatório dizia "6 process.env não-público" e não dizia em qual
# arquivo: crítico que ninguém consegue abrir. Rodando contra projeto real, dois
# críticos assim não reproduziram — e sem localização não havia como saber se
# eram reais, o que os torna piores que inúteis: consomem confiança.
#
# `_grep_src` já devolve `arquivo:linha:conteúdo`. Aqui isso vira UM achado por
# ocorrência, com localização. O teto existe para um padrão ruidoso não encher o
# relatório — e quando corta, DIZ que cortou: total silenciosamente truncado
# volta a ser o mesmo problema de "parece que cobriu tudo".
_localizados() { # severidade mensagem teto   (lê `arquivo:linha:...` na stdin)
  local sev="$1" msg="$2" teto="${3:-15}" n=0 total=0 linha arq lin
  local tmp; tmp=$(mktemp)
  cat > "$tmp"
  total=$(grep -c . "$tmp" 2>/dev/null || echo 0)
  if [ "${total:-0}" -eq 0 ]; then rm -f "$tmp"; return 1; fi
  while IFS= read -r linha; do
    [ -z "$linha" ] && continue
    n=$((n + 1))
    if [ "$n" -gt "$teto" ]; then break; fi
    arq="${linha%%:*}"
    lin="${linha#*:}"; lin="${lin%%:*}"
    case "$lin" in ''|*[!0-9]*) lin="" ;; esac
    add_finding "$sev" "$msg" "$arq" "$lin"
  done < "$tmp"
  if [ "$total" -gt "$teto" ]; then
    add_finding "$sev" "$msg — e mais $((total - teto)) ocorrência(s) além das $teto listadas" "" ""
  fi
  rm -f "$tmp"
  return 0
}

# 1. process.env.X exposto pra client (NEXT_PUBLIC_ / VITE_ são OK; resto não)
PUBLIC_LEAK_M=$(_grep_src 'process\.env\.[A-Z_]+' --type ts 2>/dev/null | grep -vE '(NEXT_PUBLIC_|VITE_|PUBLIC_|VUE_APP_|REACT_APP_)' | grep -E '(pages/|app/|components/|client/)')
_localizados "crit" "process.env não-público em arquivo client (vazará no bundle)" <<< "${PUBLIC_LEAK_M:-}" || true

# 2. console.log / logger com objeto inteiro user/token/secret
LOG_LEAK_M=$(_grep_src 'console\.(log|info|debug|error)\(.*\b(user|token|secret|password|apiKey|api_key)\b' --type ts --type js 2>/dev/null)
_localizados "high" "console.log com objeto sensível (user/token/etc)" <<< "${LOG_LEAK_M:-}" || true

# 3. throw new Error(secret/token/password)
ERR_LEAK_M=$(_grep_src 'throw new Error\(.*\b(secret|token|password|apiKey)\b' --type ts --type js 2>/dev/null)
_localizados "high" "Error message com valor de secret" <<< "${ERR_LEAK_M:-}" || true

# 4. JSON.stringify(req) em log (vaza headers c/ Authorization)
JSON_REQ_M=$(_grep_src 'JSON\.stringify\(req\b' --type ts --type js 2>/dev/null)
_localizados "high" "JSON.stringify(req) — pode vazar Authorization header" <<< "${JSON_REQ_M:-}" || true

# 5. Stack trace exposto em produção
STACK_EXPOSED_M=$(_grep_src 'res\.(send|json)\(.*err\.(stack|message)' --type ts --type js 2>/dev/null)
_localizados "med" "res.send(err.stack) — esconder em prod" <<< "${STACK_EXPOSED_M:-}" || true

# 6. Secret em URL/query string
URL_SECRET_M=$(_grep_src '(url|href|fetch)\(.*\?.*\b(token|secret|api_key|password)=' --type ts --type js 2>/dev/null)
_localizados "crit" "secret em query string — usar header Authorization" <<< "${URL_SECRET_M:-}" || true

CRITS=$(printf '%s\n' "${FINDINGS[@]}" | grep -c '"severity":"crit"' 2>/dev/null)
HIGHS=$(printf '%s\n' "${FINDINGS[@]}" | grep -c '"severity":"high"' 2>/dev/null)
if [ "$CRITS" -gt 0 ] || [ "$HIGHS" -gt 0 ]; then
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi
emit_result "$BLINDAR_AGENT" "passed" 0
