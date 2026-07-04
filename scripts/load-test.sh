#!/usr/bin/env bash
# blindar load-test — escalabilidade como GATE. Dispara N requests com C de
# concorrência contra um alvo (homolog) e falha se erro% ou p95 estourarem o SLO.
# "Muitos usuários chamando sem travar" vira número, não achismo.
#
# Uso: bash scripts/load-test.sh --url URL [--requests 200] [--concurrency 20]
#                                [--slo-error-pct 1] [--slo-p95-ms 800]
# Exit 0 = dentro do SLO. Exit 1 = estourou (erro% ou p95). skip se sem curl/url.

BLINDAR_AGENT="check-load-test"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../templates/checks/_lib.sh"
log_section "Load-test (escalabilidade — erro% + p95 vs SLO)"

URL=""; N=200; C=20; SLO_ERR=1; SLO_P95=800
while [ $# -gt 0 ]; do
  case "$1" in
    --url) URL="$2"; shift 2 ;;
    --requests) N="$2"; shift 2 ;;
    --concurrency) C="$2"; shift 2 ;;
    --slo-error-pct) SLO_ERR="$2"; shift 2 ;;
    --slo-p95-ms) SLO_P95="$2"; shift 2 ;;
    *) shift ;;
  esac
done

[ -z "$URL" ] && { log_warn "sem --url — load-test skipped"; emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0; }
command -v curl >/dev/null 2>&1 || { emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0; }
command -v node >/dev/null 2>&1 || { emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0; }

log_info "Disparando $N requests, concorrência $C, alvo $URL (SLO: erro<${SLO_ERR}% p95<${SLO_P95}ms)"
TMP=$(mktemp)
# N linhas com a URL → xargs -P C dispara em paralelo; grava "status time_total"
if command -v seq >/dev/null 2>&1; then SEQ=$(seq "$N"); else SEQ=$(awk "BEGIN{for(i=0;i<$N;i++)print i}"); fi
echo "$SEQ" | sed "s#.*#$URL#" | xargs -P "$C" -I{} curl -s -o /dev/null -w "%{http_code} %{time_total}\n" --max-time 20 {} > "$TMP" 2>/dev/null

RESULT=$(node -e '
  const fs=require("fs");
  const lines=fs.readFileSync(process.argv[1],"utf8").trim().split("\n").filter(Boolean);
  const times=[]; let errors=0, total=lines.length;
  for(const l of lines){ const [code,t]=l.split(" "); const c=parseInt(code,10);
    if(!(c>=200&&c<400)) errors++; times.push(parseFloat(t)*1000||0); }
  times.sort((a,b)=>a-b);
  const p95=times.length?times[Math.min(times.length-1,Math.floor(times.length*0.95))]:0;
  const errPct=total?(errors*100/total):100;
  console.log(JSON.stringify({total,errors,errPct:+errPct.toFixed(2),p95:Math.round(p95)}));
' "$TMP")
rm -f "$TMP"

TOTAL=$(echo "$RESULT" | node -e "process.stdout.write(String(JSON.parse(require('fs').readFileSync(0)).total))")
ERRPCT=$(echo "$RESULT" | node -e "process.stdout.write(String(JSON.parse(require('fs').readFileSync(0)).errPct))")
P95=$(echo "$RESULT" | node -e "process.stdout.write(String(JSON.parse(require('fs').readFileSync(0)).p95))")
log_info "resultado: total=$TOTAL erro=${ERRPCT}% p95=${P95}ms"

FAIL=0
if node -e "process.exit(($ERRPCT > $SLO_ERR)?0:1)"; then
  add_finding "high" "erro% ${ERRPCT}% acima do SLO ${SLO_ERR}% sob carga ($C concorrentes) — não escala/trava sob usuários simultâneos" "" ""; FAIL=1
fi
if [ "$P95" -gt "$SLO_P95" ]; then
  add_finding "high" "p95 ${P95}ms acima do SLO ${SLO_P95}ms sob carga — experiência degrada com muitos usuários" "" ""; FAIL=1
fi

if [ "$FAIL" -eq 1 ]; then emit_result "$BLINDAR_AGENT" "failed" 1; exit 1; fi
emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
