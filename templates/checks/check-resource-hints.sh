#!/usr/bin/env bash
# Materializa: resource-hints — a fila escondida antes do primeiro byte.
#
# Cada origem de terceiro na página custa, ANTES de qualquer download, uma
# resolução de DNS, um handshake TCP e um handshake TLS. Em 4G isso é 300–600ms
# por origem, em série, e o navegador só começa essa fila quando encontra a
# referência — no meio do parsing, tarde demais.
#
# `preconnect` antecipa o handshake para o começo do documento. `preload`
# antecipa o download do que é crítico. Um `<link rel="preconnect">` de uma linha
# costuma valer mais que qualquer minificação: não reduz bytes, remove espera.
#
# Onde mais dói: fonte (bloqueia o texto), script de pagamento (bloqueia o
# checkout), tag de analytics carregada no head.
BLINDAR_AGENT="check-resource-hints"
source "$(dirname "$0")/_lib.sh"
log_section "Check: preconnect/preload para origens de terceiro críticas"

PAGINAS=$(find . -maxdepth 4 \( -name '*.html' -o -name '*.htm' \) \
  -not -path '*/node_modules/*' -not -path '*/.git/*' -not -path '*/coverage/*' \
  -not -path '*/.blindar/*' 2>/dev/null | head -20)
# Frameworks colocam o head num componente, não num .html.
if [ -z "$PAGINAS" ]; then
  PAGINAS=$(grep -rIlE '<head>|<Head>|metadata|createHead' \
    --include='*.tsx' --include='*.jsx' --include='*.vue' --include='*.svelte' --include='*.astro' \
    --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=dist --exclude-dir=build \
    . 2>/dev/null | head -10)
fi

if [ -z "$PAGINAS" ]; then
  log_info "sem documento HTML nem componente de head — não se aplica"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

# Origens de terceiro que valem antecipação: bloqueiam renderização ou conversão.
CRITICAS='fonts\.googleapis\.com|fonts\.gstatic\.com|use\.typekit\.net|js\.stripe\.com|checkout\.stripe\.com|sdk\.mercadopago\.com|js\.pagseguro|www\.googletagmanager\.com|www\.google-analytics\.com|cdn\.jsdelivr\.net|unpkg\.com|cdnjs\.cloudflare\.com|player\.vimeo\.com|www\.youtube\.com'

ACHOU_ORIGEM=0
for p in $PAGINAS; do
  [ -f "$p" ] || continue
  ORIGENS=$(grep -ohE "https?://($CRITICAS)" "$p" 2>/dev/null | sed 's|https\?://||' | sort -u)
  [ -z "$ORIGENS" ] && continue
  ACHOU_ORIGEM=1
  for o in $ORIGENS; do
    if grep -qE "rel=[\"']?(preconnect|dns-prefetch|preload)[^>]*$o|$o[^>]*rel=[\"']?(preconnect|dns-prefetch|preload)" "$p" 2>/dev/null; then
      continue
    fi
    LN=$(grep -nF "$o" "$p" | head -1 | cut -d: -f1)
    add_finding "low" \
      "Origem de terceiro '$o' usada sem preconnect/preload — o navegador só começa DNS + TCP + TLS quando encontra a referência no meio do parsing; em 4G isso é 300–600ms de espera por origem, em série. Um <link rel=\"preconnect\" href=\"https://$o\"> no head remove essa fila." \
      "$p" "${LN:-}"
  done
done

if [ "$ACHOU_ORIGEM" -eq 0 ]; then
  log_pass "nenhuma origem de terceiro crítica nas páginas servidas — não há handshake a antecipar"
  emit_result "$BLINDAR_AGENT" "passed" 0
  exit 0
fi

if [ "${#FINDINGS[@]}" -gt 0 ]; then
  emit_result "$BLINDAR_AGENT" "failed" 0
  exit 0
fi
log_pass "origens de terceiro críticas com handshake antecipado"
emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
