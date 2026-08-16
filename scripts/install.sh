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

# ─── Ambiente ───
# Rodar o doctor aqui e nao depois: a ausencia de ferramenta e silenciosa no
# lugar errado. Sem ripgrep dezenas de checks saem como "skipped" e o relatorio
# mostra cobertura alta — o operador nunca sabe que metade nao olhou nada.
if [ -f "$TARGET/scripts/doctor.sh" ]; then
  bash "$TARGET/scripts/doctor.sh" || true
fi

# ─── Skill irma ───
# O ancorar fica em repo proprio porque tem codigo (16 checks de host via SSH,
# 10 fases) e um contrato de supervisao diferente. Sem ele o blindar cobre o
# codigo e o HOST nunca e verificado.
ANCORAR_TARGET="${ANCORAR_TARGET:-$HOME/.claude/skills/ancorar}"
if [ ! -d "$ANCORAR_TARGET" ]; then
  echo ""
  echo "  A skill irma 'ancorar' verifica o SERVIDOR (firewall, TLS, backup, DNS,"
  echo "  vizinhos de container) — o que o blindar nao alcanca. Sem ela, o gate"
  echo "  DEPLOYMENT fica em 'host nunca verificado'."
  echo ""
  if [ "${BLINDAR_INSTALL_ANCORAR:-ask}" = "yes" ]; then
    RESP="s"
  elif [ "${BLINDAR_INSTALL_ANCORAR:-ask}" = "no" ] || [ ! -t 0 ]; then
    RESP="n"
  else
    printf "  Instalar o ancorar tambem? [s/N] "
    read -r RESP </dev/tty || RESP="n"
  fi
  case "${RESP:-n}" in
    s|S|y|Y)
      if git clone --depth 1 "https://github.com/pretinhuu1-boop/ancorar.git" "$ANCORAR_TARGET" 2>/dev/null; then
        echo "  ancorar instalado em $ANCORAR_TARGET"
      else
        echo "  nao consegui clonar o ancorar (repo privado? faca login com: gh auth login)"
        echo "  depois: gh repo clone pretinhuu1-boop/ancorar \"$ANCORAR_TARGET\""
      fi ;;
    *)
      echo "  pulado. Depois: gh repo clone pretinhuu1-boop/ancorar \"$ANCORAR_TARGET\"" ;;
  esac
fi

echo ""
echo "  Opcional, recomendado: instale o guard da lista CRITICAL no Claude Code."
echo "  Ele PAUSA comandos que apagam dado ou reescrevem historico compartilhado."
echo "    bash \"$TARGET/scripts/install-hooks.sh\" --user"
echo ""
echo "Proximo passo: leia CHECKLIST.md"
echo "  cat \"$TARGET/CHECKLIST.md\""
echo ""
