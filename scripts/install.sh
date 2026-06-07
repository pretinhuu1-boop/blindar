#!/usr/bin/env bash
# scripts/install.sh
#
# Instala (ou atualiza) o skill blindar em ~/.claude/skills/blindar.
#
# Uso remoto:
#   curl -sSL https://raw.githubusercontent.com/pretinhuu1-boop/blindar/main/scripts/install.sh | bash
#
# Uso local (depois de clonar):
#   ./install.sh

set -eu

REPO="${BLINDAR_REPO:-pretinhuu1-boop/blindar}"
BRANCH="${BLINDAR_BRANCH:-main}"
TARGET="$HOME/.claude/skills/blindar"

mkdir -p "$(dirname "$TARGET")"

if [ -d "$TARGET" ]; then
  echo "blindar ja instalado em $TARGET"
  if [ -d "$TARGET/.git" ]; then
    echo "Atualizando via git pull..."
    git -C "$TARGET" fetch --quiet
    git -C "$TARGET" pull --ff-only
    echo "OK."
  else
    echo "Instalacao existente nao e repo git. Para atualizar, remova manualmente:"
    echo "  rm -rf \"$TARGET\""
    echo "Depois rode este script de novo."
    exit 1
  fi
  exit 0
fi

if command -v git >/dev/null 2>&1; then
  echo "Clonando $REPO -> $TARGET..."
  git clone --branch "$BRANCH" --depth 1 "https://github.com/${REPO}.git" "$TARGET"
else
  echo "git nao disponivel. Tentando tarball..."
  TARBALL_URL="https://github.com/${REPO}/archive/refs/heads/${BRANCH}.tar.gz"
  TMP=$(mktemp -d)
  curl -sSL "$TARBALL_URL" | tar xz -C "$TMP" --strip-components=1
  mkdir -p "$TARGET"
  mv "$TMP"/* "$TARGET/"
  mv "$TMP"/.* "$TARGET/" 2>/dev/null || true
  rm -rf "$TMP"
fi

echo ""
echo "blindar instalado em $TARGET"
echo ""
echo "Proximo passo: leia CHECKLIST.md"
echo "  cat \"$TARGET/CHECKLIST.md\""
echo ""
