#!/usr/bin/env bash
# Materializa: image-optimization — imagem é quase sempre o maior byte da página.
#
# Três defeitos independentes, todos comuns, todos medíveis no HTML:
#
#   FORMATO   JPEG/PNG onde WebP ou AVIF entregam a mesma imagem com 25–50% dos
#             bytes. Não é micro-otimização: numa landing com seis fotos é a
#             diferença entre 2MB e 700KB.
#   TAMANHO   Sem `srcset`, o celular baixa a versão do desktop e a reduz na
#             tela — paga a banda inteira para exibir um terço.
#   DIMENSÃO  Sem width/height (ou aspect-ratio), o navegador não reserva espaço:
#             a imagem chega, empurra o conteúdo para baixo, e o dedo que estava
#             indo para um botão acerta outro. É CLS, e é o único dos Core Web
#             Vitals que o usuário sente como "esse site é ruim".
BLINDAR_AGENT="check-image-optimization"
source "$(dirname "$0")/_lib.sh"
log_section "Check: imagens (formato moderno, srcset, dimensão explícita)"

ARQUIVOS=$(grep -rIlE '<img[[:space:]]|<Image[[:space:]]|background-image:' \
  --include='*.html' --include='*.htm' --include='*.jsx' --include='*.tsx' \
  --include='*.vue' --include='*.svelte' --include='*.astro' --include='*.css' \
  --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=.blindar \
  --exclude-dir=dist --exclude-dir=build --exclude-dir=.next --exclude-dir=coverage \
  . 2>/dev/null | head -40)

if [ -z "$ARQUIVOS" ]; then
  log_info "projeto não serve imagens em markup — não se aplica"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

# next/image, nuxt-img, astro:assets e afins já resolvem formato, srcset e
# dimensão. Se o projeto usa o componente, o defeito não está aqui.
OTIMIZADOR=$(scan_src 'from .next/image|next/image|<Image[[:space:]]|nuxt-img|NuxtImg|astro:assets|@astrojs/image|gatsby-plugin-image|unpic|@unpic' | head -1)
[ -n "$OTIMIZADOR" ] && log_info "componente de imagem otimizada em uso ($(printf '%s' "$OTIMIZADOR" | cut -d: -f1)) — avaliando só as <img> cruas"

SEM_DIM=0; SEM_SRCSET=0; LEGADO=0
PRIM_DIM=""; PRIM_SRCSET=""; PRIM_LEGADO=""

while IFS=: read -r f ln linha; do
  [ -z "${f:-}" ] && continue
  printf '%s' "$linha" | grep -q '<img' || continue

  printf '%s' "$linha" | grep -qE '(width=|height=|aspect-ratio|className="[^"]*(w-|h-)|style="[^"]*(width|height))' || {
    SEM_DIM=$((SEM_DIM+1)); [ -z "$PRIM_DIM" ] && PRIM_DIM="$f:$ln"; }

  printf '%s' "$linha" | grep -qE '(srcset|srcSet|sizes=)' || {
    SEM_SRCSET=$((SEM_SRCSET+1)); [ -z "$PRIM_SRCSET" ] && PRIM_SRCSET="$f:$ln"; }

  printf '%s' "$linha" | grep -qiE '\.(jpe?g|png)("|'"'"'|\?|[[:space:]])' && {
    printf '%s' "$linha" | grep -qiE '(webp|avif)' || {
      LEGADO=$((LEGADO+1)); [ -z "$PRIM_LEGADO" ] && PRIM_LEGADO="$f:$ln"; }; }
done <<EOT
$(grep -rInE '<img[[:space:]]' \
  --include='*.html' --include='*.htm' --include='*.jsx' --include='*.tsx' \
  --include='*.vue' --include='*.svelte' --include='*.astro' \
  --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=.blindar \
  --exclude-dir=dist --exclude-dir=build --exclude-dir=.next \
  . 2>/dev/null | head -120)
EOT

if [ "$LEGADO" -gt 0 ]; then
  add_finding "low" "$LEGADO imagem(ns) em JPEG/PNG sem alternativa WebP/AVIF — o mesmo pixel em 25–50% dos bytes; sirva com <picture> ou negocie por Accept" \
    "$(printf '%s' "$PRIM_LEGADO" | cut -d: -f1)" "$(printf '%s' "$PRIM_LEGADO" | cut -d: -f2)"
fi
if [ "$SEM_SRCSET" -gt 0 ]; then
  add_finding "low" "$SEM_SRCSET <img> sem srcset/sizes — o celular baixa a versão de desktop inteira e a reduz na tela; paga a banda toda para exibir um terço" \
    "$(printf '%s' "$PRIM_SRCSET" | cut -d: -f1)" "$(printf '%s' "$PRIM_SRCSET" | cut -d: -f2)"
fi
if [ "$SEM_DIM" -gt 0 ]; then
  add_finding "med" "$SEM_DIM <img> sem width/height nem aspect-ratio — o navegador não reserva espaço, a imagem chega e empurra o conteúdo (CLS); o dedo que ia para um botão acerta outro" \
    "$(printf '%s' "$PRIM_DIM" | cut -d: -f1)" "$(printf '%s' "$PRIM_DIM" | cut -d: -f2)"
fi

if [ "${#FINDINGS[@]}" -gt 0 ]; then
  emit_result "$BLINDAR_AGENT" "failed" 0
  exit 0
fi
log_pass "imagens com formato moderno, srcset e dimensão reservada"
emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
