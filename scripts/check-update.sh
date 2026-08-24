#!/usr/bin/env bash
# scripts/check-update.sh
#
# Compara VERSION local com a versao no GitHub.
# Cache 24h em .last-check.
#
# Uso:
#   ./check-update.sh             # modo verboso
#   ./check-update.sh --quiet     # silencia se nao houver update
#   ./check-update.sh --force     # ignora cache
#
# Exit: 0 = atualizado (ou nao deu pra checar) | 10 = HA VERSAO NOVA
# O 10 existe para o SKILL.md poder PERGUNTAR ao operador em vez de so avisar
# no meio do log, onde ninguem le.

set -u

QUIET=0
FORCE=0
for arg in "$@"; do
  case "$arg" in
    --quiet|-q) QUIET=1 ;;
    --force|-f) FORCE=1 ;;
  esac
done

[ "${BLINDAR_SKIP_UPDATE_CHECK:-0}" = "1" ] && {
  [ "$QUIET" = "0" ] && echo "blindar: update check desativado (BLINDAR_SKIP_UPDATE_CHECK=1)"
  exit 0
}

REPO="${BLINDAR_REPO:-maykonlong/blindar}"
BRANCH="${BLINDAR_BRANCH:-main}"

SKILL_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION_FILE="$SKILL_ROOT/VERSION"
CACHE="$SKILL_ROOT/.last-check"

[ ! -f "$VERSION_FILE" ] && {
  echo "blindar: VERSION local nao encontrado em $VERSION_FILE" >&2
  exit 1
}

# ─── "diferente" nao e "mais nova" ───
# A comparacao era `[ "$REMOTE" != "$LOCAL" ]`. Numa instalacao a frente do main
# — build de desenvolvimento, branch de release, ou simplesmente quem acabou de
# subir a versao — isso anunciava "blindar v0.72.0 disponivel / Voce esta em
# v0.73.0" e oferecia o comando de instalacao. Aceitar levaria a um DOWNGRADE.
#
# Pior: o SKILL.md usa o exit 10 para PERGUNTAR ao operador se quer atualizar.
# Perguntar "quer atualizar?" quando a resposta certa e "voce ja esta na frente"
# transforma o aviso em armadilha, e quem confia no aviso perde a versao nova.
#
# Compara campo a campo, numericamente. Sufixo (-rc1, -dev) e ignorado na
# ordenacao: se os numeros empatam, nao ha o que oferecer.
versao_maior_que() { # A B → 0 se A > B
  local a="${1%%-*}" b="${2%%-*}" i pa pb
  local IFS=.
  read -r -a pa <<< "$a"
  read -r -a pb <<< "$b"
  for i in 0 1 2; do
    local na="${pa[$i]:-0}" nb="${pb[$i]:-0}"
    case "$na$nb" in *[!0-9]*) return 1 ;; esac   # nao-numerico: nao arrisca
    [ "$na" -gt "$nb" ] && return 0
    [ "$na" -lt "$nb" ] && return 1
  done
  return 1
}

LOCAL=$(tr -d '[:space:]' < "$VERSION_FILE")

# Cache 24h
if [ "$FORCE" = "0" ] && [ -f "$CACHE" ]; then
  CACHE_AGE_SEC=$(( $(date +%s) - $(stat -c %Y "$CACHE" 2>/dev/null || stat -f %m "$CACHE") ))
  if [ "$CACHE_AGE_SEC" -lt 86400 ]; then
    REMOTE=$(grep -oE '"remote_version":"[^"]+' "$CACHE" | head -1 | cut -d'"' -f4)
    if [ -n "$REMOTE" ] && versao_maior_que "$REMOTE" "$LOCAL"; then
      echo "blindar v$REMOTE disponivel (local: v$LOCAL). Ver CHANGELOG.md"
      exit 10
    elif [ "$QUIET" = "0" ]; then
      echo "blindar v$LOCAL (atualizado, cache valido)"
    fi
    exit 0
  fi
fi

URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}/VERSION"
REMOTE=$(curl -sSf --max-time 5 "$URL" 2>/dev/null | tr -d '[:space:]' || echo "")

if [ -z "$REMOTE" ]; then
  [ "$QUIET" = "0" ] && echo "blindar: nao foi possivel checar update"
  exit 0
fi

cat > "$CACHE" <<EOF
{"checked_at":"$(date -u +%FT%TZ)","local_version":"$LOCAL","remote_version":"$REMOTE"}
EOF

if versao_maior_que "$REMOTE" "$LOCAL"; then
  # A instalada nem sempre e um clone: quando vem do sync-skill.sh ela e
  # artefato puro, sem .git, e `git pull` ali falha. Dizer o comando errado e
  # pior que nao dizer nada, porque o operador tenta e acha que quebrou.
  if [ -d "$SKILL_ROOT/.git" ]; then
    COMO="git -C \"$SKILL_ROOT\" pull --ff-only"
  else
    COMO="curl -sSL https://raw.githubusercontent.com/${REPO}/${BRANCH}/scripts/install.sh | bash"
  fi
  echo ""
  echo "  blindar v$REMOTE disponivel"
  echo "  Voce esta em v$LOCAL"
  echo "  Atualizar: $COMO"
  echo "  CHANGELOG: https://github.com/${REPO}/blob/${BRANCH}/CHANGELOG.md"
  echo ""
  exit 10
elif [ "$QUIET" = "0" ]; then
  if versao_maior_que "$LOCAL" "$REMOTE"; then
    echo "blindar v$LOCAL (a frente do main, que esta em v$REMOTE)"
  else
    echo "blindar v$LOCAL (atualizado)"
  fi
fi
