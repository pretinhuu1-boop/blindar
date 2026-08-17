#!/usr/bin/env bash
# blindar monitor — o que está rodando agora, e há quanto tempo.
#
# Existe porque as coisas demoradas deste projeto não dizem onde estão. O gate
# leva ~45 minutos e só imprime no fim; um run completo passa de 10; o semgrep
# em container some por um minuto sem sinal. Sem isso, a única forma de saber se
# algo travou ou só está lento é abrir arquivo de log na mão — e "travou" e
# "lento" se parecem exatamente igual até você medir.
#
# Não mede nada por conta própria: lê o que os processos já escrevem. Monitor
# que inventa número seria mais uma coisa para não confiar.
#
# Uso:
#   bash scripts/monitor.sh              # uma foto
#   bash scripts/monitor.sh --watch      # atualiza a cada 10s até Ctrl-C
#   bash scripts/monitor.sh --watch 30   # a cada 30s

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  R=$'\e[31m'; G=$'\e[32m'; Y=$'\e[33m'; B=$'\e[1m'; D=$'\e[2m'; RST=$'\e[0m'
else R=''; G=''; Y=''; B=''; D=''; RST=''; fi

INTERVALO=0
case "${1:-}" in
  --watch) INTERVALO="${2:-10}" ;;
  -h|--help) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac

# Mostra a HORA da última escrita, não uma idade calculada.
#
# A primeira versão subtraía epochs e chegou a exibir "há 357m" para um arquivo
# tocado 18 segundos antes. Não vale caçar a causa: um monitor existe para você
# confiar no que lê, e relógio de parede não tem aritmética para errar. Você
# compara com o seu próprio relógio e sabe na hora se travou.
ultima_escrita() { # arquivo → "15:54:14"
  [ -f "$1" ] || return 0
  stat -c %y "$1" 2>/dev/null | cut -c12-19 && return 0
  stat -f %Sm -t '%H:%M:%S' "$1" 2>/dev/null   # macOS
}

secao() { printf '\n%s── %s ──%s\n' "$B" "$1" "$RST"; }

