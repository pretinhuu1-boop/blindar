#!/usr/bin/env bash
# Termination calculator: lê .blindar/results/aggregate.json e decide se release está liberada.
# Decisão MATEMÁTICA, não opinião do LLM.
#
# Critério de termination v0.22:
#   - 0 crit confirmados
#   - ≤ 2 high acknowledged (em .accept-risk.md)
#   - Cobertura crítica ≥ 80%
#   - CI verde streak ≥ 3
#
# Exit:
#   0 = termination atingida, release liberada
#   1 = crit aberto (bloqueia)
#   2 = high > 2 sem accept-risk (bloqueia)
#   3 = cobertura insuficiente
#   4 = CI streak insuficiente
#   5 = não deu pra CONTAR (node ausente, ou número ilegível no agregado).
#       Não contar não é contar zero: sem contagem não se libera.

set -euo pipefail

BLINDAR_DIR="${BLINDAR_DIR:-.blindar}"
AGGREGATE="$BLINDAR_DIR/results/aggregate.json"
ACCEPT_RISK="$BLINDAR_DIR/accept-risk.md"

# As contagens abaixo vinham de jq. Sem jq elas viravam string vazia, a
# comparação numérica falhava em silêncio e o script dizia GO independente do
# que existisse — por isso passou a EXIGIR jq e bloquear na ausência.
#
# Bloquear é melhor que aprovar errado, mas continua sendo release barrada por
# ferramenta, não por achado. Numa máquina nova, sem jq, o gate de terminação
# reprovava projeto saudável — e o doctor ainda anunciava que sem jq não se
# perde nada.
#
# Agora lê com node, que é dependência ESSENCIAL do blindar (sem node o
# orquestrador nem resolve o MODULE-MAP). Some o bloqueio espúrio e continua
# valendo a regra que originou tudo: valor ilegível NUNCA vira 0.
if ! command -v node >/dev/null 2>&1; then
  echo "❌ 'node' não está instalado — impossível contar os findings." >&2
  echo "   Sem contagem não há veredito, e ausência de veredito não é" >&2
  echo "   aprovação. Release BLOQUEADA por falta de instrumentação." >&2
  echo "   Instale: https://nodejs.org (>=20)" >&2
  exit 5
fi

# Lê um caminho pontilhado do JSON. Chave ausente → default. Arquivo ilegível
# ou valor não-numérico → ERRO, nunca 0: "não consegui ler" e "não tem nenhum"
# são estados diferentes e só um deles autoriza seguir.
json_num() { # arquivo caminho.pontilhado default
  node -e '
    const fs = require("fs");
    const [arq, caminho, pad] = process.argv.slice(1);
    let v;
    try {
      v = caminho.split(".").reduce((o, k) => (o == null ? undefined : o[k]),
                                    JSON.parse(fs.readFileSync(arq, "utf8")));
    } catch (e) { process.stderr.write("ilegivel"); process.exit(3); }
    if (v === undefined || v === null) { process.stdout.write(pad); process.exit(0); }
    if (typeof v !== "number" || !Number.isFinite(v)) { process.exit(3); }
    process.stdout.write(String(v));
  ' "$1" "$2" "${3:-0}" 2>/dev/null
}

if [ ! -f "$AGGREGATE" ]; then
  echo "❌ $AGGREGATE não encontrado. Rode: bash scripts/blindar/run-all.sh primeiro." >&2
  exit 1
fi

# Critérios configuráveis
MAX_CRIT="${MAX_CRIT:-0}"
MAX_HIGH_ACCEPTED="${MAX_HIGH_ACCEPTED:-2}"
MIN_COVERAGE_PCT="${MIN_COVERAGE_PCT:-80}"
MIN_CI_GREEN_STREAK="${MIN_CI_GREEN_STREAK:-3}"

CRITS=$(json_num "$AGGREGATE" findings_by_severity.crit 0) || CRITS=""
HIGHS=$(json_num "$AGGREGATE" findings_by_severity.high 0) || HIGHS=""
MEDS=$(json_num  "$AGGREGATE" findings_by_severity.med  0) || MEDS=""
LOWS=$(json_num  "$AGGREGATE" findings_by_severity.low  0) || LOWS=""

# O motivo de tudo isto: vazio comparado numericamente não falha alto, passa.
for _par in "crit:$CRITS" "high:$HIGHS" "med:$MEDS" "low:$LOWS"; do
  case "${_par#*:}" in
    ''|*[!0-9]*)
      echo "❌ contagem de ${_par%%:*} ilegível em $AGGREGATE." >&2
      echo "   Não é zero achado: é achado não contado. NO-GO." >&2
      exit 5 ;;
  esac
