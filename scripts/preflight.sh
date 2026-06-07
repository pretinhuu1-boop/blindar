#!/usr/bin/env bash
# scripts/preflight.sh
#
# Valida que o projeto atual esta pronto pra blindar.
# Exit 0 se todos checks passaram, exit 1 caso contrario.
#
# Uso (na pasta do projeto-alvo):
#   ~/.claude/skills/blindar/scripts/preflight.sh
#
# Flags:
#   --fix      tenta corrigir checks que da pra automatizar
#   --quiet    so imprime resultado final

set -u

FIX=0
QUIET=0
FAILED=0
declare -a RESULTS

while [ $# -gt 0 ]; do
  case "$1" in
    --fix) FIX=1; shift ;;
    --quiet) QUIET=1; shift ;;
    *) echo "Unknown flag: $1" >&2; exit 2 ;;
  esac
done

add_check() {
  local name="$1" ok="$2" fix="$3" detail="${4:-}"
  RESULTS+=("$ok|$name|$fix|$detail")
  [ "$ok" = "0" ] && FAILED=$((FAILED+1))
}

# 1. Repo git?
if [ -d .git ]; then ok=1; else ok=0; fi
add_check "Pasta atual e repo git" "$ok" "Rode: git init"

# 2. Branch nomeada?
if [ "$ok" = "1" ]; then
  branch=$(git branch --show-current 2>/dev/null || echo "")
  if [ -n "$branch" ]; then bok=1; else bok=0; fi
  add_check "Em branch nomeada" "$bok" "Checkout: git checkout -b feature/blindar" "atual: $branch"
fi

# 3. Working tree limpo?
if [ "$ok" = "1" ]; then
  status=$(git status --porcelain 2>/dev/null)
  if [ -z "$status" ]; then cok=1; else cok=0; fi
  add_check "Working tree limpo" "$cok" "Commit ou stash: git status / git stash"
fi

# 4. CI configurada?
if [ -d .github/workflows ] || [ -f .gitlab-ci.yml ] || [ -f Jenkinsfile ] || \
   [ -f .circleci/config.yml ] || [ -f .travis.yml ] || [ -f azure-pipelines.yml ]; then
  ciok=1
else
  ciok=0
fi
add_check "CI configurada" "$ciok" "Adicione .github/workflows/ci.yml minima"

# 5. Stack detectavel?
STACK=""
for entry in "package.json:Node" "requirements.txt:Python(pip)" "pyproject.toml:Python(modern)" \
             "Cargo.toml:Rust" "go.mod:Go" "pom.xml:Java(Maven)" "build.gradle:JVM(Gradle)" \
             "Gemfile:Ruby" "composer.json:PHP"; do
  f=$(echo "$entry" | cut -d: -f1)
  s=$(echo "$entry" | cut -d: -f2)
  [ -f "$f" ] && STACK="${STACK}${STACK:+, }$s"
done
if [ -n "$STACK" ]; then sok=1; else sok=0; fi
add_check "Stack detectavel" "$sok" "Adicione package.json/requirements.txt/etc." "detectada: ${STACK:-nenhuma}"

# 6. gh CLI autenticado?
if command -v gh >/dev/null 2>&1; then
  if gh auth status >/dev/null 2>&1; then ghok=1; else ghok=0; fi
  add_check "gh CLI autenticado" "$ghok" "Rode: gh auth login"
else
  add_check "gh CLI instalado" "0" "Instale: brew install gh / apt install gh / ver cli.github.com"
fi

# 7. .blindar dir?
if [ -d .blindar ]; then bok=1; else
  if [ "$FIX" = "1" ]; then mkdir -p .blindar; bok=1; else bok=0; fi
fi
add_check ".blindar dir presente" "$bok" "Sera criado na 1a invocacao (ou rode com --fix)"

# 8. accept-risk.md migrado?
if [ -f accept-risk.md ]; then
  if [ -f .blindar/accept-risk.md ]; then mok=1; else
    if [ "$FIX" = "1" ] && [ -d .blindar ]; then mv accept-risk.md .blindar/accept-risk.md; mok=1; else mok=0; fi
  fi
  add_check "accept-risk.md em .blindar/ (nao raiz)" "$mok" "Mova: mv accept-risk.md .blindar/ (ou rode com --fix)"
fi

# Imprime
if [ "$QUIET" = "0" ]; then
  echo ""
  echo "blindar preflight"
  echo "================="
  for r in "${RESULTS[@]}"; do
    IFS='|' read -r ok name fix detail <<< "$r"
    if [ "$ok" = "1" ]; then sym="OK "; else sym="!! "; fi
    echo "  $sym $name"
    [ -n "$detail" ] && echo "      $detail"
    [ "$ok" = "0" ] && [ -n "$fix" ] && echo "      fix: $fix"
  done
  echo ""
fi

if [ "$FAILED" -eq 0 ]; then
  echo "OK - todos os checks passaram."
  echo "Proximo passo: invocar 'blindar' no Claude Code."
  echo "  Ou em outras AIs: cole AI-ENTRYPOINT.md + SKILL.md no chat."
  exit 0
else
  echo "$FAILED check(s) falharam. Resolva antes de invocar blindar."
  [ "$FIX" = "0" ] && echo "Dica: rode com --fix pra corrigir o que da pra automatizar."
  exit 1
fi
