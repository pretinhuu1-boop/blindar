#!/usr/bin/env bash
# Materializa: frontend-perf-budget — orçamento de bytes EXECUTADO, não sugerido.
#
# "Otimizar o front" é conselho; não é medida. Orçamento é medida: um número por
# página, comparado a cada rodada, que estoura ou não estoura. Sem ele, o peso
# cresce da forma como sempre cresce — ninguém adiciona 300KB de uma vez, cada
# um adiciona 20KB e o total ninguém olha.
#
# Duas camadas:
#   ESTÁTICA  — mede o que está no disco: HTML servido e bundle JS, em gzip.
#               Roda em qualquer máquina, sem rede, sem navegador.
#   DINÂMICA  — Lighthouse contra uma URL real (LCP/TBT/CLS), quando o binário
#               existe e a URL é informada. Quando não, cai para a estática e
#               DIZ que caiu, com missing_tool preenchido.
#
# Orçamentos (KB gzipped, ajustáveis):
#   BLINDAR_PERF_PAGE_KB  (default 400)  documento HTML servido
#   BLINDAR_PERF_JS_KB    (default 400)  JS total por diretório de build
BLINDAR_AGENT="check-frontend-perf-budget"
source "$(dirname "$0")/_lib.sh"
source "$(dirname "$0")/_dyn.sh"
log_section "Check: orçamento de performance de front (bytes medidos)"

# ─── Orçamento: default do projeto, sobrescrito pelo do repositório, e este
#     sobrescrito pelo do ambiente. Orçamento que não se pode apertar não é
#     orçamento — cada produto tem o seu (LP de marketing e painel interno não
#     têm o mesmo teto). O default é o do CLAUDE.md: 400KB gzipped.
ORC_PAGE_KB=400
ORC_JS_KB=400
if [ -f "package.json" ] && command -v node >/dev/null 2>&1; then
  CFG=$(node -e '
try {
  const p = require("./package.json").blindar || {};
  console.log((p.perfBudgetPageKb ?? "") + " " + (p.perfBudgetJsKb ?? ""));
} catch (e) { console.log(" "); }' 2>/dev/null)
  P=$(printf '%s' "$CFG" | awk '{print $1}')
  J=$(printf '%s' "$CFG" | awk '{print $2}')
  case "$P" in ''|*[!0-9]*) ;; *) ORC_PAGE_KB="$P" ;; esac
  case "$J" in ''|*[!0-9]*) ;; *) ORC_JS_KB="$J" ;; esac
fi
ORC_PAGE_KB="${BLINDAR_PERF_PAGE_KB:-$ORC_PAGE_KB}"
ORC_JS_KB="${BLINDAR_PERF_JS_KB:-$ORC_JS_KB}"

TEM_WEB=0
for f in index.html public/index.html src/index.html next.config.js next.config.ts \
         next.config.mjs nuxt.config.ts astro.config.mjs svelte.config.js vite.config.ts; do
  [ -f "$f" ] && TEM_WEB=1
done
if [ "$TEM_WEB" -eq 0 ] && [ -f "package.json" ]; then
  grep -qE '"(next|nuxt|astro|@sveltejs/kit|react-dom|vue|vite)"' package.json 2>/dev/null && TEM_WEB=1
fi
if [ "$TEM_WEB" -eq 0 ]; then
  HTMLS=$(find . -maxdepth 3 -name '*.html' -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null | head -1)
  [ -n "$HTMLS" ] && TEM_WEB=1
fi
if [ "$TEM_WEB" -eq 0 ]; then
  log_info "projeto não serve HTML nem usa framework de front — orçamento de página não se aplica"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

# ─── Medidor: bytes em gzip ───
# Sem gzip a conta é sobre bytes crus, que superestimam o custo de rede. Isso
# muda o significado da medida, então fica registrado como buraco de cobertura.
MODO="gzip"
if ! command -v gzip >/dev/null 2>&1; then
  MODO="cru"
  log_warn "gzip ausente — medindo bytes CRUS; o número não é comparável ao que trafega"
  BLINDAR_MISSING_TOOL="gzip"
