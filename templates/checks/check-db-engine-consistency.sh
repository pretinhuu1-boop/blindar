#!/usr/bin/env bash
# Materializa: db-migration-guardian — engine de banco DECLARADA na infra × engine
# USADA no caminho de runtime.
#
# Bug real que originou o check: pedir "migra de SQLite pra PostgreSQL no container"
# e receber de volta um docker-compose com Postgres, um README falando de Postgres
# e um código que continua abrindo SQLite. A migração aconteceu no papel, não no
# processo. Postgres no compose NÃO é prova de que a aplicação usa Postgres.
BLINDAR_AGENT="check-db-engine-consistency"
source "$(dirname "$0")/_lib.sh"
log_section "Check: engine de banco (declarada na infra × usada no runtime)"

if ! command -v rg >/dev/null 2>&1; then
  log_fail "ripgrep (rg) requerido"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

# Globs de INFRA: onde a engine é DECLARADA. Docs entram (README declara intenção),
# testes não (fixture de teste não declara a engine de produção).
INFRA_GLOBS=(
  -g '!node_modules' -g '!vendor' -g '!dist' -g '!build' -g '!.next' -g '!coverage'
  -g '!.blindar' -g '!.git' -g '!**/fixtures/**'
)
# Globs de RUNTIME: onde a engine é USADA de verdade. Testes e fixtures FORA —
# SQLite em teste é legítimo e não é o alvo deste check.
PROD_GLOBS=(
  "${INFRA_GLOBS[@]}"
  -g '!**/*.test.*' -g '!**/*.spec.*' -g '!**/__tests__/**' -g '!**/__mocks__/**'
  -g '!**/test/**' -g '!**/tests/**' -g '!**/*.md' -g '!**/spec/**'
)
load_intelligence_globs "$BLINDAR_AGENT"

# ─── 1. PostgreSQL é DECLARADO em algum lugar da infra? ───
PG_EVIDENCE=$(mktemp)
{
  rg -n -i 'image:[[:space:]]*["'"'"']?(docker\.io/)?(library/)?(postgres|postgis|timescale)' "${INFRA_GLOBS[@]}" "${INTEL_GLOBS[@]}"
  rg -n 'postgres(ql)?://' "${INFRA_GLOBS[@]}" "${INTEL_GLOBS[@]}"
  rg -n 'provider[[:space:]]*=[[:space:]]*"postgresql"' "${INFRA_GLOBS[@]}" "${INTEL_GLOBS[@]}"
  rg -n 'django\.db\.backends\.postgresql' "${INFRA_GLOBS[@]}" "${INTEL_GLOBS[@]}"
} > "$PG_EVIDENCE" 2>/dev/null || true
PG_COUNT=$(wc -l < "$PG_EVIDENCE" 2>/dev/null || echo 0)
PG_COUNT=$(echo "$PG_COUNT" | tr -d ' ')

# ─── 2. SQLite aparece no CAMINHO DE RUNTIME? ───
# Cada padrão abaixo é uso efetivo, não menção. String literal, nunca "o arquivo
# fala de sqlite" — comentário casa com heurística frouxa e vira falso positivo.
SQLITE_EVIDENCE=$(mktemp)
{
  rg -n '(require|from|import)[^\n]*["'"'"'](better-)?sqlite3?["'"'"']' "${PROD_GLOBS[@]}" "${INTEL_GLOBS[@]}"
  rg -n 'provider[[:space:]]*=[[:space:]]*"sqlite"' "${PROD_GLOBS[@]}" "${INTEL_GLOBS[@]}"
  rg -n 'sqlite:/' "${PROD_GLOBS[@]}" "${INTEL_GLOBS[@]}"
  rg -n 'django\.db\.backends\.sqlite3' "${PROD_GLOBS[@]}" "${INTEL_GLOBS[@]}"
  rg -n 'DATABASE_URL[[:space:]]*=[[:space:]]*["'"'"']?file:' "${PROD_GLOBS[@]}" "${INTEL_GLOBS[@]}"
} > "$SQLITE_EVIDENCE" 2>/dev/null || true
# Marker de exceção explícita
grep -v "@blindar:sqlite-ok" "$SQLITE_EVIDENCE" > "$SQLITE_EVIDENCE.f" 2>/dev/null || true
mv "$SQLITE_EVIDENCE.f" "$SQLITE_EVIDENCE" 2>/dev/null || true
SQLITE_COUNT=$(wc -l < "$SQLITE_EVIDENCE" 2>/dev/null || echo 0)
SQLITE_COUNT=$(echo "$SQLITE_COUNT" | tr -d ' ')

# ─── 3. Projeto sem banco relacional nenhum → não se aplica ───
if [ "$PG_COUNT" -eq 0 ] && [ "$SQLITE_COUNT" -eq 0 ]; then
  log_info "nenhuma engine relacional detectada — skipped"
  rm -f "$PG_EVIDENCE" "$SQLITE_EVIDENCE"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

# ─── 4. REGRA PRINCIPAL: infra diz Postgres, runtime usa SQLite ───
# Este é o estado "migrei" que não migrou. Crítico: todo relatório a jusante vai
# afirmar Postgres, e a afirmação será falsa.
if [ "$PG_COUNT" -gt 0 ] && [ "$SQLITE_COUNT" -gt 0 ]; then
  log_fail "DRIFT: PostgreSQL declarado na infra ($PG_COUNT sinais) mas SQLite ativo no runtime ($SQLITE_COUNT sinais)"
  while IFS=: read -r file line content; do
    [ -z "$file" ] && continue
    add_finding "crit" "engine drift: infra declara PostgreSQL mas o runtime abre SQLite aqui — $(echo "$content" | xargs)" "$file" "$line"
  done < "$SQLITE_EVIDENCE"
  log_info "Declaração de Postgres encontrada em:"
  head -5 "$PG_EVIDENCE" | while IFS= read -r l; do log_info "  $l"; done
  rm -f "$PG_EVIDENCE" "$SQLITE_EVIDENCE"
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi

# ─── 5. Prisma: provider e connection string discordam ───
if [ -f "prisma/schema.prisma" ]; then
  PROVIDER=$(rg -n -o 'provider[[:space:]]*=[[:space:]]*"[a-z]+"' prisma/schema.prisma 2>/dev/null | head -1 | sed -E 's/.*"([a-z]+)".*/\1/')
  if [ "${PROVIDER:-}" = "postgresql" ]; then
    URL_HIT=$(rg -n 'DATABASE_URL[[:space:]]*=[[:space:]]*["'"'"']?file:' -g '!node_modules' -g '!.git' 2>/dev/null | head -1)
    if [ -n "${URL_HIT:-}" ]; then
      f=$(echo "$URL_HIT" | cut -d: -f1); l=$(echo "$URL_HIT" | cut -d: -f2)
      add_finding "crit" "prisma provider=postgresql mas DATABASE_URL aponta para file: (SQLite). O client não conecta no Postgres" "$f" "$l"
    fi
  fi
fi

rm -f "$PG_EVIDENCE" "$SQLITE_EVIDENCE"

if [ "${#FINDINGS[@]}" -gt 0 ]; then
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi

log_pass "engine de banco consistente entre infra e runtime"
emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
