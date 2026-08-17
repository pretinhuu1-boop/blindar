#!/usr/bin/env bash
# Materializa: git-collaboration — o repositório está preparado para mais de uma
# pessoa mexer nele?
#
# Escopo deste check: o que é verificável no SISTEMA DE ARQUIVOS. O que exige
# história do git (segredo já commitado, arquivo binário grande no histórico,
# força-push em branch compartilhada, branch divergente há semanas) é do
# playbook `agents/git-collaboration.md`, que roda com o git disponível.
#
# O achado que mais importa aqui é o `.env` não ignorado. Segredo commitado é
# PARA SEMPRE: remover o arquivo num commit seguinte não remove do histórico,
# e qualquer clone antigo continua com ele. A janela para evitar isso é antes
# do primeiro commit — que é exatamente onde este check age.
BLINDAR_AGENT="check-git-hygiene"
source "$(dirname "$0")/_lib.sh"
log_section "Check: higiene de repositório para trabalho em equipe"

# Projeto sem nenhum sinal de repo/stack não tem o que avaliar.
if [ ! -d ".git" ] && [ ! -f "package.json" ] && [ ! -f "pyproject.toml" ] && \
   [ ! -f "go.mod" ] && [ ! -f "Cargo.toml" ] && [ ! -f "composer.json" ]; then
  log_info "sem sinais de projeto versionado — skipped"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

GITIGNORE=""
# `tr -d '\r'` e não `cat`: num `.gitignore` escrito no Windows a linha é
# "node_modules\r", e a âncora `$` do regex abaixo não casa antes do \r. O grep
# do MSYS engole o \r em modo texto, o GNU grep do Linux não — então o MESMO
# projeto passava aqui e reprovava no CI, com a mensagem "seu .gitignore não
# exclui node_modules" sobre um .gitignore que exclui node_modules.
#
# Medido rodando o gate em container Linux: três checks reprovaram só por isso.
# Projeto de equipe Windows com CI Linux é o caso comum, não a exceção.
[ -f ".gitignore" ] && GITIGNORE=$(tr -d '\r' < .gitignore 2>/dev/null)

# Um padrão está coberto pelo .gitignore?
ignora() { # padrão
  [ -n "$GITIGNORE" ] || return 1
  printf '%s\n' "$GITIGNORE" | grep -qE "^[[:space:]]*!?[/]?$1([/*]|$)" 2>/dev/null
}

# ─── 1. Arquivo de ambiente que vai ser commitado ───
# `.env.example` e `.env.sample` são para commitar mesmo — são o contrato.
# `.env`, `.env.local` e `.env.production` carregam valor real.
for envf in .env .env.local .env.production .env.prod .env.development; do
  [ -f "$envf" ] || continue
  if ! ignora '\.env' && ! ignora "$(printf '%s' "$envf" | sed 's/^\.//; s/\./\\./g')"; then
    add_finding "crit" "$envf existe e NÃO está no .gitignore — vai para o histórico no próximo commit. Segredo commitado é permanente: apagar depois não remove do histórico nem dos clones já feitos" "$envf" ""
  fi
done

# ─── 2. .gitignore ausente ou sem o essencial ───
if [ -z "$GITIGNORE" ]; then
  add_finding "high" "sem .gitignore — dependências, build e arquivos locais entram no repositório e poluem todo diff da equipe" ".gitignore" ""
else
  if [ -f "package.json" ] && ! ignora 'node_modules'; then
    add_finding "high" ".gitignore não exclui node_modules — dezenas de milhares de arquivos no repositório, e todo pull vira conflito" ".gitignore" ""
  fi
  if ! ignora '\.env'; then
    add_finding "high" ".gitignore não exclui .env — a próxima pessoa que criar um vai commitá-lo sem perceber" ".gitignore" ""
  fi
fi

# ─── 3. Nada guarda o merge ───
CI=0
for d in .github/workflows .gitlab-ci.yml .circleci azure-pipelines.yml Jenkinsfile .drone.yml; do
  if [ -d "$d" ] && [ -n "$(find "$d" -name '*.y*ml' 2>/dev/null | head -1)" ]; then CI=1; break; fi
  [ -f "$d" ] && { CI=1; break; }
done
if [ "$CI" -eq 0 ]; then
  add_finding "high" "sem pipeline de CI — nada verifica o código antes do merge, e em equipe isso significa que o main quebra sem ninguém saber quando" ".github/workflows/" ""
fi

# ─── 4. Ninguém sabe quem revisa ───
CODEOWNERS=0
for f in CODEOWNERS .github/CODEOWNERS docs/CODEOWNERS; do
  [ -f "$f" ] && { CODEOWNERS=1; break; }
done
[ "$CODEOWNERS" -eq 0 ] && \
  add_finding "low" "sem CODEOWNERS — o PR não encontra revisor por conta própria e fica parado esperando alguém se voluntariar" ".github/CODEOWNERS" ""

# ─── 5. PR sem formato ───
PRT=0
for f in .github/PULL_REQUEST_TEMPLATE.md .github/pull_request_template.md docs/PULL_REQUEST_TEMPLATE.md; do
  [ -f "$f" ] && { PRT=1; break; }
done
[ "$PRT" -eq 0 ] && \
  add_finding "low" "sem template de PR — cada autor descreve do seu jeito, e o revisor precisa reconstruir o contexto toda vez" ".github/PULL_REQUEST_TEMPLATE.md" ""

# ─── 6. Binário grande fora do .gitignore ───
# Git guarda cada versão inteira de arquivo binário. 5 MB versionados 20 vezes
# são 100 MB que todo clone baixa, para sempre.
if command -v find >/dev/null 2>&1; then
  GRANDES=$(find . -type f -size +5M \
    -not -path './.git/*' -not -path '*/node_modules/*' -not -path './dist/*' \
    -not -path './build/*' -not -path '*/.next/*' -not -path './.blindar*/*' \
    -not -path '*/coverage/*' -not -path '*/venv/*' -not -path '*/.venv/*' 2>/dev/null | head -5)
  while IFS= read -r g; do
    [ -z "${g:-}" ] && continue
    add_finding "med" "arquivo grande versionável ($(du -h "$g" 2>/dev/null | cut -f1)): git guarda cada versão inteira, e todo clone baixa todas para sempre" "$g" ""
  done <<EOF
$GRANDES
EOF
fi

if [ "${#FINDINGS[@]}" -gt 0 ]; then
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi

log_pass "repositório preparado para trabalho em equipe"
emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
