#!/usr/bin/env bash
# check-assumption-probe — a premissa do achado foi MEDIDA antes de virar obra?
#
# O blindar tem product-critic (questiona a premissa do PRODUTO) e
# runtime-adversarial (recusa "li o código e declarei verificado"). Falta o
# passo entre os dois: medir a premissa do próprio achado antes de gastar
# esforço corrigindo-o.
#
# Casos reais que motivaram este check, os dois de uma sessão só:
#   • "sessão em memória não escala" — era DB-backed, já escalava
#   • "TRUST_PROXY /16 é furo"       — já estava mitigado em produção
#
# Nos dois, o achado estava escrito, plausível e errado. Sem medir a premissa,
# o time constrói sobre premissa falsa: o custo não é o bug que ficou, é o
# trabalho inteiro que não precisava existir — e que agora precisa ser mantido.
#
# Formato em .blindar/assumptions.json (schema blindar/assumptions@v1):
#
#   { "schema": "blindar/assumptions@v1",
#     "assumptions": [
#       { "finding_id": "check-horizontal-scale:1",
#         "premise": "a sessao vive em memoria do processo",
#         "measured_how": "SELECT count(*) FROM sessions apos restart do container",
#         "result": "refuted",
#         "at": "2026-08-30T12:00:00Z" } ] }
#
# result aceita: confirmed | refuted | unmeasured
#
# O gate cruza com .blindar/fixes.json: correção construída sobre premissa
# REFUTADA ou NÃO MEDIDA é achado, não conquista.

BLINDAR_AGENT="check-assumption-probe"
STARTED_AT=$(date -u +%s)
source "$(dirname "$0")/_lib.sh"

log_section "Premissa do achado (mediu antes de construir?)"

FIXES="$BLINDAR_DIR/fixes.json"
ASSUMPTIONS="$BLINDAR_DIR/assumptions.json"

require_tool node "leitura dos registros de correção e de premissa"

if [ ! -f "$FIXES" ]; then
  log_warn "Sem $FIXES — não há correções cuja premissa gatear."
  BLINDAR_MISSING_TOOL="registro-de-correcoes"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

REPORT=$(node -e '
  const fs = require("fs");
  const [fixesPath, assumPath] = process.argv.slice(1);
  const read = (p) => { try { return JSON.parse(fs.readFileSync(p, "utf8")); } catch (e) { return null; } };

  const fixes = read(fixesPath);
  if (!fixes) { console.log("ERR|fixes.json ilegivel"); process.exit(0); }
  const list = Array.isArray(fixes) ? fixes : (fixes.fixes || []);
  if (!Array.isArray(list) || list.length === 0) { console.log("EMPTY|"); process.exit(0); }

  const doc = read(assumPath);
  const assumptions = doc ? (Array.isArray(doc) ? doc : (doc.assumptions || [])) : [];
  const byId = new Map();
  for (const a of assumptions) if (a && a.finding_id) byId.set(String(a.finding_id), a);

  console.log("COUNT|" + list.length + "|" + assumptions.length);

  for (const f of list) {
    const id = String(f && (f.finding_id || f.id) || "");
    if (!id) { console.log("high|Correcao sem finding_id: nao da para saber que premissa ela assume"); continue; }
    const a = byId.get(id);
    if (!a) {
      console.log("high|A correcao " + id + " foi construida sem que a premissa do achado fosse medida. O achado pode estar certo — mas ninguem verificou, e trabalho sobre premissa nao medida e a forma mais cara de estar errado");
      continue;
    }
    const r = String(a.result || "").toLowerCase();
    if (r === "refuted") {
      console.log("crit|A correcao " + id + " foi construida sobre uma premissa REFUTADA pela medicao (\"" + (a.premise || "sem premissa declarada") + "\"). O trabalho existe, precisa ser mantido, e resolve um problema que a medicao mostrou nao existir");
      continue;
    }
    if (r !== "confirmed") {
      console.log("high|A premissa de " + id + " esta registrada como \"" + (a.result || "(vazio)") + "\": nao foi confirmada por medicao. Ausencia de medicao nao e confirmacao");
      continue;
    }
    if (!a.measured_how) {
      console.log("med|A premissa de " + id + " diz confirmed mas nao registra measured_how — confirmacao sem metodo nao e reproduzivel nem auditavel");
      continue;
    }
    console.log("ok|" + id);
  }
' "$FIXES" "$ASSUMPTIONS" 2>/dev/null)

if [ -z "$REPORT" ]; then
  log_fail "node não devolveu nada — tratando como erro, não como aprovação."
  BLINDAR_MISSING_TOOL="leitura-dos-registros"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

case "$REPORT" in
  ERR\|*)
    add_finding "high" "$FIXES existe mas não é JSON válido — o gate de premissa não conseguiu ler as correções" "$FIXES" ""
    emit_result "$BLINDAR_AGENT" "failed" 1
    exit 1
    ;;
  EMPTY\|*)
    log_warn "$FIXES sem correções — nada a gatear."
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
    COUNT) log_info "correções: $(echo "$msg" | cut -d'|' -f1) · premissas registradas: $(echo "$msg" | cut -d'|' -f2)" ;;
    ok)    OKN=$((OKN + 1)) ;;
    crit|high) add_finding "$sev" "$msg" "$ASSUMPTIONS" ""; FAIL=1 ;;
    med)   add_finding "med" "$msg" "$ASSUMPTIONS" "" ;;
  esac
done <<EOF
$REPORT
EOF

[ "$OKN" -gt 0 ] && log_pass "$OKN correção(ões) sobre premissa confirmada por medição"

if [ "$FAIL" -eq 1 ]; then
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi
emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
