#!/usr/bin/env bash
# Materializa: a11y-executado — acessibilidade MEDIDA, não recomendada.
#
# O `responsive-a11y` é playbook com heurística de grep: acha `<img>` sem alt e
# `outline: none`. Útil, e insuficiente — ele não sabe se o contraste passa, se o
# foco é visível, se o campo tem rótulo associado de verdade. Nenhuma dessas
# coisas é opinião: WCAG 2.2 AA define número.
#
# Duas camadas, e a segunda diz quando não rodou:
#   EXECUTADA  axe-core contra a página no ar (violação de contraste, ARIA,
#              nome acessível, ordem de foco). Precisa de URL e do binário.
#   MEDIDA     razão de contraste calculada a partir do CSS do repositório —
#              par color/background declarado na mesma regra. Não depende de
#              navegador e ainda assim é aritmética, não palpite.
#
# Se nenhuma das duas rodou, o resultado é `skipped` com o motivo. Acessibilidade
# não verificada não é acessibilidade aprovada.
BLINDAR_AGENT="check-a11y-executado"
source "$(dirname "$0")/_lib.sh"
source "$(dirname "$0")/_dyn.sh"
log_section "Check: WCAG AA executado (axe-core + contraste calculado)"

TEM_UI=0
for f in index.html public/index.html src/index.html next.config.js next.config.ts \
         next.config.mjs nuxt.config.ts astro.config.mjs svelte.config.js vite.config.ts; do
  [ -f "$f" ] && TEM_UI=1
done
if [ "$TEM_UI" -eq 0 ] && [ -f "package.json" ]; then
  grep -qE '"(next|nuxt|astro|@sveltejs/kit|react-dom|vue)"' package.json 2>/dev/null && TEM_UI=1
fi
if [ "$TEM_UI" -eq 0 ]; then
  HTML1=$(find . -maxdepth 3 -name '*.html' -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null | head -1)
  [ -n "$HTML1" ] && TEM_UI=1
fi
if [ "$TEM_UI" -eq 0 ]; then
  log_info "projeto sem interface — não se aplica"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

MEDIU=0

# ─── Camada 1: axe-core contra a página no ar ───
dyn_parse_args "$@"
for a in "$@"; do
  case "$a" in --url=*) DYN_URL="${a#--url=}" ;; esac
done
URL=$(dyn_resolve_target || true)

AXE=""
command -v axe >/dev/null 2>&1 && AXE="axe"

if [ -n "$URL" ] && [ -n "$AXE" ]; then
  log_info "axe-core contra $URL ..."
  SAIDA=$(axe "$URL" --stdout --exit 2>/dev/null)
  if [ -z "$SAIDA" ] || ! command -v node >/dev/null 2>&1; then
    log_warn "axe instalado mas sem saída utilizável — NÃO leia como página acessível"
    BLINDAR_MISSING_TOOL="axe:sem-saida"
  else
    export AXE_RAW="$SAIDA"
    while IFS='|' read -r sev regra desc alvo; do
      [ -z "${sev:-}" ] && continue
      add_finding "$sev" "WCAG (axe: $regra) — $desc | elemento: $alvo" "$URL" ""
    done <<EOT
