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

REPO="${BLINDAR_REPO:-pretinhuu1-boop/blindar}"
BRANCH="${BLINDAR_BRANCH:-main}"

SKILL_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION_FILE="$SKILL_ROOT/VERSION"
CACHE="$SKILL_ROOT/.last-check"

[ ! -f "$VERSION_FILE" ] && {
  echo "blindar: VERSION local nao encontrado em $VERSION_FILE" >&2
  exit 1
}

LOCAL=$(tr -d '[:space:]' < "$VERSION_FILE")

# Cache 24h
if [ "$FORCE" = "0" ] && [ -f "$CACHE" ]; then
  CACHE_AGE_SEC=$(( $(date +%s) - $(stat -c %Y "$CACHE" 2>/dev/null || stat -f %m "$CACHE") ))
  if [ "$CACHE_AGE_SEC" -lt 86400 ]; then
    REMOTE=$(grep -oE '"remote_version":"[^"]+' "$CACHE" | head -1 | cut -d'"' -f4)
    if [ -n "$REMOTE" ] && [ "$REMOTE" != "$LOCAL" ]; then
      echo "blindar v$REMOTE disponivel (local: v$LOCAL). Ver CHANGELOG.md"
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

if [ "$REMOTE" != "$LOCAL" ]; then
  echo ""
  echo "  blindar v$REMOTE disponivel"
  echo "  Voce esta em v$LOCAL"
  echo "  Atualizar: git -C \"$SKILL_ROOT\" pull --ff-only"
  echo "  CHANGELOG: https://github.com/${REPO}/blob/${BRANCH}/CHANGELOG.md"
  echo ""
elif [ "$QUIET" = "0" ]; then
  echo "blindar v$LOCAL (atualizado)"
fi
