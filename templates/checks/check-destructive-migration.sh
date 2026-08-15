#!/usr/bin/env bash
# Materializa: risk-engine — migration destrutiva SEM caminho de volta.
#
# Origem: "como desfazer?" é a pergunta que separa uma mudança arriscada de uma
# mudança irreversível. DROP COLUMN sem down migration não tem resposta: o dado
# já não existe quando alguém descobre que era necessário. O rollback do deploy
# volta o código, não a coluna.
#
# Este check NÃO reprova destruição — reprova destruição irreversível. Migration
# destrutiva COM rollback declarado passa; quem decide se ela deve rodar é o
# gate de risco da Fase 04, não um grep.
BLINDAR_AGENT="check-destructive-migration"
source "$(dirname "$0")/_lib.sh"
log_section "Check: migration destrutiva sem rollback"

# Localiza migrations nos layouts mais comuns.
MIGRATIONS=$(find . \
  \( -path '*/migrations/*' -o -path '*/migrate/*' -o -path '*/versions/*' \) \
  \( -name '*.sql' -o -name '*.py' -o -name '*.rb' -o -name '*.ts' -o -name '*.js' \) \
  -not -path '*/node_modules/*' -not -path '*/.git/*' -not -path '*/.blindar/*' \
  2>/dev/null | sort)

if [ -z "${MIGRATIONS:-}" ]; then
  log_info "nenhuma migration encontrada — skipped"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

# DDL que destrói dado. ALTER ... DROP COLUMN entra; DROP INDEX não (índice
# se recria a partir do dado, coluna não).
DESTRUCTIVE='DROP[[:space:]]+TABLE|DROP[[:space:]]+COLUMN|DROP[[:space:]]+SCHEMA|DROP[[:space:]]+DATABASE|TRUNCATE[[:space:]]+|DROP[[:space:]]+TYPE'

# O arquivo declara um caminho de volta?
has_rollback() {
  local f="$1"
  case "$f" in
    *.py)
      # Alembic: downgrade() com corpo real. `pass` é ausência de rollback
      # escrita como se fosse rollback — pior que não ter, porque parece ter.
      awk '/^[[:space:]]*def[[:space:]]+downgrade/{flag=1;next}
           flag && /^[[:space:]]*def[[:space:]]/{flag=0}
           flag && !/^[[:space:]]*(pass|#|""")?[[:space:]]*$/ && !/^[[:space:]]*pass[[:space:]]*$/{found=1}
           END{exit !found}' "$f" 2>/dev/null && return 0
      ;;
    *.rb|*.ts|*.js)
      grep -qE '(def[[:space:]]+down|^[[:space:]]*(async[[:space:]]+)?(function[[:space:]]+)?down[[:space:]]*[:(=])' "$f" 2>/dev/null && return 0
      ;;
  esac
  # Marcadores de down no próprio SQL (goose, sql-migrate, dbmate)
  grep -qiE '^--[[:space:]]*\+?(goose|migrate)?[[:space:]]*Down' "$f" 2>/dev/null && return 0
  # Arquivo irmão .down.sql
  [ -f "${f%.sql}.down.sql" ] && return 0
  [ -f "$(dirname "$f")/down.sql" ] && return 0
  return 1
}

FOUND=0
for m in $MIGRATIONS; do
  [ -f "$m" ] || continue
  # Exceção explícita, com motivo escrito no próprio arquivo
  grep -q '@blindar:destructive-ok' "$m" 2>/dev/null && continue

  HITS=$(grep -inE "$DESTRUCTIVE" "$m" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*(--|#)' | head -5)
  [ -z "${HITS:-}" ] && continue
  FOUND=1

  if has_rollback "$m"; then
    log_info "destrutiva com rollback declarado: $m"
    continue
  fi

  while IFS=: read -r line content; do
    [ -z "${line:-}" ] && continue
    add_finding "crit" "migration destrutiva sem rollback: $(echo "$content" | xargs) — o deploy volta o código, não o dado apagado. Declare o down/downgrade, ou justifique com '@blindar:destructive-ok <motivo>'" "$m" "$line"
  done <<EOF
$HITS
EOF
done

if [ "${#FINDINGS[@]}" -gt 0 ]; then
  log_fail "${#FINDINGS[@]} operação(ões) destrutiva(s) sem caminho de volta"
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi

if [ "$FOUND" -eq 1 ]; then
  log_pass "operações destrutivas encontradas, todas com rollback declarado"
else
  log_pass "nenhuma operação destrutiva nas migrations"
fi
emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