done
unset _par

# Conta highs em accept-risk
HIGH_ACCEPTED=0
if [ -f "$ACCEPT_RISK" ]; then
  # grep -c sai 1 quando a contagem é 0. Sob `set -e` (linha 19) isso aborta o
  # gate inteiro no caso comum — accept-risk.md existe (o instalador o cria) sem
  # nenhum high marcado [x] — com exit 1, que o próprio contrato deste script lê
  # como "CRIT aberto". Um portão de release que morre assim é o pior modo de
  # falha de uma ferramenta de auditoria. `|| true` mantém a contagem (o grep já
  # imprimiu "0") sem deixar o errexit matar o gate; guarda numérica defensiva.
  HIGH_ACCEPTED=$(grep -c "^- \[x\].*high" "$ACCEPT_RISK" 2>/dev/null || true)
  [[ "$HIGH_ACCEPTED" =~ ^[0-9]+$ ]] || HIGH_ACCEPTED=0
fi
HIGH_UNACCEPTED=$((HIGHS - HIGH_ACCEPTED))

echo "═══ blindar termination check ═══"
echo ""
echo "  Crits abertos          : $CRITS  (max permitido: $MAX_CRIT)"
echo "  Highs total            : $HIGHS"
echo "  Highs em accept-risk   : $HIGH_ACCEPTED"
echo "  Highs sem accept-risk  : $HIGH_UNACCEPTED  (max permitido: $MAX_HIGH_ACCEPTED)"
echo "  Meds                   : $MEDS"
echo "  Lows                   : $LOWS"
echo ""

EXIT_CODE=0

if [ "$CRITS" -gt "$MAX_CRIT" ]; then
  echo "❌ CRIT aberto — release BLOQUEADA"
  EXIT_CODE=1
fi

if [ "$HIGH_UNACCEPTED" -gt "$MAX_HIGH_ACCEPTED" ]; then
  echo "❌ Highs sem accept-risk > $MAX_HIGH_ACCEPTED — release BLOQUEADA"
  echo "   Aceite os highs em $ACCEPT_RISK com checkbox marcado [x]"
  [ "$EXIT_CODE" -eq 0 ] && EXIT_CODE=2
fi

# Coverage check (se disponível)
if [ -f "coverage/coverage-summary.json" ]; then
  COVERAGE=$(json_num coverage/coverage-summary.json total.statements.pct) || COVERAGE=""
  if [ -z "$COVERAGE" ]; then
    # O arquivo existe e não deu pra ler. Antes isto caía em `bc` sem valor:
    # `(( ))` vazio é erro de sintaxe e, sob `set -e`, matava o script no meio —
    # sem veredito e sem dizer por quê. Arquivo de cobertura ilegível é cobertura
    # NÃO VERIFICADA, que bloqueia igual a cobertura baixa.
    echo "❌ coverage-summary.json existe mas é ilegível — cobertura NÃO VERIFICADA"
    echo "   Não verificado não é aprovado. Release BLOQUEADA."
    [ "$EXIT_CODE" -eq 0 ] && EXIT_CODE=3
  else
    # Comparação em node, não em bc: bc não existe por padrão no Windows e o
    # `2>/dev/null` escondia isso — a comparação virava vazia e o teste sumia.
    if node -e 'process.exit(Number(process.argv[1]) < Number(process.argv[2]) ? 0 : 1)' \
         "$COVERAGE" "$MIN_COVERAGE_PCT" 2>/dev/null; then
      echo "❌ Coverage $COVERAGE% < $MIN_COVERAGE_PCT% — release BLOQUEADA"
      [ "$EXIT_CODE" -eq 0 ] && EXIT_CODE=3
    fi
  fi
else
  echo "⚠  coverage-summary.json não encontrado (rode npm run test:coverage)"
fi

# CI green streak (lê última N runs via gh CLI)
if command -v gh >/dev/null 2>&1; then
  STREAK=$(gh run list --limit 5 --json conclusion --jq '[.[] | select(.conclusion == "success")] | length' 2>/dev/null || echo 0)
  if [ "$STREAK" -lt "$MIN_CI_GREEN_STREAK" ]; then
    echo "❌ CI green streak $STREAK < $MIN_CI_GREEN_STREAK — release BLOQUEADA"
    [ "$EXIT_CODE" -eq 0 ] && EXIT_CODE=4
  else
    echo "✅ CI green streak: $STREAK"
  fi
fi

if [ "$EXIT_CODE" -eq 0 ]; then
  echo ""
  echo "✅ ✅ ✅  TERMINATION ATINGIDA — release LIBERADA  ✅ ✅ ✅"
fi

exit $EXIT_CODE
