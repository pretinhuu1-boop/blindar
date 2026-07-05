#!/usr/bin/env bash
# Materializa: cdn-strategy — Cache-Control, immutable assets, ?utm em canonical
BLINDAR_AGENT="check-cdn-strategy"
source "$(dirname "$0")/_lib.sh"
log_section "Check: CDN strategy (cache + immutable + UTM)"

if ! command -v rg >/dev/null 2>&1; then emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0; fi

if ! has_dir "public" && ! has_dir "app" && ! has_dir "src/components"; then
  emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0
fi

IGNORE=(-g '!node_modules' -g '!dist' -g '!build' -g '!**/*.test.*')
load_intelligence_globs "$BLINDAR_AGENT"

# 1. Cache-Control: no-cache em tudo (CDN inútil)
TMP=$(mktemp)
rg -n "Cache-Control.*no-cache" --type ts --type js --type yaml "${IGNORE[@]}" "${INTEL_GLOBS[@]}" > "$TMP" 2>/dev/null || true
NO_CACHE_ALL=$(wc -l < "$TMP" || echo 0)
if [ "$NO_CACHE_ALL" -gt 3 ]; then
  add_finding "med" "$NO_CACHE_ALL Cache-Control: no-cache espalhado — CDN não consegue cachear" "" ""
fi
rm -f "$TMP"

# 2. <img> sem next/image (já coberto por frontend-performance, mas relevante aqui)
RAW_IMG=$(rg -c "<img "   "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null | wc -l || echo 0)
[ "$RAW_IMG" -gt 5 ] && add_finding "low" "$RAW_IMG <img> sem next/image — perde optimization + cache CDN" "" ""

# 3. Asset path sem hash (cache eterno = bug eterno)
TMP=$(mktemp)
rg -n "src=['\"]/(images|assets)/[^'\"]*\\.(js|css|png|jpg)['\"]" --type html "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null | \
  grep -vE "[a-f0-9]{6,}" > "$TMP" || true
NO_HASH=$(wc -l < "$TMP" || echo 0)
[ "$NO_HASH" -gt 0 ] && add_finding "med" "$NO_HASH asset sem hash no path — mudar = bug de cache" "" ""
rm -f "$TMP"

# 4. CORS '*' em CDN assets
TMP=$(mktemp)
rg -n "Access-Control-Allow-Origin.*\*" --type ts --type js --type yaml "${IGNORE[@]}" "${INTEL_GLOBS[@]}" > "$TMP" 2>/dev/null || true
CORS_STAR=$(wc -l < "$TMP" || echo 0)
[ "$CORS_STAR" -gt 0 ] && add_finding "low" "$CORS_STAR CORS:* em assets — anti-hotlink desabilitado" "" ""
rm -f "$TMP"

# 5. preload="auto" em <video> (baixa video todo desnecessário)
PRELOAD_AUTO=$(rg -c "preload=['\"]auto" --type html "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null | wc -l || echo 0)
[ "$PRELOAD_AUTO" -gt 0 ] && add_finding "med" "$PRELOAD_AUTO <video preload=auto> — banda perdida" "" ""

[ "${#FINDINGS[@]}" -gt 0 ] && { emit_result "$BLINDAR_AGENT" "failed" 1; exit 0; }
emit_result "$BLINDAR_AGENT" "passed" 0
