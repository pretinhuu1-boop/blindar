---
name: idempotency-keys
category: api
module: 4
priority: P1
lead: chief-architect
authority: implement
description: |
  Chave de idempotência em endpoint que cria estado com consequência (pedido, pagamento, cobrança, agendamento). Sem ela, o retry do cliente em rede instável cria a segunda cobrança — e "tentei de novo" fica indistinguível de "quis duas vezes".
---

# Agent: idempotency-keys

A rede não avisa a diferença entre "a requisição não chegou" e "a resposta não
voltou". Do lado do cliente as duas parecem timeout — e a reação certa em uma
delas, tentar de novo, é catastrófica na outra.

Celular em elevador, 4G oscilando, usuário tocando o botão duas vezes porque nada
aconteceu: dois pedidos, duas cobranças, dois agendamentos no mesmo horário. O
servidor fez exatamente o que foi pedido, duas vezes, e não tinha como saber que
era a mesma intenção.

A correção é velha e simples: **o cliente manda uma chave única por INTENÇÃO** —
não por requisição — **o servidor guarda o resultado da primeira execução e
devolve o mesmo resultado nas repetições**.

## O que o check já garante

[`check-idempotency-keys.sh`](../templates/checks/check-idempotency-keys.sh):

| Situação | Severidade |
|---|---|
| Endpoint de criação com consequência sem chave de idempotência | **med** |
| Chave recebida mas sem sinal de que é persistida e consultada | **low** |

Procura rotas POST cujo nome indica consequência: pedido, pagamento, cobrança,
checkout, transferência, assinatura, fatura, agendamento, reserva, saque,
depósito.

Auto-skip quando não há endpoint dessa natureza — CRUD comum não precisa disso, e
cobrar ali seria ruído.

## Chave por intenção, não por requisição

É o erro mais comum da implementação ingênua: gerar a chave no momento do envio.
Aí cada retry manda uma chave nova, e a deduplicação não acontece — o mecanismo
está lá e não protege nada.

A chave nasce **quando o usuário decide**, no cliente, e sobrevive a todas as
tentativas daquela decisão. Um `crypto.randomUUID()` guardado no estado do
formulário, não gerado dentro do `fetch`.

## O contrato do lado do servidor

| Situação | Resposta |
|---|---|
| Chave nova | executa, guarda `(chave → resposta, status)`, responde |
| Chave repetida, execução concluída | devolve a **mesma** resposta, mesmo status |
| Chave repetida, execução em andamento | `409` ou espera — nunca executa em paralelo |
| Mesma chave, **corpo diferente** | `422`: é bug do cliente, não retry |

O último caso é o que separa implementação séria de aparência de implementação.
Sem ele, um cliente com bug reusa a chave e recebe silenciosamente a resposta da
operação errada.

**Expiração**: 24h costuma bastar. Guardar para sempre transforma a tabela de
idempotência no maior objeto do banco.

## O que só se prova sob carga

| Verificar | Como |
|---|---|
| Duas requisições **simultâneas** com a mesma chave | só uma executa — exige constraint única, não `SELECT` antes do `INSERT` |
| A resposta guardada é a **completa** | devolver `200` vazio no retry quebra o cliente |
| Idempotência sobrevive ao restart | guardada só em memória some no deploy |
