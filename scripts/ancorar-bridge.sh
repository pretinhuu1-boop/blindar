#!/usr/bin/env bash
# Ponte blindar → ancorar.
#
# O blindar responde "esse código pode ir pro ar?". O ancorar responde "o que
# está no ar está seguro e reversível?". São perguntas diferentes sobre coisas
# diferentes — código e host — e o blindar não tem como responder a segunda:
# firewall ativo, certificado válido, backup fresco, DNS apontando certo e
# vizinho de container saudável só se veem no servidor.
#
# O QUE ESTA PONTE FAZ, E O QUE NÃO FAZ
#
# Faz: emite o plano de deploy, detecta o ancorar, e invoca as fases de LEITURA
# dele (0, 1, 3, 7, 8, 10). Nenhuma delas muta o host.
#
# NÃO faz: invocar fase que muta (2, 4, 5, 6, 9), nem passar ANCORAR_APPLY. Essas
# fases mudam o servidor — provisionam, migram dado, viram tráfego, decommissionam
# — e a decisão de rodá-las é do operador, no ancorar, com a supervisão que o
# ancorar impõe por default. Automatizar isso a partir daqui trocaria o
# "supervisionado + dry-run" dele pelo "auto" daqui, que é o oposto do que cada
# ferramenta escolheu ser.
#
# O blindar também nunca ESCREVE em .ancorar/ — só lê os resultados que o
# ancorar produziu.
#
# Uso:
#   bash scripts/ancorar-bridge.sh --plan-only
#   bash scripts/ancorar-bridge.sh --host meu.servidor.com
#   bash scripts/ancorar-bridge.sh --host X --phases 3,7
#
# Exit: 0 = tudo que rodou passou | 1 = ancorar reportou falha
#       | 3 = ancorar não instalado (plano emitido mesmo assim)
#       | 64 = uso incorreto

set -uo pipefail

BLINDAR_DIR="${BLINDAR_DIR:-.blindar}"
PLANO="$BLINDAR_DIR/deployment-plan.json"
HOST=""
FASES="3,7,8"      # baseline de segurança, verdade de runtime, co-inquilinos
PLAN_ONLY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --host)   HOST="$2"; shift 2 ;;
    --phases) FASES="$2"; shift 2 ;;
    --plan-only) PLAN_ONLY=1; shift ;;
    -h|--help) sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Arg desconhecido: $1" >&2; exit 64 ;;
  esac
done

# ─── Recusa explícita das fases que mutam ───
for f in $(printf '%s' "$FASES" | tr ',' ' '); do
  case "$f" in
    2|4|5|6|9)
      echo "RECUSADO: a fase $f do ancorar MUTA o host (provisiona, migra dado," >&2
      echo "          vira tráfego ou decommissiona)." >&2
      echo "          Esta ponte só invoca fases de leitura. Rode a fase que muta" >&2
      echo "          pelo ancorar, que impõe supervisão e dry-run por default:" >&2
      echo "            ANCORAR_HOST=<host> bash scripts/run.sh $f" >&2
      exit 64 ;;
    0|1|3|7|8|10) : ;;
    *) echo "Fase desconhecida: $f (válidas para leitura: 0,1,3,7,8,10)" >&2; exit 64 ;;
  esac
done

mkdir -p "$BLINDAR_DIR"

# ─── 1. Plano de deploy: estado desejado, sempre emitido ───
ALVO="vps"
[ -d "k8s" ] || [ -d "helm" ] && ALVO="k8s"
[ -f "vercel.json" ] || [ -f "fly.toml" ] || [ -f "render.yaml" ] && ALVO="cloud"
COMPOSE="none"
for c in docker-compose.yml docker-compose.yaml compose.yml; do [ -f "$c" ] && COMPOSE="$c"; done

cat > "$PLANO" <<EOF
{
  "schema": "blindar/deployment-plan@v1",
  "generated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "target": "$ALVO",
  "compose": "$COMPOSE",
  "host": "${HOST:-null}",
  "artefatos": { "compose": "$COMPOSE" },
  "saude": { "smoke": "scripts/smoke-run.sh" },
  "volta": {
    "codigo": "revert para a tag anterior",
    "schema": "requer down migration — ver check-destructive-migration",
    "dado_em_risco": "PREENCHER: o que se perde entre o deploy e o rollback"
  },
  "nota": "Artefato PASSIVO. O blindar declara o estado desejado; quem executa o deploy é o operador, pelo ancorar ou por outro provider."
}
EOF
echo "✓ plano de deploy: $PLANO (alvo=$ALVO)"

[ "$PLAN_ONLY" -eq 1 ] && exit 0

# ─── 2. Localizar o ancorar ───
ANCORAR=""
for d in "${ANCORAR_DIR:-}" "$HOME/.claude/skills/ancorar" "../ancorar" "../../ancorar"; do
  [ -n "${d:-}" ] || continue
  [ -f "$d/scripts/run.sh" ] && { ANCORAR="$d"; break; }
done

if [ -z "$ANCORAR" ]; then
  echo ""
  echo "⚠ ancorar não encontrado — o plano acima foi emitido, mas ninguém verificou o HOST."
  echo "  O blindar cobre o código; firewall ativo, certificado válido, backup fresco,"
  echo "  DNS e vizinhos de container só se veem no servidor, e isso é do ancorar."
  echo ""
  echo "  Instale:  gh repo clone pretinhuu1-boop/ancorar ~/.claude/skills/ancorar"
  echo "  Ou aponte: ANCORAR_DIR=/caminho/para/ancorar bash scripts/ancorar-bridge.sh --host X"
  echo ""
  echo "  Isto NÃO é aprovação do host — é ausência de verificação."
  exit 3
fi
echo "✓ ancorar em: $ANCORAR"

if [ -z "$HOST" ]; then
  echo "⚠ sem --host: nada a verificar no servidor (só o plano foi emitido)."
  exit 0
fi

# ─── 3. Fases de leitura ───
FALHOU=0
for f in $(printf '%s' "$FASES" | tr ',' ' '); do
  echo ""
  echo "── ancorar fase $f (leitura) ──"
  if ANCORAR_HOST="$HOST" bash "$ANCORAR/scripts/run.sh" "$f"; then
    echo "  fase $f ok"
  else
    echo "  fase $f reportou problema"
    FALHOU=1
  fi
done

# ─── 4. Ler o que o ancorar produziu (somente leitura) ───
if [ -d ".ancorar/results" ] && command -v node >/dev/null 2>&1; then
  echo ""
  echo "── resumo do host (lido de .ancorar/results/) ──"
  node -e '
    const fs = require("fs"), path = require("path");
    const dir = ".ancorar/results";
    let ok = 0, falhou = 0, pulou = 0; const ruins = [];
    for (const n of fs.readdirSync(dir).filter(x => x.endsWith(".json"))) {
      let j; try { j = JSON.parse(fs.readFileSync(path.join(dir, n), "utf8")); } catch (e) { continue; }
      if (j.status === "passed") ok++;
      else if (j.status === "failed") { falhou++; ruins.push((j.check || n) + ": " + String(j.message || "").slice(0, 70)); }
      else pulou++;
    }
    console.log("  passou: " + ok + "  falhou: " + falhou + "  pulou: " + pulou);
    // "skipped" no ancorar NÃO é aprovação — é ausência de alvo ou de config.
    if (pulou) console.log("  (pulado != aprovado: sem alvo ou sem config para aquele check)");
    for (const r of ruins.slice(0, 10)) console.log("  ✗ " + r);
  ' || true
fi

exit $FALHOU
