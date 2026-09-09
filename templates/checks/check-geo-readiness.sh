#!/usr/bin/env bash
# Materializa: geo-readiness — GEO, Generative Engine Optimization.
#
# Não é SEO com outro nome. SEO clássico disputa POSIÇÃO numa lista de dez links;
# GEO disputa ser CITADO dentro de uma resposta que o usuário lê sem clicar em
# nada. São mecânicas diferentes: o motor generativo não ranqueia a página, ele
# extrai um fato dela e credita a fonte. O que decide não é backlink nem
# densidade de palavra-chave — é o fato estar declarado de forma extraível, no
# HTML do servidor, com identidade e data.
#
# Complementa (não duplica) `seo-marketing-meta` e `seo-foundation`: lá são
# metadados e fundação de indexação. Aqui é prontidão para citação.
#
# AUTO-SKIP É A REGRA. A maioria dos projetos que o blindar audita não tem
# superfície pública de conteúdo — API, CLI, backend de bot e painel interno não
# têm o que ser citado, e cobrar GEO deles é ruído.
BLINDAR_AGENT="check-geo-readiness"
source "$(dirname "$0")/_lib.sh"
log_section "Check: prontidão para citação por motor generativo (GEO)"

# ─── Existe superfície pública de conteúdo? ───
SUPERFICIE=""
for f in astro.config.mjs astro.config.ts docusaurus.config.js docusaurus.config.ts \
         config.toml hugo.toml hugo.yaml _config.yml theme.config.tsx \
         .vitepress/config.ts .vitepress/config.js gatsby-config.js; do
  [ -f "$f" ] && { SUPERFICIE="SSG de conteúdo ($f)"; break; }
done
if [ -z "$SUPERFICIE" ]; then
  # `docs/` NÃO entra nesta lista de propósito. Praticamente todo projeto tem um
  # `docs/` de documentação interna, e contá-lo como superfície pública fazia o
  # check disparar num backend de bot — medido no FastList, que ganhou quatro
  # achados de GEO sem ter uma única página a ser citada. Documentação publicada
  # de verdade aparece pelo SSG (Docusaurus, VitePress, Nextra, mkdocs), que já
  # é detectado acima.
  for d in content posts blog _posts src/content src/posts; do
    [ -d "$d" ] || continue
    N=$(find "$d" -name '*.md' -o -name '*.mdx' 2>/dev/null | head -3 | grep -c . )
    [ "${N:-0}" -ge 2 ] && { SUPERFICIE="diretório de conteúdo ($d, $N+ artigos)"; break; }
  done
fi
# Páginas de conteúdo: HTML com meta description E prosa de verdade. Os dois
# critérios juntos separam landing e página de preços — públicas, feitas para
# serem lidas e citadas — de shell de aplicação. Medido no FastList: o
# `gestor.html` tem 372 mil caracteres de markup de painel e nenhuma meta
# description; a `landing.html` tem 5,5 mil de prosa e uma.
PAGINAS_CONTEUDO=""
while IFS= read -r h; do
  [ -z "$h" ] && continue
  grep -qiE '<meta[^>]+name=["'"'"']description' "$h" 2>/dev/null || continue
  CHARS=$(sed -e 's/<script[^>]*>.*<\/script>//g' -e 's/<[^>]*>//g' "$h" 2>/dev/null \
    | tr -d '[:space:]' | wc -c | tr -d '[:space:]')
  case "$CHARS" in ''|*[!0-9]*) CHARS=0 ;; esac
  [ "$CHARS" -ge 1200 ] || continue
  PAGINAS_CONTEUDO="$PAGINAS_CONTEUDO $h"
  [ -z "$SUPERFICIE" ] && SUPERFICIE="página pública de conteúdo ($h, ~${CHARS} caracteres de texto)"
done <<EOT
$(find . -maxdepth 3 -name '*.html' -not -path '*/node_modules/*' -not -path '*/.git/*' \
  -not -path '*/dist/*' -not -path '*/build/*' -not -path '*/coverage/*' 2>/dev/null | head -25)
EOT

