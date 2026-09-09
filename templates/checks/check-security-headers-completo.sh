#!/usr/bin/env bash
# Materializa: security-headers-completo — a segunda metade dos cabeçalhos.
#
# `check-headers-security` cobre os quatro clássicos: CSP, HSTS, X-Frame-Options,
# Referrer-Policy. Este cobre o que quase ninguém configura e que fecha buracos
# reais:
#
#   Permissions-Policy  desliga câmera, microfone, geolocalização e sensores que
#                       a aplicação não usa. Sem ele, qualquer script de terceiro
#                       que entre na página (tag de analytics, dependência
#                       comprometida) pode pedir esses acessos em seu nome.
#   COOP / COEP / CORP  isolam o contexto de navegação. Sem COOP, uma janela
#                       aberta pelo seu site mantém referência ao `window` dele;
#                       e sem cross-origin isolation não há defesa de processo
#                       contra ataques de canal lateral tipo Spectre.
#
# Duas fontes de verdade, nesta ordem: a RESPOSTA HTTP real (quando há alvo) e a
# configuração no repositório (sempre). Config certa com proxy sobrescrevendo é o
# caso comum — por isso a resposta real vem primeiro quando existe.
BLINDAR_AGENT="check-security-headers-completo"
source "$(dirname "$0")/_lib.sh"
source "$(dirname "$0")/_dyn.sh"
log_section "Check: Permissions-Policy + isolamento de origem (COOP/COEP/CORP)"

if ! scan_hit 'express|fastify|@nestjs|next|koa|hapi|flask|django|fastapi|gin-gonic|rails|helmet|nginx|caddy|traefik|app\.listen'; then
  log_info "sem servidor HTTP no projeto — não se aplica"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

# `--url <valor>` (convenção do harness dinâmico) e `--url=<valor>` valem os dois.
dyn_parse_args "$@"
for a in "$@"; do
  case "$a" in --url=*) DYN_URL="${a#--url=}" ;; esac
done
URL=$(dyn_resolve_target || true)

CABECALHOS=""
FONTE="config"
if [ -n "$URL" ] && command -v curl >/dev/null 2>&1; then
  log_info "lendo cabeçalhos da resposta real: $URL"
  CABECALHOS=$(curl -sS -I --max-time 20 "$URL" 2>/dev/null | tr 'A-Z' 'a-z')
  if [ -z "$CABECALHOS" ]; then
    log_warn "alvo não respondeu — caindo para a configuração no repositório"
    BLINDAR_MISSING_TOOL="alvo-http-sem-resposta"
  else
    FONTE="resposta HTTP"
    # O sistema vivo respondeu: a evidência deixa de ser leitura de arquivo.
    BLINDAR_EVIDENCE_KIND="dynamic"
    mark_exercised
  fi
elif [ -n "$URL" ]; then
  log_warn "curl ausente — não consigo ler a resposta real; medindo só a configuração"
  BLINDAR_MISSING_TOOL="curl"
else
  log_info "sem URL alvo — medindo a configuração no repositório (informe com --url= para ler a resposta real)"
  BLINDAR_MISSING_TOOL="alvo-http-ausente"
fi

# Presente na resposta real OU declarado na configuração.
tem_header() { # nome-em-minusculas padrão-config
  local nome="$1" pat="$2"
  if [ -n "$CABECALHOS" ]; then
    printf '%s' "$CABECALHOS" | grep -qE "^$nome:" && return 0
    return 1
  fi
  scan_hit "$pat"
}

ONDE=""
for f in next.config.js next.config.ts next.config.mjs nginx.conf Caddyfile \
         src/middleware.ts middleware.ts src/app.ts src/server.ts; do
  [ -f "$f" ] && { ONDE="$f"; break; }
done

if ! tem_header "permissions-policy" 'Permissions-Policy|permissionsPolicy|permissions_policy|Feature-Policy'; then
  add_finding "med" \
    "Sem Permissions-Policy ($FONTE) — câmera, microfone, geolocalização e sensores continuam disponíveis para qualquer script que rode na página, inclusive de terceiro. Desligue explicitamente o que a aplicação não usa: Permissions-Policy: camera=(), microphone=(), geolocation=(), payment=()." \
    "$ONDE" ""
else
  log_pass "Permissions-Policy presente ($FONTE)"
fi

if ! tem_header "cross-origin-opener-policy" 'Cross-Origin-Opener-Policy|crossOriginOpenerPolicy'; then
  add_finding "low" \
    "Sem Cross-Origin-Opener-Policy ($FONTE) — janela aberta a partir do seu site mantém referência ao window dele; COOP: same-origin corta essa ponte e habilita o isolamento de processo" "$ONDE" ""
fi
if ! tem_header "cross-origin-embedder-policy" 'Cross-Origin-Embedder-Policy|crossOriginEmbedderPolicy'; then
  add_finding "low" \
    "Sem Cross-Origin-Embedder-Policy ($FONTE) — sem COEP não há cross-origin isolation, e sem isolamento não há defesa de processo contra canal lateral (Spectre)" "$ONDE" ""
fi
if ! tem_header "cross-origin-resource-policy" 'Cross-Origin-Resource-Policy|crossOriginResourcePolicy'; then
  add_finding "low" \
    "Sem Cross-Origin-Resource-Policy ($FONTE) — outro site pode embutir seus recursos e usá-los como oráculo de canal lateral; CORP: same-site é o default seguro" "$ONDE" ""
fi

# Os quatro clássicos entram aqui só quando há resposta real: no repositório eles
# já são território do check-headers-security, e duplicar achado é ruído.
if [ -n "$CABECALHOS" ]; then
  for par in "content-security-policy|high|CSP" \
             "strict-transport-security|high|HSTS" \
             "x-frame-options|med|X-Frame-Options" \
             "referrer-policy|low|Referrer-Policy"; do
    H=$(printf '%s' "$par" | cut -d'|' -f1)
    S=$(printf '%s' "$par" | cut -d'|' -f2)
    N=$(printf '%s' "$par" | cut -d'|' -f3)
    printf '%s' "$CABECALHOS" | grep -qE "^$H:" || \
      add_finding "$S" "$N ausente na resposta HTTP real de $URL — configurado no repositório ou não, o que chega ao navegador é isto" "" ""
  done
fi

if [ "${#FINDINGS[@]}" -gt 0 ]; then
  case "${FINDINGS[*]}" in
    *'"severity":"high"'*|*'"severity":"crit"'*) emit_result "$BLINDAR_AGENT" "failed" 1; exit 1 ;;
  esac
  emit_result "$BLINDAR_AGENT" "failed" 0
  exit 0
fi

log_pass "Permissions-Policy e isolamento de origem presentes ($FONTE)"
emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
