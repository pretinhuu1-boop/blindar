#!/usr/bin/env bash
# Materializa: seo-marketing-meta — sitemap, robots, JSON-LD, canonical, OG
BLINDAR_AGENT="check-seo-marketing-meta"
source "$(dirname "$0")/_lib.sh"
log_section "Check: SEO + marketing meta (sitemap + JSON-LD + canonical)"

# Roda só em projeto com rotas públicas (não SaaS puro autenticado)
if ! has_dir "public" && ! has_dir "app" && ! has_dir "pages"; then
  emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0
fi

IGNORE=('!node_modules' '!dist' '!**/*.test.*')

# 1. sitemap.xml ausente
if [ ! -f "public/sitemap.xml" ] && [ ! -f "app/sitemap.ts" ] && [ ! -f "pages/sitemap.xml.ts" ]; then
  add_finding "med" "Sem sitemap.xml — Google demora pra descobrir páginas" "" ""
fi

# 2. robots.txt ausente
[ ! -f "public/robots.txt" ] && [ ! -f "app/robots.ts" ] && add_finding "low" "Sem robots.txt — sem política de crawler explícita" "" ""

# 3. metadata.robots = 'noindex' em rota pública (provável erro)
TMP=$(mktemp)
rg -nE "robots:\s*['\"]noindex" --type ts  "${IGNORE[@]}" 2>/dev/null > "$TMP" || true
NOINDEX=$(wc -l < "$TMP" || echo 0)
# Só warn se acharmos noindex fora de /admin /app /dashboard
while IFS=: read -r file line content; do
  [ -z "$file" ] && continue
  if [[ "$file" != *admin* && "$file" != *app/* && "$file" != *dashboard* ]]; then
    add_finding "high" "metadata.robots = 'noindex' em rota pública? $file:$line" "$file" "$line"
  fi
done < "$TMP"
rm -f "$TMP"

# 4. Sem og:image em layout
LAYOUT_FILES=$(find . -maxdepth 4 \( -name "layout.tsx" -o -name "layout.ts" -o -name "_document.tsx" \) -not -path "./node_modules/*" 2>/dev/null | head -3)
OG_FOUND=0
for f in $LAYOUT_FILES; do
  grep -q "og:image\|openGraph" "$f" 2>/dev/null && OG_FOUND=1
done
if [ "$OG_FOUND" -eq 0 ] && [ -n "$LAYOUT_FILES" ]; then
  add_finding "med" "Sem og:image nos layouts — preview em redes sociais quebrado" "" ""
fi

# 5. Title duplicado em todas as páginas (sinal de SEO ruim)
TMP=$(mktemp)
rg -hoE "title:\s*['\"][^'\"]+['\"]" --type ts app/ 2>/dev/null | sort -u > "$TMP" || true
UNIQUE_TITLES=$(wc -l < "$TMP" || echo 0)
ALL_PAGES=$(find app -name "page.tsx" 2>/dev/null | wc -l || echo 0)
if [ "$ALL_PAGES" -gt 5 ] && [ "$UNIQUE_TITLES" -lt 3 ]; then
  add_finding "med" "Possível title duplicado em N páginas ($UNIQUE_TITLES únicos vs $ALL_PAGES rotas)" "" ""
fi
rm -f "$TMP"

# 6. JSON-LD structured data
HAS_JSONLD=$(rg -lE "application/ld\+json" --type ts --type html "${IGNORE[@]}" 2>/dev/null | head -1)
[ -z "$HAS_JSONLD" ] && add_finding "low" "Sem JSON-LD structured data — perde rich snippets" "" ""

emit_result "$BLINDAR_AGENT" "passed" 0