if [ -z "$SUPERFICIE" ]; then
  log_info "sem superfície pública de conteúdo a ser citada por motor generativo"
  log_info "(API, CLI, backend de bot e painel interno não têm o que ser citado — GEO não se aplica)"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi
log_info "superfície pública detectada: $SUPERFICIE"

# Os achados apontam para a página de CONTEÚDO, não para o primeiro .html que o
# find devolver — achado de GEO em cima do shell da aplicação manda quem lê
# corrigir o arquivo errado.
PAGINAS=$(printf '%s\n' $PAGINAS_CONTEUDO | grep -v '^$')
if [ -z "$PAGINAS" ]; then
  PAGINAS=$(find . -maxdepth 4 -name '*.html' -not -path '*/node_modules/*' -not -path '*/.git/*' \
    -not -path '*/coverage/*' -not -path '*/.blindar/*' 2>/dev/null | head -15)
fi

# ─── 1. Dados estruturados: o fato que o motor extrai ───
# JSON-LD schema.org é o formato que os motores leem sem adivinhar. Sem ele, o
# motor infere do HTML — e infere errado, ou não cita.
JSONLD=$(grep -rIlE 'application/ld\+json|schema\.org|jsonLd|JsonLd|@context' \
  --include='*.html' --include='*.tsx' --include='*.jsx' --include='*.astro' \
  --include='*.vue' --include='*.svelte' --include='*.ts' --include='*.js' \
  --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=dist --exclude-dir=build \
  . 2>/dev/null | head -3)
if [ -z "$JSONLD" ]; then
  ALVO=$(printf '%s\n' "$PAGINAS" | head -1)
  add_finding "high" \
    "Página de conteúdo com ZERO dados estruturados JSON-LD (schema.org). É o bloco que o motor generativo extrai como fato citável — sem ele, ChatGPT, Perplexity, AI Overviews e Claude precisam inferir do HTML, e inferem errado ou não citam. Declare Organization e, conforme o caso, Product, FAQPage ou Article." \
    "${ALVO:-index.html}" ""
else
  log_pass "dados estruturados presentes ($(printf '%s\n' "$JSONLD" | head -1))"
fi

# ─── 2. Política de crawler de IA ───
# roster de crawlers de IA — revisar trimestralmente, últ.: 2026-09
# Dois tiers, tratados de forma DIFERENTE. Bloquear crawler de treino é decisão
# legítima do operador; bloquear crawler de RESPOSTA é auto-de-indexação.
TIER_RESPOSTA='GPTBot|OAI-SearchBot|ChatGPT-User|Google-Extended|Googlebot|ClaudeBot|Claude-SearchBot|Claude-User|anthropic-ai|PerplexityBot|Perplexity-User|bingbot|Meta-ExternalAgent'
TIER_TREINO='CCBot|Bytespider|Amazonbot|Applebot-Extended|cohere-ai|cohere-training-data-crawler|MistralAI-User|YouBot|DuckAssistBot|Diffbot|AI2Bot|PetalBot|omgili|omgilibot'

ROBOTS=""
for f in robots.txt public/robots.txt static/robots.txt src/robots.txt app/robots.ts app/robots.js; do
  [ -f "$f" ] && { ROBOTS="$f"; break; }
done

if [ -z "$ROBOTS" ]; then
  add_finding "med" \
    "Sem robots.txt — a postura diante dos crawlers de IA está indefinida por omissão. Decida: quer ser citado (libere o tier de resposta) ou não (bloqueie explicitamente). Omissão deixa a decisão com o crawler." \
    "robots.txt" ""