$(node -e '
let d; try { d = JSON.parse(process.env.AXE_RAW); } catch (e) { process.exit(0); }
const runs = Array.isArray(d) ? d : [d];
const lim = (s) => String(s || "").replace(/[\r\n\t|]+/g, " ").slice(0, 150);
const map = { critical: "high", serious: "high", moderate: "med", minor: "low" };
const out = [];
for (const r of runs)
  for (const v of r.violations || [])
    out.push([map[v.impact] || "med", v.id, lim(v.help), lim((v.nodes?.[0]?.target || []).join(" "))]);
for (const l of out.slice(0, 30)) console.log(l.join("|"));
' 2>/dev/null)
EOT
    MEDIU=1
    BLINDAR_EVIDENCE_KIND="dynamic"
    mark_exercised
    log_info "axe-core concluído"
  fi
elif [ -n "$URL" ]; then
  log_warn "URL informada mas 'axe' não está instalado — a camada de navegador NÃO rodou"
  log_warn "instale: npm i -g @axe-core/cli"
  BLINDAR_MISSING_TOOL="axe"
else
  log_info "sem URL alvo — só a camada estática rodou (informe com --url= ou BLINDAR_TARGET_URL)"
  BLINDAR_MISSING_TOOL="alvo-http-ausente"
fi

# ─── Camada 2: contraste calculado a partir do CSS ───
# Aritmética de luminância relativa (WCAG 2.x §1.4.3). Cobre só o par declarado
# na MESMA regra — o que é pouco, e é honesto dizer que é pouco: cor herdada de
# outra regra ou vinda de variável não entra na conta.
CSS=$(find . -maxdepth 4 -name '*.css' -not -path '*/node_modules/*' -not -path '*/.git/*' \
  -not -path '*/dist/*' -not -path '*/build/*' -not -path '*/.next/*' 2>/dev/null | head -20)
if [ -n "$CSS" ] && command -v node >/dev/null 2>&1; then
  MEDIU=1
  while IFS='|' read -r arq razao seletor; do
    [ -z "${arq:-}" ] && continue
    add_finding "med" "Contraste calculado em ${razao}:1 — abaixo do mínimo WCAG AA de 4.5:1 para texto normal (regra: $seletor). O número é aritmética de luminância, não julgamento estético." "$arq" ""
  done <<EOT
$(node -e '
const fs = require("fs");
const arquivos = process.argv.slice(1);
const NOMES = { white:"#ffffff", black:"#000000", red:"#ff0000", lime:"#00ff00", blue:"#0000ff",
  gray:"#808080", grey:"#808080", silver:"#c0c0c0", yellow:"#ffff00", aqua:"#00ffff",
  fuchsia:"#ff00ff", maroon:"#800000", green:"#008000", navy:"#000080", teal:"#008080",
  olive:"#808000", purple:"#800080" };
function rgb(v) {
  v = String(v || "").trim().toLowerCase();
  if (NOMES[v]) v = NOMES[v];
  let m = /^#([0-9a-f]{3})$/.exec(v);
  if (m) return [0,1,2].map(i => parseInt(m[1][i] + m[1][i], 16));
  m = /^#([0-9a-f]{6})$/.exec(v);
  if (m) return [0,2,4].map(i => parseInt(m[1].substr(i,2), 16));
  m = /^rgba?\(\s*(\d+)[\s,]+(\d+)[\s,]+(\d+)/.exec(v);
  if (m) return [1,2,3].map(i => parseInt(m[i], 10));
  return null;
}
const lum = (c) => { const s = c.map(x => { x /= 255; return x <= 0.03928 ? x/12.92 : Math.pow((x+0.055)/1.055, 2.4); });
  return 0.2126*s[0] + 0.7152*s[1] + 0.0722*s[2]; };
for (const f of arquivos) {
  let txt; try { txt = fs.readFileSync(f, "utf8"); } catch (e) { continue; }
  const regras = txt.match(/[^{}]+\{[^{}]*\}/g) || [];
  for (const r of regras) {
    const sel = (r.split("{")[0] || "").replace(/[\r\n\t|]+/g, " ").trim().slice(0, 60);
    const corpo = r.split("{")[1] || "";
    const fg = /(?:^|[;{\s])color\s*:\s*([^;}]+)/i.exec(corpo);
    const bg = /background(?:-color)?\s*:\s*([^;}]+)/i.exec(corpo);
    if (!fg || !bg) continue;
    const a = rgb(fg[1]), b = rgb(bg[1]);
    if (!a || !b) continue;
    const l1 = lum(a), l2 = lum(b);
    const ratio = (Math.max(l1,l2) + 0.05) / (Math.min(l1,l2) + 0.05);
    if (ratio < 4.5) console.log([f, ratio.toFixed(2), sel].join("|"));
  }
}
' $CSS 2>/dev/null | head -15)
EOT
fi

if [ "${#FINDINGS[@]}" -gt 0 ]; then
  case "${FINDINGS[*]}" in
    *'"severity":"high"'*|*'"severity":"crit"'*) emit_result "$BLINDAR_AGENT" "failed" 1; exit 1 ;;
  esac
  emit_result "$BLINDAR_AGENT" "failed" 0
  exit 0
fi

if [ "$MEDIU" -eq 0 ]; then
  log_warn "nem axe nem CSS mensurável — acessibilidade NÃO verificada (não confunda com aprovada)"
  BLINDAR_MISSING_TOOL="${BLINDAR_MISSING_TOOL:+$BLINDAR_MISSING_TOOL,}sem-alvo-mensuravel"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

log_pass "sem violação WCAG AA nas camadas executadas"
emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
