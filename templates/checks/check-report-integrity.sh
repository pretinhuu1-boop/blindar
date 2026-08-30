#!/usr/bin/env bash
# check-report-integrity — o laudo se corrige quando a medição o contradiz?
#
# agents/decision-log.md e agents/execution-report.md REGISTRAM. Nenhum dos dois
# se auto-corrige. Sem isso, a primeira versão do laudo vira fonte de verdade e
# a correção nunca alcança quem já leu — o relatório fica mais confiável do que
# a medição que o desmente, que é exatamente a inversão errada.
#
# O gate é sobre histórico, não sobre uma foto:
#   .blindar/report.json            — versão corrente (schema blindar/report@v1)
#   .blindar/report-history/*.json  — versões anteriores, uma por arquivo
#
#   { "schema": "blindar/report@v1",
#     "version": 2,
#     "supersedes": 1,
#     "claims": [ { "agent": "check-horizontal-scale", "status": "passed" } ],
#     "corrections": [
#       { "agent": "check-horizontal-scale", "was": "failed", "now": "passed",
#         "why": "a medicao mostrou sessao DB-backed; a afirmacao anterior estava errada" } ] }
#
# Regra: toda afirmação que MUDOU de status entre a versão anterior e a atual
# precisa aparecer em corrections com o motivo. Status que vira o contrário em
# silêncio é o laudo se editando sem dizer que se editou.

BLINDAR_AGENT="check-report-integrity"
STARTED_AT=$(date -u +%s)
source "$(dirname "$0")/_lib.sh"

log_section "Integridade do relatório (versionado e auto-corretivo)"

REPORT="$BLINDAR_DIR/report.json"
HISTORY="$BLINDAR_DIR/report-history"

require_tool node "leitura do relatório versionado e do histórico"

if [ ! -f "$REPORT" ]; then
  log_warn "Sem $REPORT — não há laudo versionado para gatear."
  log_info "  A fase 07 deve gravá-lo; sem ele, correções de laudo não são rastreáveis."
  BLINDAR_MISSING_TOOL="relatorio-versionado"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

REPORT_OUT=$(node -e '
  const fs = require("fs"), path = require("path");
  const [reportPath, histDir] = process.argv.slice(1);
  const read = (p) => { try { return JSON.parse(fs.readFileSync(p, "utf8")); } catch (e) { return null; } };

  const cur = read(reportPath);
  if (!cur) { console.log("ERR|report.json ilegivel ou invalido"); process.exit(0); }

  if (typeof cur.version !== "number") {
    console.log("high|O relatorio nao declara version numerico. Sem versao nao ha como saber qual laudo alguem leu, nem o que mudou desde entao");
  }

  let prev = null;
  try {
    const files = fs.readdirSync(histDir).filter((f) => f.endsWith(".json")).sort();
    if (files.length) {
      const cands = files.map((f) => read(path.join(histDir, f))).filter(Boolean)
        .filter((r) => typeof r.version === "number" && r.version < (cur.version || Infinity))
        .sort((a, b) => b.version - a.version);
      prev = cands[0] || null;
    }
  } catch (e) { /* sem historico: primeira versao */ }

  if (!prev) { console.log("FIRST|"); process.exit(0); }

  if (cur.supersedes !== prev.version) {
    console.log("med|O relatorio v" + cur.version + " nao declara supersedes=" + prev.version + ": a cadeia entre versoes fica quebrada e nao da para reconstruir o que cada leitor viu");
  }

  const claimMap = (r) => {
    const m = new Map();
    for (const c of (r.claims || [])) if (c && c.agent) m.set(String(c.agent), String(c.status || ""));
    return m;
  };
  const before = claimMap(prev), now = claimMap(cur);
  const corrected = new Set((cur.corrections || []).map((c) => String(c && c.agent || "")));

  let mudou = 0;
  for (const [agent, was] of before) {
    const is = now.get(agent);
    if (is === undefined || is === was) continue;
    mudou++;
    if (!corrected.has(agent)) {
      console.log("high|A afirmacao sobre \"" + agent + "\" mudou de \"" + was + "\" para \"" + is + "\" entre v" + prev.version + " e v" + cur.version + " sem entrada em corrections. Quem leu a versao anterior continua com a afirmacao errada, e nada no laudo atual avisa que ela caiu");
    }
  }
  for (const c of (cur.corrections || [])) {
    if (c && c.agent && !c.why) {
      console.log("med|A correcao sobre \"" + c.agent + "\" nao diz por que (campo why). Correcao sem motivo nao permite ao leitor decidir se a nova afirmacao e mais confiavel que a antiga");
    }
  }
  console.log("COUNT|" + before.size + "|" + mudou + "|" + corrected.size);
' "$REPORT" "$HISTORY" 2>/dev/null)

if [ -z "$REPORT_OUT" ]; then
  log_fail "node não devolveu nada ao ler $REPORT — tratando como erro, não como aprovação."
  BLINDAR_MISSING_TOOL="leitura-do-relatorio"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

case "$REPORT_OUT" in
  ERR\|*)
    add_finding "high" "$REPORT existe mas não é JSON válido — o laudo não é auditável" "$REPORT" ""
    emit_result "$BLINDAR_AGENT" "failed" 1
    exit 1
    ;;
esac

FAIL=0
while IFS='|' read -r sev msg extra1 extra2; do
  [ -z "${sev:-}" ] && continue
  case "$sev" in
    FIRST) log_pass "Primeira versão do laudo — sem histórico a contradizer" ;;
    COUNT) log_info "afirmações na versão anterior: $msg · mudaram: $extra1 · correções declaradas: $extra2" ;;
    crit|high) add_finding "$sev" "$msg" "$REPORT" ""; FAIL=1 ;;
    med)   add_finding "med" "$msg" "$REPORT" "" ;;
  esac
done <<EOF
$REPORT_OUT
EOF

if [ "$FAIL" -eq 1 ]; then
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi
emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
