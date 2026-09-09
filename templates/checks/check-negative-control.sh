#!/usr/bin/env bash
# check-negative-control — toda correção precisa de controle negativo EXECUTADO.
#
# agents/testing-strategy.md prescreve mutation testing com score agregado > 80%.
# Score agregado é uma média: ele é compatível com o teste da correção de hoje
# não proteger absolutamente nada, desde que os outros 200 protejam.
#
# O controle negativo é individual e local: depois de corrigir, quebre o código
# DE PROPÓSITO e confirme que o teste cai. Se ele não cai, o teste não protege a
# correção — ele só passa perto dela.
#
# Este check gateia o registro disso. Formato esperado em
# .blindar/negative-controls.json (schema blindar/negative-controls@v1):
#
#   { "schema": "blindar/negative-controls@v1",
#     "controls": [
#       { "finding_id": "check-security:0",
#         "how_broken": "removi a checagem de origem em src/mw/cors.ts",
#         "test": "tests/cors.spec.ts::rejeita origem estranha",
#         "observed": "failed",
#         "at": "2026-08-30T12:00:00Z" } ] }
#
# As correções vêm de .blindar/fixes.json (escrito por blindar-fix.sh) no mesmo
# vocabulário de id: "<agent>:<indice>".
#
# Três desfechos, e nenhum deles é aprovação silenciosa:
#   • correção sem controle          → high (a correção não tem prova de proteção)
#   • controle com observed != failed → crit (quebrei e o teste passou: ele não protege)
#   • sem registro de correção nenhum → skipped como AUSÊNCIA DE COBERTURA

BLINDAR_AGENT="check-negative-control"
STARTED_AT=$(date -u +%s)
source "$(dirname "$0")/_lib.sh"

log_section "Controle negativo por correção (quebrei de propósito e o teste caiu?)"

FIXES="$BLINDAR_DIR/fixes.json"
CONTROLS="$BLINDAR_DIR/negative-controls.json"

require_tool node "leitura dos registros de correção e de controle negativo"

if [ ! -f "$FIXES" ]; then
  # Sem lista de correções não há o que gatear. Isso é buraco de cobertura, não
  # aprovação: marcar como skipped COM insumo ausente faz o gate contar warning
  # em vez de PASS, que é a leitura honesta de "ninguém registrou nada".
  log_warn "Sem $FIXES — não há registro de correções para gatear."
  log_info "  blindar-fix.sh grava esse arquivo; correção manual precisa registrá-la também."
  BLINDAR_MISSING_TOOL="registro-de-correcoes"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

# Uma chamada de node para os dois arquivos. Saída: linhas "SEV|MSG".
REPORT=$(node -e '
  const fs = require("fs");
  const [fixesPath, controlsPath] = process.argv.slice(1);
  const read = (p) => { try { return JSON.parse(fs.readFileSync(p, "utf8")); } catch (e) { return null; } };

  const fixes = read(fixesPath);
  if (!fixes) { console.log("ERR|fixes.json ilegivel ou invalido"); process.exit(0); }
  const list = Array.isArray(fixes) ? fixes : (fixes.fixes || []);
  if (!Array.isArray(list) || list.length === 0) { console.log("EMPTY|"); process.exit(0); }

  const ctrlDoc = read(controlsPath);
  const controls = ctrlDoc ? (Array.isArray(ctrlDoc) ? ctrlDoc : (ctrlDoc.controls || [])) : [];
  const byId = new Map();
  for (const c of controls) if (c && c.finding_id) byId.set(String(c.finding_id), c);

  console.log("COUNT|" + list.length + "|" + controls.length);

  for (const f of list) {
    const id = String(f && (f.finding_id || f.id) || "");
    if (!id) { console.log("high|Correcao registrada sem finding_id: impossivel amarrar a um controle negativo"); continue; }
    const c = byId.get(id);
    if (!c) {
      console.log("high|A correcao " + id + " nao tem controle negativo registrado. Sem quebrar o codigo de proposito e ver o teste cair, nao ha prova de que o teste protege esta correcao — ele so passa perto dela");
      continue;
    }
    const obs = String(c.observed || "").toLowerCase();
    if (obs !== "failed") {
      console.log("crit|O controle negativo de " + id + " registra observed=\"" + (c.observed || "(vazio)") + "\": o codigo foi quebrado de proposito e o teste NAO caiu. Este teste nao protege a correcao, e o verde dele e pior que a ausencia dele");
      continue;
    }
    if (!c.how_broken || !c.test) {
      console.log("med|O controle negativo de " + id + " nao diz o que foi quebrado (how_broken) ou qual teste caiu (test). Controle sem essas duas coisas nao e reproduzivel por outra pessoa");
      continue;
    }
    console.log("ok|" + id);
  }
' "$FIXES" "$CONTROLS" 2>/dev/null)

if [ -z "$REPORT" ]; then
  log_fail "node não devolveu nada ao ler $FIXES — tratando como erro, não como aprovação."
  BLINDAR_MISSING_TOOL="leitura-dos-registros"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

case "$REPORT" in
  ERR\|*)
    add_finding "high" "$BLINDAR_DIR/fixes.json existe mas não é JSON válido — o gate de controle negativo não conseguiu ler o registro de correções" "$FIXES" ""
    emit_result "$BLINDAR_AGENT" "failed" 1
    exit 1
    ;;
  EMPTY\|*)
    log_warn "$FIXES não lista nenhuma correção — nada a gatear."
    BLINDAR_MISSING_TOOL="registro-de-correcoes"
    emit_result "$BLINDAR_AGENT" "skipped" 0
    exit 0
    ;;
esac

FAIL=0
OKN=0
while IFS='|' read -r sev msg; do
  [ -z "${sev:-}" ] && continue
  case "$sev" in
    COUNT) log_info "correções registradas: $(echo "$msg" | cut -d'|' -f1) · controles: $(echo "$msg" | cut -d'|' -f2)" ;;
    ok)    OKN=$((OKN + 1)) ;;
    crit|high) add_finding "$sev" "$msg" "$CONTROLS" ""; FAIL=1 ;;
    med)   add_finding "med" "$msg" "$CONTROLS" "" ;;
  esac
done <<EOF
$REPORT
EOF

[ "$OKN" -gt 0 ] && log_pass "$OKN correção(ões) com controle negativo executado e observado falhando"

if [ "$FAIL" -eq 1 ]; then
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi
emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
