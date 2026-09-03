#!/usr/bin/env bash
# Materializa: idempotency-keys — o retry do cliente duplica o pedido.
#
# A rede não avisa a diferença entre "a requisição não chegou" e "a resposta não
# voltou". Do lado do cliente as duas parecem timeout, e a reação certa em uma
# delas — tentar de novo — é catastrófica na outra. Celular em elevador, 4G
# oscilando, usuário tocando o botão duas vezes: cria dois pedidos, duas
# cobranças, dois agendamentos no mesmo horário.
#
# A correção é velha e simples: o cliente manda uma chave única por INTENÇÃO
# (não por requisição), o servidor guarda o resultado da primeira e devolve o
# mesmo resultado nas repetições. Sem isso, "tentei de novo" e "quis duas vezes"
# são a mesma coisa para o servidor.
BLINDAR_AGENT="check-idempotency-keys"
source "$(dirname "$0")/_lib.sh"
log_section "Check: chave de idempotência em endpoints que criam estado"

# Endpoints POST que criam coisa com consequência: pedido, pagamento, cobrança,
# transferência, agendamento, assinatura.
CRIACAO=$(scan_src '(post\(|@Post\(|@app\.route\([^)]*POST|@router\.post|def post|methods=\[.POST|router\.post)[^;]*(order|pedido|payment|pagamento|charge|cobranca|cobrança|checkout|transfer|transferencia|transferência|subscription|assinatura|invoice|fatura|booking|agendamento|reserva|withdraw|saque|deposit)' \
  | grep -viE '(test|spec|mock|fixture)' | head -10)

if [ -z "$CRIACAO" ]; then
  log_info "nenhum endpoint de criação de estado com consequência financeira/operacional — não se aplica"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

ARQ=$(printf '%s\n' "$CRIACAO" | head -1 | cut -d: -f1)
LN=$(printf '%s\n' "$CRIACAO" | head -1 | cut -d: -f2)
QTD=$(printf '%s\n' "$CRIACAO" | grep -c . )
log_info "$QTD endpoint(s) de criação com consequência encontrados"

IDEM=$(scan_src '(Idempotency-?Key|idempotency_?key|idempotencyKey|idempotence|chave_?idempot|X-Request-Id[^;]*(dedup|unique)|dedup(licat)?ion_?key|request_?id[^;]*unique)' \
  | grep -viE '(test|spec|mock|fixture)' | head -3)

if [ -z "$IDEM" ]; then
  add_finding "med" \
    "Endpoint que cria estado com consequência (pedido/pagamento/cobrança/agendamento) sem chave de idempotência. Cliente em rede instável não distingue 'não chegou' de 'resposta não voltou': o retry cria a segunda cobrança. Aceite um Idempotency-Key por intenção, guarde o resultado da primeira execução e devolva o mesmo nas repetições." \
    "$ARQ" "$LN"
else
  log_pass "chave de idempotência presente ($(printf '%s\n' "$IDEM" | head -1 | cut -d: -f1))"
  # Chave recebida e nunca persistida: o servidor lê o cabeçalho e não usa.
  if ! scan_hit '(idempotency|idempotencia|idempotência|dedup)[^;]*(findUnique|findFirst|SELECT|get\(|exists|cache|redis|\.set\(|upsert|INSERT)'; then
    A=$(printf '%s\n' "$IDEM" | head -1 | cut -d: -f1)
    L=$(printf '%s\n' "$IDEM" | head -1 | cut -d: -f2)
    add_finding "low" "A chave de idempotência aparece no código, mas não há sinal de que ela seja PERSISTIDA e consultada (cache, tabela, upsert). Chave recebida e ignorada não deduplica nada." "$A" "$L"
  fi
fi

if [ "${#FINDINGS[@]}" -gt 0 ]; then
  emit_result "$BLINDAR_AGENT" "failed" 0
  exit 0
fi
emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
