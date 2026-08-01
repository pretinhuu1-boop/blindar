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
  # Lê com node, NÃO com jq: jq não é garantido no ambiente, e sem ele as
  # validações abaixo viravam no-op silencioso — o manifest podia ter
  # display:browser e zero ícones que o check reportava "passed". node já é
  # requisito duro do blindar (suíte de testes), então não adiciona dependência.
  if [[ "$MANIFEST" == *.json || "$MANIFEST" == *.webmanifest ]]; then
    if ! command -v node >/dev/null 2>&1; then
      add_finding "med" "node ausente — validação do manifest não pôde rodar" "$MANIFEST" ""
    else
      MANIFEST_FACTS=$(node -e '
        const fs = require("fs");
        let m = {};
        try { m = JSON.parse(fs.readFileSync(process.argv[1], "utf8")); } catch { console.log("PARSE_ERROR"); process.exit(0); }
        const icons = Array.isArray(m.icons) ? m.icons : [];
        const has = (s) => icons.some((i) => String(i.sizes || "").includes(s));
        const missing = ["name","short_name","display","icons","start_url","theme_color","background_color"]
          .filter((k) => m[k] === undefined || m[k] === null);
        console.log("MISSING=" + missing.join(","));
        console.log("DISPLAY=" + (m.display || ""));
        console.log("HAS_192=" + (has("192") ? 1 : 0));
        console.log("HAS_512=" + (has("512") ? 1 : 0));
        console.log("MASKABLE=" + (icons.some((i) => String(i.purpose || "").includes("maskable")) ? 1 : 0));
      ' "$MANIFEST" 2>/dev/null)

      if [ "$MANIFEST_FACTS" = "PARSE_ERROR" ] || [ -z "$MANIFEST_FACTS" ]; then
        add_finding "high" "manifest não é JSON válido — navegador ignora e o app não instala" "$MANIFEST" ""
      else
        MISSING=$(echo "$MANIFEST_FACTS" | grep '^MISSING=' | cut -d= -f2-)
        DISPLAY=$(echo "$MANIFEST_FACTS" | grep '^DISPLAY=' | cut -d= -f2-)
        HAS_192=$(echo "$MANIFEST_FACTS" | grep '^HAS_192=' | cut -d= -f2-)
        HAS_512=$(echo "$MANIFEST_FACTS" | grep '^HAS_512=' | cut -d= -f2-)
        MASKABLE=$(echo "$MANIFEST_FACTS" | grep '^MASKABLE=' | cut -d= -f2-)

        if [ -n "$MISSING" ]; then
          for field in $(echo "$MISSING" | tr ',' ' '); do
            add_finding "med" "manifest sem campo obrigatório: $field" "$MANIFEST" ""
          done
        fi

        # display deve ser standalone (não browser)
        if [ "$DISPLAY" = "browser" ]; then
          add_finding "high" "manifest com display:browser — não é instalável de verdade" "$MANIFEST" ""
        fi

        # icons 192 e 512 obrigatórios
        if [ "$HAS_192" != "1" ] || [ "$HAS_512" != "1" ]; then
          add_finding "high" "manifest sem ícones 192x192 OU 512x512" "$MANIFEST" ""
        fi

        # maskable icon (Android adaptive)
        if [ "$MASKABLE" != "1" ]; then
          add_finding "med" "Sem ícone maskable — Android pode cortar o ícone" "$MANIFEST" ""
        fi
      fi
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

# Veredito pela convenção da casa: crit/high reprovam, med/low passam com warn.
# Antes havia um `if [ "$FAIL" -eq 1 ]` com FAIL nunca saindo de 0 — ramificação
# morta: o check acumulava findings high (display:browser, sem ícone 192/512) e
# reportava "passed" em qualquer projeto.
TOTAL=${#FINDINGS[@]}
if [ "$TOTAL" -gt 0 ]; then
  CRITS=$(printf '%s\n' "${FINDINGS[@]}" | grep -c '"severity":"crit"')
  HIGHS=$(printf '%s\n' "${FINDINGS[@]}" | grep -c '"severity":"high"')
  if [ "$CRITS" -gt 0 ] || [ "$HIGHS" -gt 0 ]; then
    emit_result "$BLINDAR_AGENT" "failed" 1
    exit 1
  fi
fi

emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
