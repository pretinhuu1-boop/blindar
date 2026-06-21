#!/usr/bin/env bash
# Materializa agente: pwa-installable
# manifest.webmanifest válido, SW registered, ícones 192+512

BLINDAR_AGENT="check-pwa-installable"
source "$(dirname "$0")/_lib.sh"

log_section "Check: pwa-installable (manifest + SW + ícones)"

# Roda só se for projeto com UI
HAS_UI=0
if has_dir "public" || has_dir "app" || has_dir "pages" || has_dir "src/components"; then
  HAS_UI=1
fi
if [ "$HAS_UI" -eq 0 ]; then
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

FAIL=0

# 1. manifest.webmanifest ou manifest.json
log_info "Buscando manifest..."
MANIFEST=""
for path in public/manifest.webmanifest public/manifest.json app/manifest.ts; do
  if [ -f "$path" ]; then
    MANIFEST="$path"
    log_pass "Manifest detectado: $path"
    break
  fi
done

if [ -z "$MANIFEST" ]; then
  add_finding "med" "Sem manifest.webmanifest — app não é instalável" "public/" ""
  log_warn "Sem manifest"
else
  # 2. Validações do manifest (se for JSON)
  if [[ "$MANIFEST" == *.json || "$MANIFEST" == *.webmanifest ]]; then
    for field in name short_name display icons start_url theme_color background_color; do
      if ! jq -e ".$field" "$MANIFEST" > /dev/null 2>&1; then
        add_finding "med" "manifest sem campo obrigatório: $field" "$MANIFEST" ""
      fi
    done

    # display deve ser standalone (não browser)
    DISPLAY=$(jq -r '.display' "$MANIFEST" 2>/dev/null)
    if [ "$DISPLAY" = "browser" ]; then
      add_finding "high" "manifest com display:browser — não é instalável de verdade" "$MANIFEST" ""
    fi

    # icons 192 e 512 obrigatórios
    HAS_192=$(jq '[.icons[]? | select(.sizes | contains("192"))] | length' "$MANIFEST" 2>/dev/null)
    HAS_512=$(jq '[.icons[]? | select(.sizes | contains("512"))] | length' "$MANIFEST" 2>/dev/null)
    if [ "$HAS_192" = "0" ] || [ "$HAS_512" = "0" ]; then
      add_finding "high" "manifest sem ícones 192x192 OU 512x512" "$MANIFEST" ""
    fi

    # maskable icon (Android adaptive)
    MASKABLE=$(jq '[.icons[]? | select(.purpose | contains("maskable"))] | length' "$MANIFEST" 2>/dev/null)
    if [ "${MASKABLE:-0}" = "0" ]; then
      add_finding "med" "Sem ícone maskable — Android pode cortar o ícone" "$MANIFEST" ""
    fi
  fi
fi

# 3. Service Worker registrado
log_info "Verificando Service Worker..."
HAS_SW=$(grep -lE "(serviceWorker\.register|registerServiceWorker|VitePWA|next-pwa)" \
  -r src/ app/ pages/ public/ 2>/dev/null | head -1)
if [ -z "$HAS_SW" ]; then
  HAS_SW_LIB=$(grep -lE "\"(next-pwa|vite-plugin-pwa|workbox-window)\":" package.json 2>/dev/null | head -1)
  if [ -z "$HAS_SW_LIB" ]; then
    add_finding "med" "Sem Service Worker registrado — app não funciona offline" "" ""
  fi
fi

# 4. Meta tags Apple (iOS)
if [ -n "$MANIFEST" ]; then
  log_info "Verificando meta tags iOS..."
  LAYOUT=$(find . -maxdepth 4 \( -name "layout.tsx" -o -name "_app.tsx" -o -name "_document.tsx" -o -name "index.html" \) -not -path "./node_modules/*" 2>/dev/null | head -3)
  IOS_OK=0
  for f in $LAYOUT; do
    if grep -q "apple-mobile-web-app-capable" "$f" 2>/dev/null; then
      IOS_OK=1
    fi
  done
  if [ "$IOS_OK" -eq 0 ]; then
    add_finding "low" "Meta tags iOS PWA não detectadas (apple-mobile-web-app-capable, apple-touch-icon)" "" ""
  fi
fi

if [ "$FAIL" -eq 1 ]; then
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi

emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
