#!/usr/bin/env bash
# Materializa: rollback-ready — dá para voltar o deploy ruim?
#
# `image: meuapp:latest` significa que não existe versão anterior nomeável. O
# deploy quebrou às 22h e a pergunta "volta para qual?" não tem resposta: a tag
# aponta para o que acabou de subir. Sobra reconstruir do commit anterior — se
# alguém souber qual é, se o build for reprodutível, e se der tempo.
#
# Rollback não é ter backup. É poder dizer, em trinta segundos e sem build,
# QUAL artefato estava no ar antes e como colocá-lo de volta.
BLINDAR_AGENT="check-rollback-ready"
source "$(dirname "$0")/_lib.sh"
log_section "Check: reversibilidade do deploy (tag versionada + rollback documentado)"

ALVOS=""
for f in docker-compose.yml docker-compose.yaml compose.yml compose.yaml \
         docker-compose.prod.yml docker-compose.production.yml \
         k8s/deployment.yaml k8s/deployment.yml fly.toml render.yaml \
         .github/workflows/deploy.yml .github/workflows/deploy.yaml \
         .github/workflows/release.yml Procfile; do
  [ -f "$f" ] && ALVOS="$ALVOS $f"
done
for f in .github/workflows/*.yml .github/workflows/*.yaml k8s/*.yaml k8s/*.yml; do
  [ -f "$f" ] || continue
  grep -qEi '(docker|image:|deploy|kubectl|helm)' "$f" 2>/dev/null || continue
  case " $ALVOS " in *" $f "*) ;; *) ALVOS="$ALVOS $f" ;; esac
done

if [ -z "$ALVOS" ]; then
  log_info "sem manifesto de deploy no repositório — não se aplica"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

# ─── 1. A imagem publicada tem versão? ───
FLUTUANTE=""
for f in $ALVOS; do
  L=$(grep -nEi '^[^#]*(image:[[:space:]]*[^[:space:]]+:latest|tags?:[[:space:]]*[^[:space:]]*:latest|-t[[:space:]]+[^[:space:]]+:latest|image:[[:space:]]*[a-z0-9./_-]+[[:space:]]*$)' "$f" 2>/dev/null | head -1)
  [ -n "$L" ] && { FLUTUANTE="$f:$L"; break; }
done

VERSIONADA=""
for f in $ALVOS; do
  grep -qEi '(:\$\{?(GITHUB_SHA|VERSION|TAG|IMAGE_TAG|CI_COMMIT|SHORT_SHA)|:v?[0-9]+\.[0-9]+\.[0-9]+|@sha256:|github\.sha)' "$f" 2>/dev/null && { VERSIONADA="$f"; break; }
done

if [ -n "$FLUTUANTE" ] && [ -z "$VERSIONADA" ]; then
  ARQ=$(printf '%s' "$FLUTUANTE" | cut -d: -f1)
  LN=$(printf '%s' "$FLUTUANTE" | cut -d: -f2)
  add_finding "med" \
    "Deploy publica imagem sem versão (tag :latest ou sem tag) — não existe artefato anterior nomeável para voltar. Marque cada build com o SHA do commit ou a versão semântica, e mantenha as N últimas no registry." \
    "$ARQ" "$LN"
elif [ -n "$VERSIONADA" ]; then
  log_pass "imagem publicada com tag versionada ($VERSIONADA)"
fi

# ─── 2. O procedimento está escrito? ───
# Rollback que só existe na cabeça de uma pessoa não existe às 3h da manhã.
DOC=$(grep -rIlEi 'rollback|revers[aã]o do deploy|voltar (a )?vers[aã]o|desfazer o deploy|helm rollback|kubectl rollout undo|revert deploy' \
  --include='*.md' --include='*.mdx' --include='*.txt' --include='*.yml' --include='*.yaml' --include='*.sh' \
  --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=.blindar \
  . 2>/dev/null | head -2)

if [ -z "$DOC" ]; then
  add_finding "med" \
    "Sem procedimento de rollback escrito (runbook, script ou passo no pipeline). Voltar um deploy ruim vira improviso na pior hora: descobrir qual era o commit bom, reconstruir, torcer para o build ser reprodutível." \
    "runbooks/" ""
else
  log_pass "procedimento de rollback documentado: $(printf '%s' "$DOC" | head -1)"
fi

if [ "${#FINDINGS[@]}" -gt 0 ]; then
  emit_result "$BLINDAR_AGENT" "failed" 0
  exit 0
fi
emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