fi
tamanho_kb() { # arquivo → KB (inteiro)
  local f="$1" b
  if [ "$MODO" = "gzip" ]; then
    b=$(gzip -9 -c "$f" 2>/dev/null | wc -c | tr -d '[:space:]')
  else
    b=$(wc -c < "$f" 2>/dev/null | tr -d '[:space:]')
  fi
  [ -z "$b" ] && b=0
  echo $(( b / 1024 ))
}

MEDIU=0

# ─── 1. Documento HTML servido ───
# Procura primeiro na saída de build; se não houver, no fonte — o caso do HTML
# monolítico servido direto é justamente o que estoura orçamento.
DIRS_HTML=""
for d in dist build out public .output/public _site; do
  [ -d "$d" ] && DIRS_HTML="$DIRS_HTML $d"
done
[ -z "$DIRS_HTML" ] && DIRS_HTML="."

while IFS= read -r html; do
  [ -z "$html" ] && continue
  KB=$(tamanho_kb "$html")
  MEDIU=1
  SCRIPTS=$(grep -oc '<script' "$html" 2>/dev/null || echo 0)
  log_info "$(printf '%-52s %5s KB %s' "$html" "$KB" "$MODO")"
  if [ "$KB" -gt $(( ORC_PAGE_KB * 2 )) ]; then
    add_finding "high" "Documento HTML com ${KB}KB ${MODO} — mais que o DOBRO do orçamento de ${ORC_PAGE_KB}KB. Em 4G isso é o usuário olhando tela branca enquanto o parser trabalha; quebre em chunks carregados sob demanda." "$html" ""
  elif [ "$KB" -gt "$ORC_PAGE_KB" ]; then
    add_finding "med" "Documento HTML com ${KB}KB ${MODO} — acima do orçamento de ${ORC_PAGE_KB}KB" "$html" ""
  fi
  if [ "${SCRIPTS:-0}" -gt 25 ]; then
    add_finding "low" "Página com ${SCRIPTS} tags <script> — cada uma é uma requisição e um ponto de bloqueio de parsing" "$html" ""
  fi
done <<EOT
$(find $DIRS_HTML -maxdepth 4 -name '*.html' \
  -not -path '*/node_modules/*' -not -path '*/.git/*' -not -path '*/coverage/*' \
  2>/dev/null | head -12)
EOT

# ─── 2. JS total por diretório de build ───
for d in dist build out .next/static .output/public/_nuxt; do
  [ -d "$d" ] || continue
  TOTAL=0
  N=0
  while IFS= read -r js; do
    [ -z "$js" ] && continue
    TOTAL=$(( TOTAL + $(tamanho_kb "$js") ))
    N=$(( N + 1 ))
  done <<EOT
$(find "$d" -name '*.js' -not -path '*/node_modules/*' 2>/dev/null | head -200)
EOT
  [ "$N" -eq 0 ] && continue
  MEDIU=1
  log_info "$(printf '%-52s %5s KB %s (%s arquivos)' "$d (JS)" "$TOTAL" "$MODO" "$N")"
  if [ "$TOTAL" -gt $(( ORC_JS_KB * 2 )) ]; then
    add_finding "high" "JS de $d soma ${TOTAL}KB ${MODO} em $N arquivos — mais que o dobro do orçamento de ${ORC_JS_KB}KB. Todo esse byte é baixado, parseado e executado na thread principal antes da página responder ao toque." "$d" ""
  elif [ "$TOTAL" -gt "$ORC_JS_KB" ]; then
    add_finding "med" "JS de $d soma ${TOTAL}KB ${MODO} — acima do orçamento de ${ORC_JS_KB}KB" "$d" ""
  fi
done

# ─── 3. Camada dinâmica: Lighthouse contra URL real ───
dyn_parse_args "$@"
for a in "$@"; do
  case "$a" in --url=*) DYN_URL="${a#--url=}" ;; esac
done
URL=$(dyn_resolve_target || true)

