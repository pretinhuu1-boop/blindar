#!/usr/bin/env bash
# blindar auto-fix — aplica correções automáticas em findings comuns
# que tem fix SEGURO + ÓBVIO. Para findings ambíguos, mostra sugestão
# mas não aplica.
#
# Uso:
#   bash scripts/blindar/auto-fix.sh             # modo dry-run (mostra o que faria)
#   bash scripts/blindar/auto-fix.sh --apply     # aplica de verdade (cria branch + commit)
#   bash scripts/blindar/auto-fix.sh --check mock-killer  # aplica só dum agente

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_lib.sh"

APPLY=0
ONLY_CHECK=""
for arg in "$@"; do
  case "$arg" in
    --apply)         APPLY=1 ;;
    --check)         shift; ONLY_CHECK="$1" ;;
    --help)          echo "Uso: $0 [--apply] [--check <agent>]"; exit 0 ;;
  esac
done

log_section "blindar auto-fix ($([ "$APPLY" = "1" ] && echo "APPLY" || echo "DRY-RUN"))"

if [ "$APPLY" = "1" ]; then
  # Cria branch + começa commit
  CURR=$(git rev-parse --abbrev-ref HEAD)
  if [ "$CURR" = "main" ] || [ "$CURR" = "master" ]; then
    BRANCH="fix/blindar-autofix-$(date +%Y%m%d-%H%M%S)"
    git checkout -b "$BRANCH"
    log_info "Branch criada: $BRANCH"
  fi
fi

FIXES_APPLIED=0
SUGGESTIONS=()

# ─── FIX 1: console.log em dev-only files → adicionar // @blindar:keep ───
if [ -z "$ONLY_CHECK" ] || [ "$ONLY_CHECK" = "mock-killer" ]; then
  log_info "Procurando console.log em arquivos *.dev.ts..."
  while IFS= read -r file; do
    [ -z "$file" ] && continue
    [ ! -f "$file" ] && continue

    # Acha linhas com console.* sem @blindar:keep
    while IFS=: read -r line content; do
      [ -z "$line" ] && continue
      if ! echo "$content" | grep -q "@blindar:keep"; then
        if [ "$APPLY" = "1" ]; then
          # Adiciona comentário ANTES da linha
          sed -i.bak "${line}i // @blindar:keep -- auto-added by blindar (dev-only file)" "$file"
          rm -f "${file}.bak"
          FIXES_APPLIED=$((FIXES_APPLIED + 1))
          log_pass "Fixed: $file:$line"
        else
          SUGGESTIONS+=("ADD '// @blindar:keep' before $file:$line (dev-only file)")
        fi
      fi
    done < <(rg -n "console\.(log|debug|warn)" "$file" 2>/dev/null)
  done < <(find . -name "*.dev.ts" -not -path "./node_modules/*" 2>/dev/null)
fi

# ─── FIX 2: TODO sem issue → sugerir TODO(issue-?) ───
if [ -z "$ONLY_CHECK" ] || [ "$ONLY_CHECK" = "mock-killer" ]; then
  log_info "Procurando TODOs sem issue link..."
  # SÓ sugere (não aplica — operador precisa criar issue)
  TODO_COUNT=$(rg -n "TODO[^(]" --type ts --type tsx 2>/dev/null | grep -v "TODO(issue-\|@blindar:keep-todo" | wc -l || echo 0)
  if [ "$TODO_COUNT" -gt 0 ]; then
    SUGGESTIONS+=("$TODO_COUNT TODOs sem issue — crie issues e use TODO(issue-#N): ... (não auto-fixed)")
  fi
fi

# ─── FIX 3: .env.example faltando vars usadas no código ───
if [ -z "$ONLY_CHECK" ] || [ "$ONLY_CHECK" = "config-externalization" ]; then
  log_info "Sincronizando .env.example..."
  if [ -f ".env.example" ]; then
    USED_VARS=$(rg -hoE "process\.env\.[A-Z_][A-Z_0-9]+" --type ts --type js src/ apps/ 2>/dev/null | sort -u | sed 's/process.env.//')

    MISSING=""
    while IFS= read -r v; do
      [ -z "$v" ] && continue
      grep -q "^${v}=" .env.example 2>/dev/null || MISSING="$MISSING\n${v}="
    done <<< "$USED_VARS"

    if [ -n "$MISSING" ]; then
      if [ "$APPLY" = "1" ]; then
        echo "" >> .env.example
        echo "# Auto-added by blindar (vars usadas no código mas ausentes)" >> .env.example
        echo -e "$MISSING" >> .env.example
        FIXES_APPLIED=$((FIXES_APPLIED + 1))
        log_pass "Adicionado vars faltantes em .env.example"
      else
        SUGGESTIONS+=("ADICIONAR ao .env.example:$MISSING")
      fi
    fi
  fi
fi

# ─── FIX 4: <img> sem alt em projetos React → adicionar alt="" placeholder ───
# (NÃO aplica automaticamente — risco de gerar alt errado. Só sugere.)
if [ -z "$ONLY_CHECK" ] || [ "$ONLY_CHECK" = "responsive-a11y" ]; then
  IMG_NO_ALT=$(rg -cP "<img(?![^>]*\balt=)" --type tsx --type jsx 2>/dev/null | wc -l || echo 0)
  if [ "$IMG_NO_ALT" -gt 0 ]; then
    SUGGESTIONS+=("$IMG_NO_ALT <img> sem alt — adicione alt descritivo manualmente (não auto-fixed pra evitar gerar alt errado)")
  fi
fi

# ─── FIX 5: Action sem SHA pin → sugerir hash atual ───
if [ -z "$ONLY_CHECK" ] || [ "$ONLY_CHECK" = "sbom-slsa" ]; then
  if [ -d ".github/workflows" ]; then
    UNPINNED=$(rg -nE "uses: [^@]+@v?\d" .github/workflows/ 2>/dev/null | head -20)
    if [ -n "$UNPINNED" ]; then
      SUGGESTIONS+=("Actions usando tags — rodar 'pinact' (https://github.com/suzuki-shunsuke/pinact) pra converter pra SHA")
    fi
  fi
fi

# ─── FIX 6: Dockerfile FROM :latest → sugerir versão atual ───
if [ -f "Dockerfile" ]; then
  if grep -qE ":latest$" Dockerfile 2>/dev/null; then
    SUGGESTIONS+=("Dockerfile com :latest — fixar versão major (ex: node:20-alpine) e pin SHA via 'docker pull' + 'docker inspect'")
  fi
fi

echo ""
log_section "RESUMO"
echo "Fixes aplicados: $FIXES_APPLIED"
echo "Sugestões (não aplicadas — exigem judgment): ${#SUGGESTIONS[@]}"

if [ "${#SUGGESTIONS[@]}" -gt 0 ]; then
  echo ""
  echo "Sugestões:"
  for s in "${SUGGESTIONS[@]}"; do
    echo "  • $s"
  done
fi

if [ "$APPLY" = "1" ] && [ "$FIXES_APPLIED" -gt 0 ]; then
  echo ""
  log_info "Criando commit..."
  git add -A
  git commit -m "chore(blindar): auto-fix de $FIXES_APPLIED findings

Aplicado por: blindar auto-fix
Detalhes em: .blindar/results/

Revisão manual recomendada antes de mergear.

Co-Authored-By: blindar <noreply@blindar.dev>"

  echo ""
  log_pass "Commit criado. Próximo: revisar diff + abrir PR"
  echo "  git diff HEAD~1"
  echo "  gh pr create"
fi

exit 0