uma_foto() {
  printf '%s═══ blindar monitor — %s ═══%s\n' "$B" "$(date +%H:%M:%S)" "$RST"

  # ─── Run em andamento no projeto atual ───
  # O orquestrador escreve `.blindar/.run-lines.log` linha a linha; é a fonte
  # mais fiel de progresso que existe, porque é a mesma que ele usa.
  secao "run neste projeto"
  local dir="${BLINDAR_DIR:-.blindar}"
  if [ -f "$dir/.run.lock" ]; then
    local pid; pid=$(head -1 "$dir/.run.lock" 2>/dev/null | tr -d ' \r')
    local vivo="não responde"
    kill -0 "$pid" 2>/dev/null && vivo="${G}vivo${RST}"
    printf '  lock: PID %s (%s)\n' "${pid:-?}" "$vivo"
  else
    printf '  %ssem run em andamento aqui%s\n' "$D" "$RST"
  fi
  if [ -d "$dir/results" ]; then
    local n; n=$(find "$dir/results" -name '*.json' 2>/dev/null | wc -l | tr -d ' ')
    local ult; ult=$(find "$dir/results" -name '*.json' -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
    printf '  results: %s arquivo(s)' "$n"
    [ -n "${ult:-}" ] && printf ' — último %s %s(%s)%s' "$(basename "${ult%.json}")" "$D" "$(ultima_escrita "$ult")" "$RST"
    printf '\n'
    # Estado agregado sem depender do relatório final: conta direto dos results.
    if [ "$n" -gt 0 ] && command -v node >/dev/null 2>&1; then
      node -e '
        const fs = require("fs"), path = require("path");
        const d = process.argv[1];
        const c = { passed: 0, failed: 0, skipped: 0, errored: 0 };
        for (const f of fs.readdirSync(d).filter(x => x.endsWith(".json"))) {
          try { const j = JSON.parse(fs.readFileSync(path.join(d, f), "utf8"));
                if (j.status in c) c[j.status]++; } catch {}
        }
        console.log(`  passed ${c.passed} · failed ${c.failed} · skipped ${c.skipped} · errored ${c.errored}`);
      ' "$dir/results" 2>/dev/null
    fi
  fi

  # ─── Gate / testes rodando em segundo plano ───
  secao "gate e testes"
  local achou=0
  # BLINDAR_GATE_LOG aponta direto; sem ele, procura nos lugares onde o log
  # costuma cair. Busca em profundidade só até 3 níveis: varrer /tmp inteiro num
  # monitor que roda a cada 10s seria pior que não ter monitor.
  local candidatos=()
  [ -n "${BLINDAR_GATE_LOG:-}" ] && candidatos+=("$BLINDAR_GATE_LOG")
  while IFS= read -r c; do candidatos+=("$c"); done < <(
    find "${TMPDIR:-/tmp}" -maxdepth 3 -name 'gate*.txt' -newermt '-6 hours' 2>/dev/null | head -5
    ls ./gate*.txt 2>/dev/null
  )
  for f in "${candidatos[@]}"; do
    [ -f "$f" ] || continue
    achou=1
    local ok fail total
    # `grep -c` sai com 1 quando a conta dá zero. Então `|| echo 0` ANEXA um
    # segundo zero, e a variável fica com dois números em linhas separadas — o
    # que quebra toda comparação numérica depois, com um erro que fala de
    # "integer expression" e não de grep. `|| true` preserva a saída do grep,
    # que já é o zero certo.
    #
    # E `^✓ check-` em vez de `^✓`: a linha final "todos os pares registrados
    # corretos" também começa com ✓, e contava como par. Dava 81/80.
    ok=$(grep -c '^✓ check-' "$f" 2>/dev/null || true); ok=${ok:-0}
    fail=$(grep -c '^✗' "$f" 2>/dev/null || true); fail=${fail:-0}
    total=$(grep -c '^  "check-' "$SKILL_DIR/scripts/check-selftest.sh" 2>/dev/null || true)
    total=${total:-0}
    local cor="$G"; [ "$fail" -gt 0 ] && cor="$R"
    printf '  %s  %s%s/%s pares%s' "$(basename "$f")" "$cor" "$ok" "$total" "$RST"
    [ "$fail" -gt 0 ] && printf ' %s(%s falha)%s' "$R" "$fail" "$RST"
    grep -q 'RESUMO' "$f" 2>/dev/null && printf ' %sterminado%s' "$D" "$RST" \
      || printf ' %s— última escrita %s%s' "$D" "$(ultima_escrita "$f")" "$RST"
    printf '\n'
    [ "$fail" -gt 0 ] && grep '^✗' "$f" 2>/dev/null | head -3 | sed 's/^/      /'
  done
  [ "$achou" -eq 0 ] && printf '  %snenhum gate rodando%s\n' "$D" "$RST"

  # ─── Containers ───
  # O fallback do semgrep e a verificação em Linux sobem container. Sem isto,
  # "o check está travado" e "o container está baixando 150 MB" são o mesmo
  # silêncio na tela.
  secao "containers"
  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    # Só o que é do blindar. Numa máquina de trabalho há dezenas de containers
    # de outros projetos, e listar todos afoga o sinal que este painel existe
    # para mostrar.
    local meus; meus=$(docker ps --format '  {{.Image}}  {{.Status}}' 2>/dev/null \
      | grep -E 'semgrep|node:.*bookworm|trivy|gitleaks' || true)
    local total; total=$(docker ps -q 2>/dev/null | wc -l | tr -d ' ')
    if [ -n "$meus" ]; then printf '%s\n' "$meus"
    else printf '  %snenhum do blindar%s\n' "$D" "$RST"; fi
    printf '  %s(%s container(s) no total nesta máquina)%s\n' "$D" "$total" "$RST"
  else
    printf '  %sdocker não responde%s\n' "$D" "$RST"
  fi

  # ─── Processos do blindar ───
  secao "processos"
  local procs
  procs=$(ps -ef 2>/dev/null | grep -E 'check-|blindar-run|semgrep|gitleaks|trivy|osv-scanner' \
          | grep -v grep | grep -v monitor.sh | head -8)
  if [ -n "$procs" ]; then
    printf '%s\n' "$procs" | awk '{ cmd=""; for (i=8; i<=NF; i++) cmd = cmd $i " ";
                                     printf "  %-8s %s\n", $2, substr(cmd, 1, 88) }'
  else
    printf '  %snenhum check em execução%s\n' "$D" "$RST"
  fi
}

if [ "$INTERVALO" = "0" ]; then
  uma_foto
else
  # `clear` a cada ciclo: o terminal vira painel em vez de fita de log.
  while true; do
    clear 2>/dev/null || true
    uma_foto
    printf '\n%satualizando a cada %ss — Ctrl-C para sair%s\n' "$D" "$INTERVALO" "$RST"
    sleep "$INTERVALO"
  done
fi
