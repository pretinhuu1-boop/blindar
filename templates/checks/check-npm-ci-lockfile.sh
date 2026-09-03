#!/usr/bin/env bash
# Materializa: npm-ci-lockfile — build que resolve dependência na hora não é
# reprodutível.
#
# `npm install` num Dockerfile ignora o lockfile quando ele diverge do
# package.json e resolve os ranges de novo. Duas consequências:
#
#   1. A imagem de hoje não é a de ontem. O que foi auditado não é o que
#      subiu, e "escaneado" perde o sentido.
#   2. Um pacote comprometido publicado entre os dois builds entra sozinho.
#      É assim que ataque de cadeia de suprimento chega em produção sem
#      ninguém aprovar nada.
#
# `npm ci` instala exatamente o que está no lockfile e falha se divergir — o
# comportamento que se quer num build. O equivalente existe em todo gerenciador:
# `--frozen-lockfile` (pnpm/yarn), `poetry install` com poetry.lock, `pip-sync`.
BLINDAR_AGENT="check-npm-ci-lockfile"
source "$(dirname "$0")/_lib.sh"
log_section "Check: instalação travada no lockfile (npm ci / frozen-lockfile)"

if [ ! -f "package.json" ]; then
  log_info "projeto sem package.json — não se aplica"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

# ─── 1. O lockfile existe? ───
LOCK=""
for f in package-lock.json pnpm-lock.yaml yarn.lock npm-shrinkwrap.json bun.lockb bun.lock; do
  [ -f "$f" ] && { LOCK="$f"; break; }
done
if [ -z "$LOCK" ]; then
  add_finding "high" \
    "Sem lockfile (package-lock.json, pnpm-lock.yaml, yarn.lock). Toda instalação resolve os ranges de novo: a árvore de dependências de hoje não é a de amanhã, e um pacote comprometido publicado no meio entra sem ninguém aprovar. Commite o lockfile." \
    "package.json" ""
else
  log_pass "lockfile presente: $LOCK"
  # Lockfile ignorado no .gitignore é lockfile que não existe para o build de CI.
  if [ -f ".gitignore" ] && grep -qE "^[[:space:]]*/?($LOCK|\*\.lock|package-lock\.json)[[:space:]]*$" .gitignore 2>/dev/null; then
    add_finding "high" "Lockfile $LOCK está no .gitignore — para o CI e para o build da imagem ele não existe, e a instalação volta a resolver ranges" ".gitignore" "$(grep -nE "^[[:space:]]*/?($LOCK|package-lock\.json)" .gitignore | head -1 | cut -d: -f1)"
  fi
fi

# ─── 2. Quem instala usa o modo travado? ───
ALVOS=""
for f in Dockerfile Dockerfile.prod Dockerfile.production docker/Dockerfile build/Dockerfile; do
  [ -f "$f" ] && ALVOS="$ALVOS $f"
done
for f in .github/workflows/*.yml .github/workflows/*.yaml .gitlab-ci.yml Makefile; do
  [ -f "$f" ] && ALVOS="$ALVOS $f"
done

for f in $ALVOS; do
  L=$(grep -nE '(^|[^a-zA-Z-])npm[[:space:]]+(install|i)([[:space:]]|$)' "$f" 2>/dev/null \
      | grep -vE '(npm[[:space:]]+install[[:space:]]+-g|npm[[:space:]]+i[[:space:]]+-g)' | head -1)
  if [ -n "$L" ]; then
    add_finding "med" \
      "Instalação com 'npm install' em $f — quando o lockfile diverge do package.json ele é ignorado e os ranges são resolvidos de novo, então a imagem construída deixa de ser a auditada. Use 'npm ci'." \
      "$f" "$(printf '%s' "$L" | cut -d: -f1)"
  fi
  # pnpm/yarn sem congelar o lock têm o mesmo defeito.
  L2=$(grep -nE '(^|[^a-zA-Z-])(pnpm|yarn)[[:space:]]+install' "$f" 2>/dev/null | grep -v 'frozen-lockfile' | grep -v 'immutable' | head -1)
  if [ -n "$L2" ]; then
    GER=$(printf '%s' "$L2" | grep -oE '(pnpm|yarn)' | head -1)
    add_finding "med" \
      "'$GER install' em $f sem --frozen-lockfile (pnpm) / --immutable (yarn) — a resolução pode divergir do lockfile no build" \
      "$f" "$(printf '%s' "$L2" | cut -d: -f1)"
  fi
done

if [ "${#FINDINGS[@]}" -gt 0 ]; then
  case "${FINDINGS[*]}" in
    *'"severity":"high"'*|*'"severity":"crit"'*) emit_result "$BLINDAR_AGENT" "failed" 1; exit 1 ;;
  esac
  emit_result "$BLINDAR_AGENT" "failed" 0
  exit 0
fi

log_pass "instalação travada no lockfile em todos os pontos de build"
emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