if [ -n "$URL" ] && command -v lighthouse >/dev/null 2>&1; then
  log_info "Lighthouse contra $URL ..."
  LH=$(lighthouse "$URL" --quiet --chrome-flags="--headless --no-sandbox" \
        --only-categories=performance --output=json --output-path=stdout 2>/dev/null)
  if [ -z "$LH" ] || ! command -v node >/dev/null 2>&1; then
    log_warn "lighthouse instalado mas não produziu relatório utilizável — NÃO leia como aprovado"
    BLINDAR_MISSING_TOOL="${BLINDAR_MISSING_TOOL:+$BLINDAR_MISSING_TOOL,}lighthouse:sem-saida"
  else
    export LH_RAW="$LH"
    while IFS='|' read -r sev msg; do
      [ -z "${sev:-}" ] && continue
      add_finding "$sev" "$msg" "$URL" ""
    done <<EOT
$(node -e '
const d = JSON.parse(process.env.LH_RAW || "{}");
const a = d.audits || {};
const n = (k) => (a[k] && typeof a[k].numericValue === "number") ? a[k].numericValue : null;
const out = [];
const lcp = n("largest-contentful-paint"), tbt = n("total-blocking-time"), cls = n("cumulative-layout-shift");
if (lcp !== null && lcp > 4000) out.push(["high", `LCP medido em ${Math.round(lcp)}ms (SLO: 2500ms) — o maior elemento da tela demora ${(lcp/1000).toFixed(1)}s para aparecer`]);
else if (lcp !== null && lcp > 2500) out.push(["med", `LCP medido em ${Math.round(lcp)}ms (SLO: 2500ms)`]);
if (tbt !== null && tbt > 600) out.push(["high", `TBT medido em ${Math.round(tbt)}ms (SLO: 200ms) — a thread principal fica bloqueada e o toque do usuario nao responde`]);
else if (tbt !== null && tbt > 200) out.push(["med", `TBT medido em ${Math.round(tbt)}ms (SLO: 200ms)`]);
if (cls !== null && cls > 0.25) out.push(["high", `CLS medido em ${cls.toFixed(3)} (SLO: 0.1) — o layout salta e o usuario clica no que nao queria`]);
else if (cls !== null && cls > 0.1) out.push(["med", `CLS medido em ${cls.toFixed(3)} (SLO: 0.1)`]);
for (const l of out) console.log(l.join("|"));
' 2>/dev/null)
EOT
    MEDIU=1
    BLINDAR_EVIDENCE_KIND="dynamic"
    mark_exercised
    log_info "Lighthouse concluído"
  fi
elif [ -n "$URL" ]; then
  log_warn "URL informada mas 'lighthouse' não está instalado — só o orçamento estático de bytes foi medido"
  log_warn "instale: npm i -g lighthouse   (Core Web Vitals reais exigem navegador)"
  BLINDAR_MISSING_TOOL="${BLINDAR_MISSING_TOOL:+$BLINDAR_MISSING_TOOL,}lighthouse"
else
  log_info "sem URL alvo — só o orçamento estático de bytes foi medido (informe com --url= ou BLINDAR_TARGET_URL)"
fi

if [ "${#FINDINGS[@]}" -gt 0 ]; then
  case "${FINDINGS[*]}" in
    *'"severity":"high"'*|*'"severity":"crit"'*) emit_result "$BLINDAR_AGENT" "failed" 1; exit 1 ;;
  esac
  emit_result "$BLINDAR_AGENT" "failed" 0
  exit 0
fi

# Nada medido = nada sabido. Não é aprovação.
if [ "$MEDIU" -eq 0 ]; then
  log_warn "nenhum artefato mensurável (HTML servido ou bundle de build) — rode o build antes"
  BLINDAR_MISSING_TOOL="${BLINDAR_MISSING_TOOL:+$BLINDAR_MISSING_TOOL,}build-ausente"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

log_pass "dentro do orçamento (página ≤ ${ORC_PAGE_KB}KB, JS ≤ ${ORC_JS_KB}KB, $MODO)"
emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
