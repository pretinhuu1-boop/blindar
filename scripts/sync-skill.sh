#!/usr/bin/env bash
# sync-skill.sh — sincroniza o repo dev do blindar → cópia instalada da skill.
#
# Fonte da verdade: working tree do repo dev (arquivos TRACKED pelo git).
# Destino: ~/.claude/skills/blindar (ou --dest DIR).
#
# O que faz:
#   1. Copia todo arquivo tracked que difere (ou falta) no destino
#   2. Remove do destino arquivos órfãos (que não existem no file-set tracked)
#   3. Preserva estado de runtime do destino: .git/, .blindar/, .last-check
#   4. Verifica ao final que não sobrou drift (falha se sobrou)
#
# Uso:
#   bash scripts/sync-skill.sh              # aplica sync
#   bash scripts/sync-skill.sh --check      # só reporta drift (exit 1 se houver)
#   bash scripts/sync-skill.sh --dest DIR   # destino alternativo
#
# Exit codes: 0 = em sync / sincronizado; 1 = drift (--check) ou verificação
# pós-sync falhou; 64 = uso incorreto; 70 = pré-requisito ausente.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$(dirname "$SCRIPT_DIR")"
DEST="$HOME/.claude/skills/blindar"
CHECK_ONLY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --check) CHECK_ONLY=1; shift ;;
    --dest)  DEST="$2"; shift 2 ;;
    -h|--help) sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Arg desconhecido: $1" >&2; exit 64 ;;
  esac
done

command -v git >/dev/null 2>&1 || { echo "ERRO: git requerido" >&2; exit 70; }
git -C "$SRC" rev-parse --git-dir >/dev/null 2>&1 || {
  echo "ERRO: $SRC não é repo git — sync usa 'git ls-files' como file-set" >&2
  exit 70
}

SRC_REAL="$(cd "$SRC" && pwd)"
if [ -d "$DEST" ]; then
  DEST_REAL="$(cd "$DEST" && pwd)"
  [ "$SRC_REAL" = "$DEST_REAL" ] && { echo "ERRO: fonte == destino ($SRC_REAL)" >&2; exit 64; }
fi

# Dirs/arquivos de runtime do destino que o sync NUNCA toca
is_protected() {
  case "$1" in
    .git|.git/*|.blindar|.blindar/*|.last-check) return 0 ;;
    *) return 1 ;;
  esac
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# File-set canônico: tracked no working tree do dev
git -C "$SRC" ls-files -z > "$TMP/tracked.z"
tr '\0' '\n' < "$TMP/tracked.z" | LC_ALL=C sort > "$TMP/tracked.txt"
TRACKED_COUNT=$(grep -c . "$TMP/tracked.txt" || true)
[ "$TRACKED_COUNT" -eq 0 ] && { echo "ERRO: 0 arquivos tracked em $SRC" >&2; exit 70; }

MISSING=0; DIFFER=0; COPIED=0; STALE=0; DELETED=0

# ── Comparação em lote: md5sum -c = 1 processo pro set inteiro ───────────
# (loop de cmp por arquivo custa ~1 spawn/arquivo — proibitivo no Windows).
# Fallback pra cmp por arquivo se md5sum não existir.
list_divergent() {
  # stdout: um path por linha (relativo) que falta OU difere no DEST
  if [ ! -d "$DEST" ]; then
    # destino não existe → tudo é "faltando" (instalação do zero)
    tr '\0' '\n' < "$TMP/tracked.z"
    return 0
  fi
  if command -v md5sum >/dev/null 2>&1; then
    ( cd "$SRC" && xargs -0 -r md5sum -- < "$TMP/tracked.z" 2>/dev/null ) > "$TMP/src.md5"
    ( cd "$DEST" 2>/dev/null && md5sum -c --quiet "$TMP/src.md5" 2>&1 || true ) \
      | sed -n 's/^\(.*\): FAILED.*$/\1/p'
  else
    while IFS= read -r -d '' f; do
      [ -f "$SRC/$f" ] || continue
      { [ -f "$DEST/$f" ] && cmp -s "$SRC/$f" "$DEST/$f"; } || echo "$f"
    done < "$TMP/tracked.z"
  fi
}

# ── Passo 1: diferenças tracked → destino ────────────────────────────────
list_divergent > "$TMP/divergent.txt"
while IFS= read -r f; do
  [ -z "$f" ] && continue
  [ -f "$SRC/$f" ] || continue   # tracked mas deletado no working tree — pula
  if [ ! -f "$DEST/$f" ]; then
    MISSING=$((MISSING+1))
    if [ "$CHECK_ONLY" -eq 1 ]; then echo "  faltando: $f"
    else mkdir -p "$(dirname "$DEST/$f")" && cp -p "$SRC/$f" "$DEST/$f" && COPIED=$((COPIED+1)); fi
  else
    DIFFER=$((DIFFER+1))
    if [ "$CHECK_ONLY" -eq 1 ]; then echo "  difere:   $f"
    else cp -p "$SRC/$f" "$DEST/$f" && COPIED=$((COPIED+1)); fi
  fi
done < "$TMP/divergent.txt"

# ── Passo 2: órfãos no destino (fora do file-set, fora do protegido) ─────
if [ -d "$DEST" ]; then
  ( cd "$DEST" && find . -type f | sed 's|^\./||' ) | LC_ALL=C sort > "$TMP/dest.txt"
  LC_ALL=C comm -13 "$TMP/tracked.txt" "$TMP/dest.txt" > "$TMP/stale.txt"
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    is_protected "$f" && continue
    STALE=$((STALE+1))
    if [ "$CHECK_ONLY" -eq 1 ]; then echo "  órfão:    $f"
    else rm -f "$DEST/$f" && DELETED=$((DELETED+1)); fi
  done < "$TMP/stale.txt"
fi

# ── Passo 3: limpa diretórios vazios deixados pra trás ───────────────────
if [ "$CHECK_ONLY" -eq 0 ] && [ -d "$DEST" ]; then
  find "$DEST" -mindepth 1 -depth -type d \
    ! -path "$DEST/.git" ! -path "$DEST/.git/*" \
    ! -path "$DEST/.blindar" ! -path "$DEST/.blindar/*" \
    -empty -exec rmdir {} \; 2>/dev/null || true
fi

# ── Relatório ─────────────────────────────────────────────────────────────
if [ "$CHECK_ONLY" -eq 1 ]; then
  TOTAL_DRIFT=$((MISSING + DIFFER + STALE))
  if [ "$TOTAL_DRIFT" -eq 0 ]; then
    echo "✓ em sync — $TRACKED_COUNT arquivos tracked, 0 drift ($DEST)"
    exit 0
  fi
  echo "✗ drift: $MISSING faltando, $DIFFER diferentes, $STALE órfãos ($DEST)"
  echo "  aplique com: bash scripts/sync-skill.sh"
  exit 1
fi

# Verificação pós-sync (re-checa que zerou)
VERIFY_FAIL=0
list_divergent > "$TMP/verify.txt"
while IFS= read -r f; do
  [ -z "$f" ] && continue
  [ -f "$SRC/$f" ] || continue
  VERIFY_FAIL=$((VERIFY_FAIL+1)); echo "  ✗ verify: $f" >&2
done < "$TMP/verify.txt"

echo "sync: $COPIED copiados, $DELETED órfãos removidos, $TRACKED_COUNT tracked → $DEST"
if [ "$VERIFY_FAIL" -gt 0 ]; then
  echo "✗ verificação pós-sync falhou em $VERIFY_FAIL arquivo(s)" >&2
  exit 1
fi
echo "✓ verificado — cópias idênticas"
exit 0