else
  BLOQ_RESP=""
  BLOQ_TREINO=""
  MENCIONA=0
  UA_ATUAL=""
  LN=0
  while IFS= read -r linha; do
    LN=$((LN+1))
    L=$(printf '%s' "$linha" | tr -d '\r')
    case "$L" in
      [Uu]ser-agent:*|[Uu]ser-Agent:*)
        UA=$(printf '%s' "$L" | sed -E 's/^[Uu]ser-[Aa]gent:[[:space:]]*//' | tr -d '[:space:]')
        UA_ATUAL="$UA"
        printf '%s' "$UA" | grep -qiE "^($TIER_RESPOSTA|$TIER_TREINO)$" && MENCIONA=1
        ;;
      [Dd]isallow:*)
        VAL=$(printf '%s' "$L" | sed -E 's/^[Dd]isallow:[[:space:]]*//' | tr -d '[:space:]')
        [ "$VAL" = "/" ] || continue
        printf '%s' "$UA_ATUAL" | grep -qiE "^($TIER_RESPOSTA)$" && BLOQ_RESP="$BLOQ_RESP $UA_ATUAL:$LN"
        printf '%s' "$UA_ATUAL" | grep -qiE "^($TIER_TREINO)$" && BLOQ_TREINO="$BLOQ_TREINO $UA_ATUAL"
        ;;
    esac
  done < "$ROBOTS"

  if [ -n "$BLOQ_RESP" ]; then
    PRIM=$(printf '%s' "$BLOQ_RESP" | tr ' ' '\n' | grep -v '^$' | head -1)
    NOMES_RESP=$(trim_ws "$(printf '%s' "$BLOQ_RESP" | sed 's/:[0-9]*//g')")
    add_finding "high" \
      "robots.txt bloqueia crawler do tier RESPOSTA ($NOMES_RESP) — estes são os que geram citação e tráfego (OpenAI, Google AI Overviews, Anthropic, Perplexity, Copilot via Bing). Bloqueá-los é auto-de-indexação dos motores generativos, e costuma ser acidente de copiar-e-colar, não decisão." \
      "$ROBOTS" "$(printf '%s' "$PRIM" | sed 's/^[^:]*://')"
  fi
  if [ -n "$BLOQ_TREINO" ]; then
    log_info "postura do tier TREINO: BLOQUEADO ($(printf '%s' "$BLOQ_TREINO" | sed 's/^ *//')) — escolha legítima do operador (licenciamento, banda), não defeito"
  fi
  if [ "$MENCIONA" -eq 0 ]; then
    add_finding "med" \
      "robots.txt não menciona NENHUM crawler de IA — postura indefinida. Decida se quer ser citado por motor generativo e escreva a decisão; o roster deste check foi revisado em 2026-09 e user-agent fora dele é 'não classificado', nunca 'aprovado'." \
      "$ROBOTS" ""
  else
    log_pass "robots.txt trata crawlers de IA de forma intencional"
  fi
fi

# llms.txt: convenção emergente para entregar o contexto do negócio em markdown.
LLMS=0
for f in llms.txt public/llms.txt static/llms.txt app/llms.txt llms-full.txt; do
  [ -f "$f" ] && { LLMS=1; break; }
done
[ "$LLMS" -eq 0 ] && add_finding "low" \
  "Sem llms.txt — o motor generativo monta o contexto do negócio adivinhando pelo HTML; o arquivo entrega produtos, preços, FAQ e documentação em markdown direto" "llms.txt" ""

# ─── 3. O fato está no HTML do servidor? ───
# Boa parte dos crawlers de IA não executa JavaScript. Conteúdo injetado só no
# cliente simplesmente não existe para eles.
SPA_VAZIA=""
for p in $PAGINAS; do
  [ -f "$p" ] || continue
  TEXTO=$(sed -e 's/<script[^>]*>.*<\/script>//g' -e 's/<[^>]*>//g' "$p" 2>/dev/null | tr -d '[:space:]' | wc -c | tr -d '[:space:]')
  TEM_ROOT=$(grep -cE '<div[^>]+id=["'"'"'](root|app|__next)["'"'"']' "$p" 2>/dev/null || echo 0)
  if [ "${TEM_ROOT:-0}" -gt 0 ] && [ "${TEXTO:-0}" -lt 400 ]; then
    SPA_VAZIA="$p"
    break
  fi
done
if [ -n "$SPA_VAZIA" ]; then
  add_finding "high" \
    "O HTML servido está praticamente vazio (contêiner de montagem + script): o conteúdo é renderizado só no cliente. Boa parte dos crawlers de IA não executa JavaScript — para eles a página não tem fato nenhum a citar. Renderize no servidor o que precisa ser citado." \
    "$SPA_VAZIA" ""
