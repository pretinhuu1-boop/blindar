#!/usr/bin/env bash
# Materializa: runtime-adversarial (metade estática) — defesa DECLARADA que não
# defende.
#
# Origem: os checks de segurança perguntam "existe CSP?", "existe helmet?",
# "existe CORS configurado?". Todos passam quando a defesa está presente — e
# ficam cegos quando ela está presente e desligada na mesma linha. Helmet com
# `contentSecurityPolicy: false` satisfaz "usa helmet". CSP com
# `script-src 'unsafe-inline'` satisfaz "tem CSP".
#
# Isto é PIOR que ausência de defesa: a ausência aparece no relatório, o teatro
# aparece como aprovação. O código afirma proteção que o runtime não tem, e todo
# relatório a jusante repete a afirmação.
BLINDAR_AGENT="check-defense-theater"
source "$(dirname "$0")/_lib.sh"
log_section "Check: defesa declarada que não defende"

if ! command -v rg >/dev/null 2>&1; then
  log_fail "ripgrep (rg) requerido"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

GLOBS=(
  -g '!node_modules' -g '!vendor' -g '!dist' -g '!build' -g '!.next' -g '!coverage'
  -g '!.blindar' -g '!.git' -g '!**/fixtures/**'
  -g '!**/*.test.*' -g '!**/*.spec.*' -g '!**/__tests__/**' -g '!**/test/**' -g '!**/tests/**'
  -g '!**/*.md'
)
load_intelligence_globs "$BLINDAR_AGENT"

# Emite finding para cada linha casada, ignorando exceção explícita.
scan() { # severidade  padrão  mensagem
  local sev="$1" pat="$2" msg="$3" tmp
  tmp=$(mktemp)
  rg -n "$pat" "${GLOBS[@]}" "${INTEL_GLOBS[@]}" > "$tmp" 2>/dev/null || true
  grep -v '@blindar:keep' "$tmp" > "$tmp.f" 2>/dev/null || true
  mv "$tmp.f" "$tmp" 2>/dev/null || true
  while IFS=: read -r file line content; do
    [ -z "${file:-}" ] && continue
    add_finding "$sev" "$msg — $(echo "$content" | xargs | cut -c1-160)" "$file" "$line"
  done < "$tmp"
  rm -f "$tmp"
}

# 1. Verificação de TLS desligada. O canal continua criptografado e deixa de ser
#    autenticado: qualquer intermediário com um certificado próprio é aceito.
scan "crit" 'rejectUnauthorized[[:space:]]*:[[:space:]]*false' \
  "verificação de certificado TLS desligada (rejectUnauthorized: false) — TLS sem autenticação de par não protege contra intermediário"
scan "crit" 'NODE_TLS_REJECT_UNAUTHORIZED[[:space:]]*=[[:space:]]*.?0' \
  "NODE_TLS_REJECT_UNAUTHORIZED=0 desliga verificação de TLS do processo INTEIRO"
scan "crit" 'verify[[:space:]]*=[[:space:]]*False' \
  "requests com verify=False — certificado não é validado"

# 2. helmet presente com a proteção principal desligada.
scan "high" 'contentSecurityPolicy[[:space:]]*:[[:space:]]*false' \
  "helmet com contentSecurityPolicy: false — 'usa helmet' passa no check, mas não há CSP"

# 3. CSP que autoriza exatamente o que a CSP existe para bloquear.
#    A fronteira é o ';', que separa diretivas — NÃO a aspa: valor de CSP é cheio
#    de aspas legítimas ('self', 'none'), e excluí-las fazia o match parar em
#    "script-src 'self' ..." antes de chegar no 'unsafe-inline' logo adiante.
#    Com [^;]*, um "script-src 'self'; style-src 'unsafe-inline'" corretamente
#    NÃO casa, porque o ';' barra a travessia para a outra diretiva.
scan "high" "script-src[^;]*'unsafe-inline'" \
  "CSP com script-src 'unsafe-inline' — a CSP existe e não impede XSS injetado inline"
scan "high" "script-src[^;]*'unsafe-eval'" \
  "CSP com script-src 'unsafe-eval' — permite eval/Function sobre string controlada por entrada"

# 4. JWT verificado sem fixar o algoritmo: confusão de algoritmo, incluindo
#    aceitar 'none' ou trocar RS256 por HS256 usando a chave pública como segredo.
scan "crit" "algorithms[^)]*['\"]none['\"]" \
  "JWT aceitando algoritmo 'none' — assinatura deixa de ser verificada"

# 5. CORS refletindo qualquer origem COM credenciais. Origem refletida mais
#    cookie é leitura autenticada cross-site.
CORS_TMP=$(mktemp)
rg -n -U 'credentials[[:space:]]*:[[:space:]]*true' "${GLOBS[@]}" "${INTEL_GLOBS[@]}" -l > "$CORS_TMP" 2>/dev/null || true
while IFS= read -r f; do
  [ -z "${f:-}" ] && continue
  [ -f "$f" ] || continue
  if grep -qE "origin[[:space:]]*:[[:space:]]*(true|['\"]\*['\"])" "$f" 2>/dev/null; then
    ln=$(grep -nE "origin[[:space:]]*:[[:space:]]*(true|['\"]\*['\"])" "$f" 2>/dev/null | head -1 | cut -d: -f1)
    add_finding "crit" "CORS reflete qualquer origem COM credentials: true — qualquer site lê resposta autenticada da vítima" "$f" "${ln:-}"
  fi
done < "$CORS_TMP"
rm -f "$CORS_TMP"

if [ "${#FINDINGS[@]}" -gt 0 ]; then
  log_fail "${#FINDINGS[@]} defesa(s) declarada(s) que não defende(m)"
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi

log_pass "nenhuma defesa neutralizada na própria declaração"
emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
