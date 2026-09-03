---
name: outbound-queue-readiness
category: resilience
module: 13
priority: P2
lead: runtime-lead
authority: implement
description: |
  Efeito de saída (e-mail, webhook, notificação) rodando síncrono dentro da requisição, sem fila com retry e backoff. A latência do seu endpoint vira a do provedor mais lento, e a falha dele aparece como erro numa operação que já deu certo.
---

# Agent: outbound-queue-readiness

Enviar e-mail, disparar webhook, mandar notificação e postar em API de terceiro
têm três propriedades que não combinam com o ciclo de uma requisição HTTP:

- são **lentos** (centenas de milissegundos a segundos);
- falham por **motivo alheio** — o provedor caiu, não você;
- o cliente do outro lado **está esperando**.

Feito inline, o resultado é o pior dos dois mundos. A latência do seu endpoint
passa a ser a latência do provedor mais lento. E quando ele falha, o usuário vê
erro numa operação que **já deu certo**: o pedido foi criado, só o e-mail não
saiu. Ou pior — alguém "conserta" isso revertendo o pedido por causa do e-mail.

Com fila, o efeito de saída ganha o que precisa: retry com backoff, isolamento de
falha, e uma resposta imediata para quem está esperando.

## O que o check já garante

[`check-outbound-queue-readiness.sh`](../templates/checks/check-outbound-queue-readiness.sh):

| Situação | Severidade |
|---|---|
| Efeito de saída sem nenhuma fila no projeto | **med** |
| Há fila, mas este handler HTTP dispara direto | **med** |

O segundo caso é o mais frequente em projeto maduro: a infraestrutura foi
montada, e um caminho continuou inline. É justamente ele que vai falhar em
produção, porque ninguém lembra dele — "o projeto usa fila".

Auto-skip em projeto sem efeito de saída.

## O desenho mínimo

1. **A requisição grava a intenção e responde.** O usuário não espera pelo
   provedor.
2. **O worker executa com retry exponencial** e teto de tentativas.
3. **DLQ para o que esgotou** — mensagem que falhou cinco vezes precisa de olho
   humano, não de mais uma tentativa.
4. **O job é idempotente**: fila entrega ao menos uma vez, e "ao menos uma" às
   vezes é duas. Enviar o mesmo e-mail duas vezes é constrangedor; cobrar duas
   vezes é outra coisa (ver [`idempotency-keys`](idempotency-keys.md)).

## Quando inline é aceitável

Nem todo efeito de saída precisa de fila. Vale manter síncrono quando o usuário
**precisa do resultado para continuar** — validar um cupom no gateway, consultar
CEP, confirmar pagamento antes de mostrar a tela de sucesso.

Nesses casos o que não pode faltar é **timeout curto e fallback definido**. O
erro não é ser síncrono; é ser síncrono sem teto de espera.

## O que só se prova com o provedor fora do ar

| Verificar | Como |
|---|---|
| A operação principal sobrevive à falha do provedor | derrube o provedor em homologação e crie um pedido |
| O retry não vira tempestade | 10 mil mensagens falhando ao mesmo tempo com retry imediato |
| A DLQ é observada | mensagem na DLQ sem alerta é mensagem perdida com etapa extra |
| O consumidor acompanha a produção | fila que só cresce é queda com atraso |
