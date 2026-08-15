#!/usr/bin/env bash
# Materializa: deployment-readiness — o compose está pronto pra virar produção
# numa VPS, ou só pra subir na máquina de quem escreveu?
#
# Escopo: o que é verificável no ARQUIVO. O que só se prova no host (firewall
# ativo, cert válido, backup fresco, vizinho saudável) é da skill irmã `ancorar`,
# que roda contra o servidor via SSH. O blindar define o estado desejado e para
# aí — não invoca o ancorar, não escreve em .ancorar/.
BLINDAR_AGENT="check-vps-readiness"
source "$(dirname "$0")/_lib.sh"
log_section "Check: prontidão do compose para VPS"

COMPOSE=""
for c in docker-compose.yml docker-compose.yaml compose.yml compose.yaml; do
  [ -f "$c" ] && COMPOSE="$COMPOSE $c"
done
COMPOSE=$(echo "$COMPOSE" | xargs)

if [ -z "${COMPOSE:-}" ]; then
  log_info "sem docker-compose — skipped"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

DB_IMAGE='image:[[:space:]]*["'"'"']?(docker\.io/)?(library/)?(postgres|mysql|mariadb|mongo|redis)'

for f in $COMPOSE; do
  grep -q '@blindar:vps-ok' "$f" 2>/dev/null && continue

  # 1. Porta de banco publicada no host. Em VPS isso normalmente significa
  #    exposta na internet: o default do Docker é bind em 0.0.0.0, e a regra
  #    publicada atravessa o ufw, que continua "ativo" e não protege nada.
  #    Serviço da mesma stack alcança pela rede interna do compose, sem publicar.
  while IFS=: read -r line content; do
    [ -z "${line:-}" ] && continue
    add_finding "high" "porta de banco publicada no host: $(echo "$content" | xargs) — o bind default do Docker é 0.0.0.0 e a regra publicada passa por cima do firewall de host. Serviço da mesma stack não precisa disso" "$f" "$line"
  done <<EOF
$(grep -nE '^[[:space:]]*-[[:space:]]*"?[0-9]+:(5432|3306|27017|6379|5433)"?[[:space:]]*$' "$f" 2>/dev/null)
EOF

  # 2. Tag flutuante: o que subiu hoje não é o que sobe no próximo deploy.
  while IFS=: read -r line content; do
    [ -z "${line:-}" ] && continue
    add_finding "med" "imagem sem tag fixa: $(echo "$content" | xargs) — deploy deixa de ser reprodutível e o rollback não tem para onde voltar" "$f" "$line"
  done <<EOF
$(grep -nE 'image:[[:space:]]*["'"'"']?[A-Za-z0-9._/-]+(:latest)?["'"'"']?[[:space:]]*$' "$f" 2>/dev/null | grep -vE 'image:[[:space:]]*["'"'"']?[A-Za-z0-9._/-]+:[A-Za-z0-9._-]+' ; grep -nE 'image:[[:space:]]*[^[:space:]]*:latest' "$f" 2>/dev/null)
EOF

  # 3. Banco sem volume nomeado: `docker compose down` recria o container e o
  #    dado do container anterior fica inalcançável. Não é backup — é perda.
  if grep -qE "$DB_IMAGE" "$f" 2>/dev/null && ! grep -qE '^[[:space:]]*volumes:' "$f" 2>/dev/null; then
    add_finding "high" "serviço de banco sem volume declarado — recriar o container descarta os dados" "$f" ""
  fi

  # 4. Sem política de restart: a VPS reinicia e a aplicação não volta.
  if ! grep -qE '^[[:space:]]*restart:' "$f" 2>/dev/null; then
    add_finding "med" "nenhum serviço com 'restart:' — após reboot da VPS ou OOM-kill a stack não sobe sozinha" "$f" ""
  fi

  # 5. Sem healthcheck: o orquestrador considera "de pé" um container que
  #    subiu o processo e não atende.
  if ! grep -qE '^[[:space:]]*healthcheck:' "$f" 2>/dev/null; then
    add_finding "med" "nenhum healthcheck declarado — container 'up' não é o mesmo que aplicação atendendo" "$f" ""
  fi
done

if [ "${#FINDINGS[@]}" -gt 0 ]; then
  log_fail "${#FINDINGS[@]} pendência(s) de prontidão para VPS"
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi

log_pass "compose pronto para VPS (portas, tags, volume, restart, healthcheck)"
emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
