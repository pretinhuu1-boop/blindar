#!/usr/bin/env bash
# Materializa: decision-log — as decisões arquiteturais estão registradas, e o
# registro está completo?
#
# Origem: uma decisão tomada numa sessão é desfeita em outra porque o motivo não
# ficou em lugar nenhum. "Por que Postgres e não SQLite?", "por que essa fila?",
# "por que não usamos Redis aqui?" — sem resposta escrita, a pergunta volta e a
# resposta muda. Registro sem o MOTIVO é quase inútil: quem lê depois precisa
# saber o que foi considerado e descartado, não só o que ficou.
#
# O log vive VERSIONADO (docs/), não em .blindar/: decisão arquitetural tem de
# aparecer no diff, ser revisada no PR e sobreviver a um `rm -rf .blindar`.
BLINDAR_AGENT="check-decision-log"
source "$(dirname "$0")/_lib.sh"
log_section "Check: decision log / ADR"

# ─── 1. Onde mora o log ───
LOG_FILES=""
for cand in docs/decisions.md docs/DECISIONS.md docs/adr.md ADR.md DECISIONS.md; do
  [ -f "$cand" ] && LOG_FILES="$LOG_FILES $cand"
done
for d in docs/adr docs/adrs docs/decisions docs/architecture/decisions; do
  if [ -d "$d" ]; then
    found=$(find "$d" -maxdepth 1 -name '*.md' 2>/dev/null | sort | tr '\n' ' ')
    LOG_FILES="$LOG_FILES $found"
  fi
done
LOG_FILES=$(trim_ws "$LOG_FILES")

# ─── 2. Sem log: só cobra se o projeto TEM decisões a registrar ───
if [ -z "${LOG_FILES:-}" ]; then
  SIGNALS=0
  SIGNAL_LIST=""
  add_signal() { SIGNALS=$((SIGNALS+1)); SIGNAL_LIST="$SIGNAL_LIST $1"; }

  [ -f "docker-compose.yml" ] || [ -f "docker-compose.yaml" ] || [ -f "compose.yml" ] && add_signal "compose"
  grep -rqiE '"(bullmq|bull|celery|sidekiq|amqplib|kafkajs)"|^celery|amqp://' \
    package.json requirements.txt pyproject.toml Gemfile 2>/dev/null && add_signal "fila"
  grep -rqiE '"(pinecone|qdrant|weaviate|chromadb)"|pgvector' \
    package.json requirements.txt pyproject.toml 2>/dev/null && add_signal "vector-db"
  grep -rqiE '"(ioredis|redis)"|redis://' \
    package.json requirements.txt docker-compose.y*ml 2>/dev/null && add_signal "redis"
  [ -d "k8s" ] || [ -d "kubernetes" ] || [ -d "helm" ] && add_signal "k8s"

  if [ "$SIGNALS" -ge 2 ]; then
    add_finding "med" "projeto tem decisões arquiteturais a registrar ($(trim_ws "$SIGNAL_LIST")) mas não há decision log. Sem o motivo escrito, a escolha é refeita — e desfeita — a cada sessão. Crie docs/decisions.md" "docs/" ""
    log_warn "sem decision log, com $SIGNALS sinais arquiteturais:$SIGNAL_LIST"
    emit_result "$BLINDAR_AGENT" "failed" 1
    exit 1
  fi

  log_info "sem decision log e sem sinais arquiteturais suficientes — skipped"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

# ─── 3. Log existe: cada entrada precisa das 4 seções ───
# Uma ADR que diz só o que foi decidido não impede a decisão de ser revertida.
# O que impede é o que foi CONSIDERADO e por que foi descartado.
INCOMPLETE=0
for f in $LOG_FILES; do
  [ -f "$f" ] || continue

  # Entradas = headings de nível 2. Arquivo-por-ADR (docs/adr/0001-x.md) conta
  # como uma entrada só.
  ENTRIES=$(grep -c '^## ' "$f" 2>/dev/null | tail -1)
  ENTRIES=$(echo "$ENTRIES" | tr -d ' ')

  MISSING=""
  grep -qiE '^#{1,4}[[:space:]]*(contexto|problema|context|problem)' "$f" 2>/dev/null || MISSING="$MISSING contexto/problema"
  grep -qiE '^#{1,4}[[:space:]]*(alternativas|opções|options|considered)' "$f" 2>/dev/null || MISSING="$MISSING alternativas"
  grep -qiE '^#{1,4}[[:space:]]*(decisão|decisao|decision)' "$f" 2>/dev/null || MISSING="$MISSING decisão"
  grep -qiE '^#{1,4}[[:space:]]*(consequências|consequencias|consequences|trade-?offs)' "$f" 2>/dev/null || MISSING="$MISSING consequências"

  if [ -n "${MISSING// /}" ]; then
    add_finding "high" "decision log incompleto — faltam seções:$MISSING. Registro sem alternativas e consequências não impede a decisão de ser revertida por quem não sabe o que já foi descartado" "$f" ""
    INCOMPLETE=1
    log_fail "$f — faltam:$MISSING"
  else
    log_pass "$f — $ENTRIES entrada(s), estrutura completa"
  fi
done

if [ "$INCOMPLETE" -eq 1 ]; then
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi

emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
