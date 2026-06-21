#!/usr/bin/env bash
# blindar — instala a camada determinística no projeto-alvo.
# Copia templates/checks/* + .github/workflows/blindar.yml + .husky/ pro projeto.
# Adapta package.json scripts.
#
# Uso (dentro do projeto-alvo):
#   bash ~/.claude/skills/blindar/scripts/install-deterministic-checks.sh
#
# Idempotente: skipa o que já existe; usa --force pra sobrescrever.

set -euo pipefail

FORCE=0
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    --help)  echo "Uso: $0 [--force]"; exit 0 ;;
  esac
done

if [ ! -d ".git" ]; then
  echo "❌ Não está em um repositório git. Rode de dentro do projeto-alvo."
  exit 1
fi

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATES="$SKILL_DIR/templates"

copy_if_absent() {
  local src="$1"; local dst="$2"; local desc="$3"
  if [ -f "$dst" ] && [ "$FORCE" -eq 0 ]; then
    echo "  ⏭️  $dst (já existe — use --force pra sobrescrever)"
    return 0
  fi
  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst"
  chmod +x "$dst" 2>/dev/null || true
  echo "  ✓  $dst ($desc)"
}

echo "═══ blindar deterministic layer install ═══"
echo ""

echo "1. Scripts de check..."
for script in "$TEMPLATES/checks/"*.sh; do
  copy_if_absent "$script" "scripts/blindar/$(basename "$script")" "check determinístico"
done

echo ""
echo "2. GitHub Actions workflow..."
copy_if_absent "$TEMPLATES/.github/workflows/blindar.yml" \
               ".github/workflows/blindar.yml" "CI"

echo ""
echo "3. Husky hooks (se Husky configurado)..."
if [ -d ".husky" ]; then
  copy_if_absent "$TEMPLATES/.husky/pre-commit" ".husky/pre-commit" "pre-commit"
  copy_if_absent "$TEMPLATES/.husky/pre-push"   ".husky/pre-push"   "pre-push"
else
  echo "  ⏭️  .husky/ não existe — pule esse passo OU rode: npx husky init"
fi

echo ""
echo "4. Setup .blindar/ no projeto..."
mkdir -p .blindar/results
if [ ! -f ".blindar/accept-risk.md" ]; then
  cat > .blindar/accept-risk.md <<'EOF'
# Riscos aceitos

Findings de severidade `high` aceitos conscientemente. Marque com `[x]`
pra que `check-termination.sh` os considere aprovados.

## Template

- [ ] **AGENTE** — descrição do finding
  - ADR: docs/adr/000X-decisao.md
  - Razão: ...
  - Quando reavaliar: ...
EOF
  echo "  ✓  .blindar/accept-risk.md (template criado)"
fi

echo ""
echo "5. Verificando dependências externas..."
MISSING=()
for tool in rg jq; do
  command -v "$tool" >/dev/null 2>&1 || MISSING+=("$tool")
done
if command -v gitleaks >/dev/null 2>&1; then
  echo "  ✓  gitleaks instalado"
else
  echo "  ⚠  gitleaks NÃO instalado (recomendado pra check-secrets)"
  echo "      brew install gitleaks  (mac)"
  echo "      ou: https://github.com/gitleaks/gitleaks#installing"
fi
for m in "${MISSING[@]}"; do
  echo "  ⚠  $m NÃO instalado (necessário pra alguns checks)"
done

echo ""
echo "═══ Instalação concluída ═══"
echo ""
echo "Próximos passos:"
echo "  1. Adicione ao package.json scripts:"
echo "       \"blindar:check\":      \"bash scripts/blindar/run-all.sh\","
echo "       \"blindar:fast\":       \"bash scripts/blindar/run-all.sh --fast\","
echo "       \"blindar:terminate\":  \"bash scripts/blindar/check-termination.sh\""
echo ""
echo "  2. Configure branch protection no GitHub:"
echo "       Settings → Branches → main → Require status checks:"
echo "         ☑ blindar-checks"
echo ""
echo "  3. Teste local:"
echo "       npm run blindar:check"
echo ""
echo "  4. Commit + push:"
echo "       git add scripts/blindar/ .github/workflows/blindar.yml .husky/"
echo "       git commit -m 'feat: adicionar blindar deterministic layer'"