else
  # Sem SSR/SSG declarado num projeto de framework cliente é o mesmo risco, um
  # grau abaixo, porque não deu para confirmar no HTML.
  if [ -f "package.json" ] && grep -qE '"(react-dom|vue)"' package.json 2>/dev/null; then
    grep -qE '"(next|nuxt|astro|@sveltejs/kit|gatsby|remix|react-dom/server)"' package.json 2>/dev/null || \
      add_finding "med" "Framework de cliente sem SSR/SSG (Next, Nuxt, Astro, SvelteKit, Remix) — se o conteúdo citável for montado no navegador, o crawler de IA não o vê" "package.json" ""
  fi
fi

# ─── 4. Respostas extraíveis ───
# Motor generativo cita frase auto-contida, não slogan. "A melhor solução do
# mercado" não é citável; "O prazo de devolução é de 30 dias corridos" é.
EXTRAIVEL=$(grep -rIlEi '(FAQPage|<h[23][^>]*>[^<]*(o que [eé]|como |quanto |quando |por que|qual )|<details|itemscope[^>]*Question|perguntas frequentes|frequently asked)' \
  --include='*.html' --include='*.md' --include='*.mdx' --include='*.tsx' --include='*.astro' \
  --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=dist --exclude-dir=build \
  . 2>/dev/null | head -2)
if [ -z "$EXTRAIVEL" ]; then
  add_finding "med" \
    "Conteúdo sem bloco diretamente respondível (FAQ, seção 'o que é / como funciona', schema FAQPage). Motor generativo cita frase auto-contida com um fato dentro; copy de marketing sem afirmação verificável não dá o que citar." \
    "$(printf '%s\n' "$PAGINAS" | head -1)" ""
else
  log_pass "conteúdo com blocos respondíveis ($(printf '%s\n' "$EXTRAIVEL" | head -1))"
fi

# ─── 5. E-E-A-T e frescor ───
# Quem afirma, quando afirmou, e de onde. Sem isso o motor tem o fato e não tem
# a quem creditar — e prefere citar quem tem.
FALTA=""
grep -rqIiE '(datePublished|dateModified|<time[[:space:]]|article:published_time|"date":)' \
  --include='*.html' --include='*.md' --include='*.mdx' --include='*.tsx' --include='*.astro' \
  --exclude-dir=node_modules --exclude-dir=.git . 2>/dev/null || FALTA="$FALTA data"
grep -rqIiE '(author|autor|byline|"Person"|rel=["'"'"']author)' \
  --include='*.html' --include='*.md' --include='*.mdx' --include='*.tsx' --include='*.astro' \
  --exclude-dir=node_modules --exclude-dir=.git . 2>/dev/null || FALTA="$FALTA autoria"
grep -rqIiE '(rel=["'"'"']canonical|alternates[^)]*canonical|metadataBase)' \
  --include='*.html' --include='*.tsx' --include='*.astro' --include='*.js' --include='*.ts' \
  --exclude-dir=node_modules --exclude-dir=.git . 2>/dev/null || FALTA="$FALTA canonical"
grep -rqIiE '(og:title|og:description|openGraph)' \
  --include='*.html' --include='*.tsx' --include='*.astro' --include='*.js' --include='*.ts' \
  --exclude-dir=node_modules --exclude-dir=.git . 2>/dev/null || FALTA="$FALTA open-graph"

if [ -n "$FALTA" ]; then
  add_finding "med" \
    "Sinais de E-E-A-T e frescor ausentes em página de conteúdo:$FALTA. O motor generativo credita quem consegue identificar e datar; sem isso ele usa o fato e cita outra fonte." \
    "$(printf '%s\n' "$PAGINAS" | head -1)" ""
fi

if [ "${#FINDINGS[@]}" -gt 0 ]; then
  case "${FINDINGS[*]}" in
    *'"severity":"high"'*|*'"severity":"crit"'*) emit_result "$BLINDAR_AGENT" "failed" 1; exit 1 ;;
  esac
  emit_result "$BLINDAR_AGENT" "failed" 0
  exit 0
fi

log_pass "conteúdo pronto para ser extraído e citado por motor generativo"
emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
