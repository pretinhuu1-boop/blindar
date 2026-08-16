#!/usr/bin/env bash
# Materializa: seo-foundation — a fundação técnica que decide se o site pode ser
# encontrado. Não é metadado: `check-seo-marketing-meta` já cobre og:image,
# title, JSON-LD e a EXISTÊNCIA de robots/sitemap. Aqui é o que está por baixo —
# o CONTEÚDO do robots, o canonical, a 404 de verdade e a normalização de host.
#
# O achado mais caro é o robots bloqueando CSS/JS. O Google renderiza a página
# como um navegador: sem folha de estilo e sem script ele vê um site quebrado, e
# avalia como tal. Bloquear `/_next/` ou `/assets/` "para economizar crawl" é o
# tiro no pé mais comum de SEO técnico.
BLINDAR_AGENT="check-seo-foundation"
source "$(dirname "$0")/_lib.sh"
log_section "Check: fundação de SEO (robots, canonical, 404, normalização)"

# Só se aplica a coisa que tem página web.
TEM_WEB=0
[ -f "index.html" ] || [ -f "public/index.html" ] && TEM_WEB=1
for f in next.config.js next.config.ts next.config.mjs nuxt.config.ts astro.config.mjs svelte.config.js vite.config.ts; do
  [ -f "$f" ] && TEM_WEB=1
done
if [ "$TEM_WEB" -eq 0 ] && [ -f "package.json" ]; then
  grep -qE '"(next|nuxt|astro|@sveltejs/kit|react-dom|vue)"' package.json 2>/dev/null && TEM_WEB=1
fi
if [ "$TEM_WEB" -eq 0 ]; then
  log_info "sem sinais de site/página web — skipped"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

# Onde o robots pode estar (arquivo estático ou rota gerada).
ROBOTS=""
for f in robots.txt public/robots.txt static/robots.txt src/robots.txt app/robots.ts app/robots.js; do
  [ -f "$f" ] && { ROBOTS="$f"; break; }
done

if [ -n "$ROBOTS" ]; then
  CONTEUDO=$(cat "$ROBOTS" 2>/dev/null)

  # 1. Bloqueio de CSS/JS — o Google precisa renderizar.
  BLOQUEIOS=$(printf '%s\n' "$CONTEUDO" | grep -inE '^[[:space:]]*Disallow:[[:space:]]*/?(\*\.(css|js)|_next|_nuxt|assets|static|build|dist|css|js)/?[[:space:]]*$' | head -4)
  while IFS=: read -r ln txt; do
    [ -z "${ln:-}" ] && continue
    add_finding "high" "robots.txt bloqueia recurso de renderização ($(echo "$txt" | xargs)) — o Google renderiza a página como um navegador; sem CSS e JS ele vê um site quebrado e avalia como tal" "$ROBOTS" "$ln"
  done <<EOF
$BLOQUEIOS
EOF

  # 2. Sem apontar o sitemap.
  printf '%s\n' "$CONTEUDO" | grep -qiE '^[[:space:]]*Sitemap:[[:space:]]*https?://' || \
    add_finding "med" "robots.txt sem diretiva 'Sitemap:' com URL absoluta — o crawler não descobre o mapa do site pelo caminho mais direto" "$ROBOTS" ""
fi

# 3. llms.txt — contexto do negócio para busca generativa. Novo e raro.
LLMS=0
for f in llms.txt public/llms.txt static/llms.txt app/llms.txt; do
  [ -f "$f" ] && { LLMS=1; break; }
done
[ "$LLMS" -eq 0 ] && \
  add_finding "low" "sem llms.txt — motor de busca generativa e assistente extraem o contexto do negócio adivinhando pelo HTML; o arquivo entrega produtos, FAQ e documentação em markdown direto" "llms.txt" ""

# 4. Canonical. Duas formas legítimas: tag literal, ou a metadata API do
#    framework (Next expõe alternates.canonical / metadataBase).
CANONICAL=0
if command -v rg >/dev/null 2>&1; then
  rg -ql '<link[^>]+rel=["'"'"']canonical' -g '!node_modules' 2>/dev/null && CANONICAL=1
  [ "$CANONICAL" -eq 0 ] && rg -ql 'metadataBase|alternates[^)]*canonical|rel:[[:space:]]*["'"'"']canonical' -g '!node_modules' 2>/dev/null && CANONICAL=1
fi
[ "$CANONICAL" -eq 0 ] && \
  add_finding "high" "sem URL canônica declarada — com parâmetro de rastreamento (UTM), filtro ou paginação, a mesma página vira várias URLs e a autoridade se divide entre elas" "" ""

# 5. Página 404 própria, com status real.
P404=0
for f in app/not-found.tsx app/not-found.jsx app/not-found.js pages/404.tsx pages/404.jsx pages/404.js \
         src/pages/404.tsx public/404.html 404.html app/\[...not_found\]/page.tsx error.html; do
  [ -f "$f" ] && { P404=1; break; }
done
[ "$P404" -eq 0 ] && \
  add_finding "med" "sem página 404 própria — o visitante perdido recebe a tela padrão do servidor, sem busca nem caminho de volta, e sai" "" ""

# 6. Normalização de host e barra final. Sem isso, /contato e /contato/ são
#    duas URLs para o mesmo conteúdo, e www e não-www dividem a autoridade.
NORM=0
for f in next.config.js next.config.ts next.config.mjs vercel.json netlify.toml public/_redirects _redirects .htaccess nginx.conf; do
  [ -f "$f" ] || continue
  grep -qiE 'trailingSlash|redirects|RewriteRule|301|permanent' "$f" 2>/dev/null && { NORM=1; break; }
done
[ "$NORM" -eq 0 ] && \
  add_finding "med" "sem normalização de host/barra final — /contato e /contato/ viram duas URLs para o mesmo conteúdo, e www × não-www divide a autoridade entre dois domínios" "" ""

if [ "${#FINDINGS[@]}" -gt 0 ]; then
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi

log_pass "fundação de SEO coberta (robots, canonical, 404, normalização)"
emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
