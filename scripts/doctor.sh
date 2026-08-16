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
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ─── O rg é perguntado ao _lib.sh, não ao PATH ───
# Se o doctor decidisse por conta própria, as duas respostas divergiriam na
# máquina recém-instalada: PATH ainda sem rg, mas o probe do _lib.sh achando o
# binário. Doctor diria "cobertura reduzida" e os checks rodariam completos —
# ou o inverso, que é pior. Uma pergunta, uma fonte.
_PROBE="$( (. "$SKILL_DIR/templates/checks/_lib.sh"; printf '%s\n%s' "${BLINDAR_RG_BIN:-}" "$PATH") 2>/dev/null )"
RG_REAL="$(printf '%s' "$_PROBE" | head -1)"
# O _lib.sh também junta ao PATH o que a máquina já declarou e este shell ainda
# não pegou (Windows: instalou agora, PATH só no próximo shell). Sem herdar isso,
# o doctor listaria gitleaks/trivy como ausentes e os checks os encontrariam —
# duas respostas para a mesma pergunta, que é o bug que este projeto persegue.
_PROBE_PATH="$(printf '%s' "$_PROBE" | tail -n +2)"
[ -n "$_PROBE_PATH" ] && export PATH="$_PROBE_PATH"
unset _PROBE _PROBE_PATH

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

if [ -n "$RG_REAL" ]; then
  RGV="$("$RG_REAL" --version 2>/dev/null | head -1 | cut -d' ' -f2)"
  if type -P rg >/dev/null 2>&1; then
    linha "✓" "$G" "rg" "${RGV:-ok}" ""
  else
    # Instalado, achado, usado — mas fora do PATH. Não é degradação (o blindar
    # roda completo), e também não é "tudo normal": qualquer outra ferramenta
    # que chame `rg` nesta máquina ainda não acha. Dizer as duas coisas.
    linha "✓" "$G" "rg" "${RGV:-ok}" "fora do PATH — o blindar acha, seu shell não"
    printf '                                     %s→ %s%s\n' "$Y" "$RG_REAL" "$RST"
    printf '                                     %s→ abra um shell novo, ou adicione o diretório ao PATH%s\n' "$Y" "$RST"
  fi
else
  linha "⚠" "$Y" "rg" "ausente" "cai no fallback de grep: mais lento, e alguns tipos de arquivo não mapeiam"
  printf '                                     %s→ winget install BurntSushi.ripgrep.MSVC  |  brew install ripgrep  |  apt install ripgrep%s\n' "$Y" "$RST"
  DEGRADADO=1
fi

verifica docker degrada 'docker --version | cut -d" " -f3' \
  "módulo 18 self-skipa — a aplicação NUNCA é provada de pé (smoke/runtime truth)" \
  "https://docker.com"

verifica gh   opcional 'gh --version | head -1 | cut -d" " -f3' \
  "sem abrir PR e sem ler o streak de CI verde no termination" \
  "https://cli.github.com"

