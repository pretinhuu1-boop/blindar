#!/usr/bin/env bash
# Wrapper API: solution-architect — vê o projeto (grafo + stack) e entrega o que
# FALTA por área, priorizado. Diferente de `architect` (avalia decisões): este
# lista o que construir. Blindar não só audita — cria o que não existe.
BLINDAR_AGENT="check-solution-architect"
source "$(dirname "$0")/_lib.sh"
source "$(dirname "$0")/_api_wrapper.sh"
log_section "Check: solution-architect (entrega o que falta por área)"

# Garante o grafo (a principal evidência — "vê o projeto")
GRAPH=".blindar/graph.json"
if [ ! -f "$GRAPH" ] && command -v node >/dev/null 2>&1; then
  GB="$(dirname "$0")/../../scripts/graph-build.js"
  [ -f "$GB" ] && node "$GB" --dir . >/dev/null 2>&1 || true
fi

EVIDENCE=""
[ -f "$GRAPH" ] && EVIDENCE+="=== grafo do projeto (.blindar/graph.json) ===\n$(head -c 9000 "$GRAPH")\n\n"
[ -f "README.md" ] && EVIDENCE+="=== README.md ===\n$(head -c 4000 README.md)\n\n"
[ -f "package.json" ] && EVIDENCE+="=== package.json ===\n$(head -c 3000 package.json)\n\n"
[ -f "pyproject.toml" ] && EVIDENCE+="=== pyproject.toml ===\n$(head -c 2000 pyproject.toml)\n\n"
[ -f "${BLINDAR_DIR:-.blindar}/scan.json" ] && EVIDENCE+="=== stack scan ===\n$(head -c 3000 "${BLINDAR_DIR:-.blindar}/scan.json")\n\n"

if [ -z "$EVIDENCE" ]; then
  log_warn "Sem evidência coletável"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

SYSTEM="Você é o agente solution-architect do blindar. Você VÊ o projeto pelo grafo
de conhecimento + stack e entrega, por ÁREA, o que FALTA pra ele estar completo,
seguro e escalável — priorizado por importância (crit/high/med/low).

Cubra estas áreas e aponte lacunas concretas (não genéricas):
- Segurança (authz, validação, secrets, rate-limit, headers) — PRIORIDADE MÁXIMA
- Superfície interna×externa (interna nunca aceita externa; externa protegida)
- Escalabilidade (filas pra trabalho assíncrono, cache, N+1, connection pool)
- Resiliência/fallback (timeout, circuit breaker, retry, health, 'se caiu como volta')
- Dados (migrations, soft-delete, audit log, backup/DR, tenant isolation)
- Observabilidade (logs estruturados, métricas, tracing, alertas)
- UX fluida (loading/skeleton, empty state, erro amigável, timeout de sessão)
- Testes (unit/e2e, smoke de runtime, testes de ataque)
- Conformidade (delegue detalhe ao regulatory-mapper, só sinalize se há dado sensível)

Para cada lacuna: severity, message (o que falta e por quê dói), fix (o que
construir). NÃO invente o que já existe no grafo. Foque no que está AUSENTE."

blindar_api_check "$BLINDAR_AGENT" "$SYSTEM" "$EVIDENCE"
