#!/usr/bin/env bash
# blindar doctor — a MÁQUINA tem o que o blindar precisa?
#
# Diferente do preflight.sh, que valida o projeto-alvo. Este valida o ambiente.
#
# Existe porque a ausência de ferramenta é SILENCIOSA no lugar errado: sem
# ripgrep, dezenas de checks emitem `skipped` e o relatório mostra cobertura
# alta — o operador nunca sabe que metade não olhou nada. Numa máquina nova
# isso é o modo de falha mais provável, e o mais difícil de perceber.
#
# Por isso cada ausência aqui diz O QUE SE PERDE, não só "faltando".
#
# Uso:  bash scripts/doctor.sh
# Exit: 0 = tudo essencial presente | 1 = falta algo essencial

set -uo pipefail

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  R=$'\e[31m'; G=$'\e[32m'; Y=$'\e[33m'; B=$'\e[1m'; RST=$'\e[0m'
else R=''; G=''; Y=''; B=''; RST=''; fi

FALTA_ESSENCIAL=0
DEGRADADO=0

linha() { # simbolo cor nome versao perda
  printf '%s%s%s  %-12s %-22s %s\n' "$2" "$1" "$RST" "$3" "$4" "$5"
}

verifica() { # nome nivel comando_versao o_que_se_perde como_instalar
  local nome="$1" nivel="$2" vcmd="$3" perda="$4" instala="$5"
  if command -v "$nome" >/dev/null 2>&1; then
    local v; v=$(eval "$vcmd" 2>/dev/null | head -1 | cut -c1-20)
    linha "✓" "$G" "$nome" "${v:-ok}" ""
    return 0
  fi
  case "$nivel" in
    essencial)
      linha "✗" "$R" "$nome" "AUSENTE" "$perda"
      printf '                                     %s→ %s%s\n' "$Y" "$instala" "$RST"
      FALTA_ESSENCIAL=1 ;;
    degrada)
      linha "⚠" "$Y" "$nome" "ausente" "$perda"
      printf '                                     %s→ %s%s\n' "$Y" "$instala" "$RST"
      DEGRADADO=1 ;;
    opcional)
      linha "·" "$Y" "$nome" "ausente" "$perda" ;;
  esac
  return 1
}

echo "${B}═══ blindar doctor — ambiente da máquina ═══${RST}"
echo ""

verifica git  essencial 'git --version | cut -d" " -f3' \
  "instalação, sync e o modo diff (--since) não funcionam" \
  "https://git-scm.com  |  winget install Git.Git"

verifica node essencial 'node --version' \
  "o orquestrador não resolve o MODULE-MAP; gates, relatório e vários checks morrem" \
  "https://nodejs.org (20+)  |  winget install OpenJS.NodeJS.LTS"

verifica rg   degrada 'rg --version | head -1 | cut -d" " -f2' \
  "cai no fallback de grep: mais lento, e alguns tipos de arquivo não mapeiam" \
  "winget install BurntSushi.ripgrep.MSVC  |  brew install ripgrep  |  apt install ripgrep"

verifica docker degrada 'docker --version | cut -d" " -f3' \
  "módulo 18 self-skipa — a aplicação NUNCA é provada de pé (smoke/runtime truth)" \
  "https://docker.com"

verifica gh   opcional 'gh --version | head -1 | cut -d" " -f3' \
  "sem abrir PR e sem ler o streak de CI verde no termination" \
  "https://cli.github.com"

verifica jq   opcional 'jq --version' \
  "nada: há fallback em Node para tudo que usava jq" \
  "winget install jqlang.jq"

verifica curl opcional 'curl --version | head -1 | cut -d" " -f2' \
  "recon passivo (módulo 17) e pentest ativo (19) não enviam requisição" \
  "geralmente já vem no sistema"

# ─── bash 4+ ───
echo ""
BV="${BASH_VERSINFO[0]:-0}"
if [ "$BV" -ge 4 ]; then
  linha "✓" "$G" "bash" "$BASH_VERSION" ""
else
  linha "⚠" "$Y" "bash" "$BASH_VERSION" "3.x: array associativo e algumas features do fallback degradam"
  printf '                                     %s→ macOS: brew install bash (ver docs/BASH-COMPAT.md)%s\n' "$Y" "$RST"
  DEGRADADO=1
fi

# ─── Skill irmã ───
ANC=""
for d in "${ANCORAR_DIR:-}" "$HOME/.claude/skills/ancorar" "../ancorar"; do
  [ -n "${d:-}" ] && [ -f "$d/scripts/run.sh" ] && { ANC="$d"; break; }
done
if [ -n "$ANC" ]; then
  linha "✓" "$G" "ancorar" "instalada" ""
else
  linha "·" "$Y" "ancorar" "ausente" "o HOST nunca é verificado (firewall, TLS, backup, DNS)"
  printf '                                     %s→ gh repo clone pretinhuu1-boop/ancorar ~/.claude/skills/ancorar%s\n' "$Y" "$RST"
fi

# ─── Impacto medido, não estimado ───
echo ""
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -d "$SKILL_DIR/templates/checks" ]; then
  TOTAL=$(find "$SKILL_DIR/templates/checks" -maxdepth 1 -name 'check-*.sh' | wc -l | tr -d ' ')
  # Quantos checks morrem sem ripgrep: os que saem cedo quando `rg` falta.
  SEM_RG=$(grep -l 'command -v rg' "$SKILL_DIR"/templates/checks/check-*.sh 2>/dev/null | wc -l | tr -d ' ')
  echo "${B}── impacto medido neste repositório ──${RST}"
  echo "  checks instalados: $TOTAL"
  command -v rg >/dev/null 2>&1 || \
    echo "  ${Y}$SEM_RG deles saem como 'skipped' sem ripgrep — e skipped NÃO é aprovação${RST}"
  [ -n "${ANTHROPIC_API_KEY:-}" ] && echo "  ANTHROPIC_API_KEY presente (checks .api.sh e análise proativa ativos)" \
    || echo "  ${Y}ANTHROPIC_API_KEY ausente — 14 checks .api.sh viram deferred (playbook manual)${RST}"
fi

echo ""
if [ "$FALTA_ESSENCIAL" -eq 1 ]; then
  echo "${R}${B}✗ falta dependência ESSENCIAL — o blindar não roda completo.${RST}"
  exit 1
fi
if [ "$DEGRADADO" -eq 1 ]; then
  echo "${Y}${B}⚠ roda, mas com cobertura reduzida.${RST} O que falta acima diz o que se perde."
  echo "  Cobertura reduzida sem aviso é o pior modo de falha: o relatório parece bom."
  exit 0
fi
echo "${G}${B}✓ ambiente completo.${RST}"
exit 0