# Dizia "nada: há fallback em Node para tudo que usava jq". Era falso nos dois
# sentidos: check-secrets pulava inteiro sem jq (gitleaks instalado e o check de
# segredo não rodava) e check-termination BLOQUEAVA a release por falta de jq.
# Os dois passaram a ler com node; o que sobrou tem fallback de verdade.
verifica jq   opcional 'jq --version' \
  "nada — os dois checks que exigiam jq (secrets, termination) leem com node" \
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
if [ -d "$SKILL_DIR/templates/checks" ]; then
  TOTAL=$(find "$SKILL_DIR/templates/checks" -maxdepth 1 -name 'check-*.sh' | wc -l | tr -d ' ')
  # Quantos checks morrem sem ripgrep: os que saem cedo quando `rg` falta.
  SEM_RG=$(grep -l 'command -v rg' "$SKILL_DIR"/templates/checks/check-*.sh 2>/dev/null | wc -l | tr -d ' ')
  echo "${B}── impacto medido neste repositório ──${RST}"
  echo "  checks instalados: $TOTAL"
  [ -n "$RG_REAL" ] || \
    echo "  ${Y}$SEM_RG deles saem como 'skipped' sem ripgrep — e skipped NÃO é aprovação${RST}"
  [ -n "${ANTHROPIC_API_KEY:-}" ] && echo "  ANTHROPIC_API_KEY presente (checks .api.sh e análise proativa ativos)" \
    || echo "  ${Y}ANTHROPIC_API_KEY ausente — 14 checks .api.sh viram deferred (playbook manual)${RST}"

  # ─── Scanners externos ───
  # Até aqui o doctor conferia 7 ferramentas e dizia "ambiente completo". Mas os
  # checks chamam gitleaks, trivy, semgrep, osv-scanner, govulncheck, pip-audit,
  # cargo-audit — nenhum na lista. Sem eles o scan de CVE e de segredo não roda,
  # e o doctor assinava embaixo que estava tudo certo.
  #
  # A lista é DERIVADA dos checks instalados, não escrita à mão: check novo com
  # dependência nova aparece aqui sozinho. Lista à mão desatualiza no primeiro
  # check que alguém adicionar, e volta a mentir exatamente do mesmo jeito.
  echo ""
  echo "${B}── scanners externos (o que cada ausência apaga) ──${RST}"
  FALTAM_SCANNERS=0
  for s in gitleaks trivy semgrep osv-scanner govulncheck pip-audit cargo-audit hunspell; do
    USADO=$(grep -l "command -v $s" "$SKILL_DIR"/templates/checks/check-*.sh 2>/dev/null | wc -l | tr -d ' ')
    [ "$USADO" = "0" ] && continue
    if command -v "$s" >/dev/null 2>&1; then
      linha "✓" "$G" "$s" "$($s --version 2>/dev/null | head -1 | tr -d '\r' | cut -c1-20)" ""
    else
      case "$s" in
        gitleaks)    perda="segredo commitado não é procurado (100+ regras)"; como="brew install gitleaks | winget install gitleaks.gitleaks" ;;
        trivy)       perda="CVE de dependência e de imagem Docker não é procurado"; como="brew install trivy | winget install AquaSecurity.Trivy" ;;
        semgrep)     perda="SAST — injeção, path traversal, crypto fraca"; como="pipx install semgrep | brew install semgrep" ;;
        osv-scanner) perda="CVE via base OSV (cobre ecossistemas que o trivy não)"; como="brew install osv-scanner | go install github.com/google/osv-scanner/cmd/osv-scanner@latest" ;;
        govulncheck) perda="CVE de dependência Go"; como="go install golang.org/x/vuln/cmd/govulncheck@latest" ;;
        pip-audit)   perda="CVE de dependência Python"; como="pipx install pip-audit" ;;
        cargo-audit) perda="CVE de dependência Rust"; como="cargo install cargo-audit" ;;
        hunspell)    perda="revisão ortográfica do texto de UI"; como="apt install hunspell | brew install hunspell" ;;
      esac
      linha "○" "$Y" "$s" "ausente" "$perda"
      printf '                                     %s→ %s%s\n' "$Y" "$como" "$RST"
      FALTAM_SCANNERS=$((FALTAM_SCANNERS + USADO))
    fi
  done
  [ "$FALTAM_SCANNERS" -gt 0 ] && echo "  ${Y}$FALTAM_SCANNERS checks saem 'skipped' por scanner ausente — nenhum deles reprovou; eles não rodaram${RST}"
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
if [ "${FALTAM_SCANNERS:-0}" -gt 0 ]; then
  # Não é "degradado" no sentido de quebrado — o blindar roda inteiro e os gates
  # decidem. Mas "completo" seria falso: a varredura de CVE e de segredo não
  # aconteceu, e é justamente aí que mora o achado caro. Nomear a diferença.
  echo "${Y}${B}✓ o blindar roda — mas o ambiente NÃO está completo.${RST}"
  echo "  $FALTAM_SCANNERS checks ficam sem executar por falta de scanner externo."
  echo "  Eles entram no relatório como 'skipped', que não é aprovação nem reprovação."
  exit 0
fi
echo "${G}${B}✓ ambiente completo.${RST}"
exit 0
