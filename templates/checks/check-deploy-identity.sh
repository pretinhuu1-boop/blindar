#!/usr/bin/env bash
# check-deploy-identity — o artefato NO AR é o commit que foi auditado?
#
# Esta é a lição mais cara do histórico deste projeto: 17 checks passaram contra
# a imagem errada. Auditar o código e subir outro artefato produz um verde
# perfeitamente honesto sobre uma coisa que ninguém está usando.
#
# scripts/reproducibility.js e scripts/sbom-build.js já hasheiam o REPOSITÓRIO.
# Nenhum deles pergunta o que está rodando. Este check pergunta.
#
# Como funciona: bate no health (ou em --health) e procura, no corpo, uma
# identidade de build — commit, sha, revision, version, build. Compara com o
# git HEAD local. Três desfechos:
#
#   • bate            → DEPLOYMENT pode ser PASS
#   • diverge         → crit: a auditoria não é sobre o que está no ar
#   • não declara     → high: impossível provar qualquer relação entre os dois
#
# "Não declara" é high de propósito. Sem identidade exposta, todo veredito de
# runtime é sobre um artefato anônimo — e um verde sobre artefato anônimo é o
# mesmo verde-sem-medida que este projeto existe para recusar.
#
# Uso: bash check-deploy-identity.sh --url http://localhost:3000 [--health /healthz]

BLINDAR_AGENT="check-deploy-identity"
STARTED_AT=$(date -u +%s)
source "$(dirname "$0")/_lib.sh"
source "$(dirname "$0")/_dyn.sh"
declare_dynamic

log_section "Identidade do artefato no ar (imagem == commit auditado?)"

dyn_parse_args "$@"

dyn_need_curl   || { emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0; }
dyn_need_target || { emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0; }

LOCAL_SHA=$(git rev-parse HEAD 2>/dev/null || echo "")
if [ -z "$LOCAL_SHA" ]; then
  not_exercised "diretorio nao e repositorio git — sem commit local nao ha com o que comparar"
  log_warn "Sem git HEAD local — nada com que comparar."
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi
SHORT_SHA=$(printf '%s' "$LOCAL_SHA" | cut -c1-7)

HEALTH_URL="${DYN_TARGET%/}${DYN_HEALTH}"
RESP=$(dyn_probe_body "$HEALTH_URL" 10)
CODE=$(dyn_code_of "$RESP")
BODY=$(dyn_body_of "$RESP")

case "$CODE" in
  2*) : ;;
  *)
    not_exercised "health respondeu $CODE — nao foi possivel ler a identidade do artefato no ar"
    log_warn "$HEALTH_URL devolveu $CODE."
    emit_result "$BLINDAR_AGENT" "skipped" 0
    exit 0
    ;;
esac

# O artefato respondeu: o exercício aconteceu, independente do que venha a seguir.
mark_exercised
log_info "Health respondeu $CODE em $HEALTH_URL"

# Procura identidade no corpo. Aceita as chaves usuais e valores de 7 a 40 hex.
IDENT=$(printf '%s' "$BODY" \
  | grep -oiE '"(commit|commit_sha|sha|git_sha|revision|rev|build|build_sha|version)"[[:space:]]*:[[:space:]]*"[0-9a-f]{7,40}"' \
  | head -1 \
  | sed -E 's/.*"([0-9a-f]{7,40})"/\1/')

# Fallback: header dedicado, comum em quem expõe build via proxy.
if [ -z "$IDENT" ]; then
  IDENT=$(curl -s -I --max-time 10 "$HEALTH_URL" 2>/dev/null \
    | grep -oiE '^x-(commit|build|revision|git)-?(sha)?:[[:space:]]*[0-9a-f]{7,40}' \
    | head -1 | grep -oiE '[0-9a-f]{7,40}$')
fi

FAIL=0

if [ -z "$IDENT" ]; then
  add_finding "high" "O artefato no ar não declara identidade de build em ${DYN_HEALTH} (nem chave commit/sha/revision/version no corpo, nem header X-Commit-Sha). Sem isso não há como provar que o que foi auditado é o que está rodando — e foi exatamente assim que 17 checks passaram contra a imagem errada. Exponha o SHA do commit no health" "" ""
  FAIL=1
  DEPLOYED="null"
  MATCH="false"
else
  DEPLOYED="\"$IDENT\""
  log_info "Artefato no ar declara: $IDENT   |   git HEAD local: $SHORT_SHA"
  # Compara pelo prefixo comum: o deploy pode expor 7, 8, 12 ou 40 caracteres.
  LEN=$(printf '%s' "$IDENT" | wc -c | tr -d ' ')
  LEN=$((LEN - 0))
  LOCAL_CUT=$(printf '%s' "$LOCAL_SHA" | cut -c1-"$LEN")
  if [ "$(printf '%s' "$IDENT" | tr 'A-Z' 'a-z')" = "$(printf '%s' "$LOCAL_CUT" | tr 'A-Z' 'a-z')" ]; then
    MATCH="true"
    log_pass "Artefato no ar == commit auditado ($SHORT_SHA)"
  else
    MATCH="false"
    add_finding "crit" "O artefato no ar é o commit '$IDENT', mas o código auditado nesta rodada é '$SHORT_SHA'. Todo veredito desta execução é sobre um artefato que não está rodando: os checks passaram contra uma imagem, e outra está servindo tráfego" "" ""
    FAIL=1
  fi
fi

# Sujeira na árvore torna até o "bate" parcial: o que roda é o commit, não o
# working tree que acabou de ser auditado.
DIRTY="false"
if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
  DIRTY="true"
  add_finding "med" "A árvore de trabalho tem alterações não commitadas: mesmo com o SHA batendo, o código auditado agora não é byte-a-byte o do artefato no ar" "" ""
fi

mkdir -p "$BLINDAR_DIR" 2>/dev/null || true
cat > "$BLINDAR_DIR/deploy-identity.json" <<EOF
{
  "schema": "blindar/deploy-identity@v1",
  "ran_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "target": "$HEALTH_URL",
  "audited_commit": "$LOCAL_SHA",
  "deployed_identity": $DEPLOYED,
  "match": $MATCH,
  "working_tree_dirty": $DIRTY
}
EOF

if [ "$FAIL" -eq 1 ]; then
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi
emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
