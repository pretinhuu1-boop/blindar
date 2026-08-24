#!/usr/bin/env bash
# Ponte blindar → Sentinela.
#
# O blindar prova que o CÓDIGO é seguro e que a app SOBE. O Sentinela prova que
# a app RODANDO e LOGADA é segura — ele abre um browser real, o operador faz o
# login (passa 2FA/SSO/CAPTCHA), e audita a sessão autenticada por dentro:
# storage, cookies, tokens, headers e APIs que só existem depois do login. É a
# verdade de runtime que nenhuma análise de código alcança.
#
# O QUE ESTA PONTE FAZ, E O QUE NÃO FAZ
#
# Faz: detecta o Sentinela, mostra o comando de auditoria, e INGERE o SARIF que
# ele produz para dentro de .blindar/results/ — onde o gate lê, o report conta e
# o `reproduzir` explica.
#
# NÃO faz: fazer login por você nem digitar credencial. O login é do operador,
# no browser do Sentinela. Esta ponte nunca vê senha. Também não roda a auditoria
# sozinha por default (ela é interativa) — com --run ela lança o Sentinela e é
# você quem dirige o browser.
#
# Uso:
#   bash scripts/sentinela-bridge.sh --check                 # detecta e valida
#   bash scripts/sentinela-bridge.sh --url https://app --run # lança a auditoria (você loga)
#   bash scripts/sentinela-bridge.sh --ingest [arquivo.sarif]# traz o SARIF pro blindar
#
# Exit: 0 = ok / limpo | 1 = Sentinela reportou achado crit/high
#       | 3 = Sentinela não instalado | 64 = uso incorreto

set -uo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BLINDAR_DIR="${BLINDAR_DIR:-.blindar}"
URL=""
MODE="check"
RUN=0
SARIF_ARG=""

while [ $# -gt 0 ]; do
  case "$1" in
    --check)  MODE="check"; shift ;;
    --url)    URL="$2"; MODE="url"; shift 2 ;;
    --run)    RUN=1; shift ;;
    --ingest) MODE="ingest"; shift; case "${1:-}" in --*|"") ;; *) SARIF_ARG="$1"; shift ;; esac ;;
    -h|--help) sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Arg desconhecido: $1" >&2; exit 64 ;;
  esac
done

# ─── Detecta o Sentinela ───
SENT=""
for d in "${SENTINELA_DIR:-}" "$HOME/.claude/skills/sentinela" "../Sentinela" "../../Sentinela" "$SKILL_DIR/../Sentinela"; do
  [ -n "$d" ] && [ -f "$d/sentinela.mjs" ] && { SENT="$(cd "$d" && pwd)"; break; }
done

if [ -z "$SENT" ]; then
  echo "⚠ Sentinela não encontrado — a verdade de runtime (app logada) NÃO foi verificada."
  echo "  Isto não é 'seguro': é medição que não aconteceu."
  echo "  Instale/aponte:  SENTINELA_DIR=/caminho/para/Sentinela bash scripts/sentinela-bridge.sh --check"
  echo "  Repo:            git clone https://github.com/maykonlong/sentinela.git"
  exit 3
fi
echo "✓ Sentinela: $SENT"

command -v node >/dev/null 2>&1 || { echo "node ausente — necessário para o Sentinela e o ingest." >&2; exit 3; }

# ─── Modo: check (detecta e valida, não audita) ───
if [ "$MODE" = "check" ]; then
  [ -f "$SENT/package.json" ] && echo "✓ package.json presente" || echo "⚠ sem package.json em $SENT"
  [ -f "$SENT/src/report/sarif-export.mjs" ] && echo "✓ exportação SARIF disponível" || echo "⚠ sem sarif-export — o ingest precisa do SARIF"
  echo ""
  echo "Para auditar a app logada:"
  echo "  bash scripts/sentinela-bridge.sh --url https://sua-app --run   # você faz o login no browser"
  echo "  bash scripts/sentinela-bridge.sh --ingest                       # depois, traz o SARIF pro blindar"
  exit 0
fi

# ─── Modo: url (mostra/roda a auditoria — o operador dirige o browser) ───
if [ "$MODE" = "url" ]; then
  [ -z "$URL" ] && { echo "sem --url" >&2; exit 64; }
  echo "Comando de auditoria (o login é seu, no browser do Sentinela):"
  echo "  ( cd \"$SENT\" && node sentinela.mjs start --url \"$URL\" )"
  if [ "$RUN" -eq 1 ]; then
    echo ""
    echo "── lançando Sentinela (dirija o browser; ele audita em segundo plano) ──"
    ( cd "$SENT" && node sentinela.mjs start --url "$URL" )
    RC=$?
    echo "Sentinela saiu com rc=$RC. Agora rode:  bash scripts/sentinela-bridge.sh --ingest"
    exit "$RC"
  fi
  echo ""
  echo "Rode com --run para lançar, ou depois:  bash scripts/sentinela-bridge.sh --ingest"
  exit 0
fi

# ─── Modo: ingest (SARIF do Sentinela → .blindar/results/sentinela.json) ───
if [ "$MODE" = "ingest" ]; then
  SARIF="$SARIF_ARG"
  if [ -z "$SARIF" ]; then
    # acha o .sarif mais recente em reports/ do Sentinela ou local
    for dir in "$SENT/reports" "./reports" "$BLINDAR_DIR"; do
      [ -d "$dir" ] || continue
      cand=$(ls -t "$dir"/*.sarif 2>/dev/null | head -1)
      [ -n "$cand" ] && { SARIF="$cand"; break; }
    done
  fi
  if [ -z "$SARIF" ] || [ ! -f "$SARIF" ]; then
    echo "⚠ nenhum .sarif encontrado (rode a auditoria com --url ... --run antes, ou passe o arquivo)."
    echo "  isto NÃO é 'sem achado': é ingest sem entrada."
    exit 3
  fi
  echo "✓ ingerindo: $SARIF"
  mkdir -p "$BLINDAR_DIR/results"
  node "$SKILL_DIR/scripts/sentinela-ingest.mjs" "$SARIF" --out "$BLINDAR_DIR/results/sentinela.json"
  RC=$?
  echo "  → use  node scripts/blindar-report.mjs reproduzir  para os passos de confirmação."
  exit "$RC"
fi
