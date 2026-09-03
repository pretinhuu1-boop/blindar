---
name: graceful-shutdown
category: resilience
module: 13
priority: P1
lead: runtime-lead
authority: implement
description: |
  SIGTERM drena o que está em voo antes de sair. Sem handler, todo deploy corta requisição, transação e mensagem de fila no meio — e o sintoma vira "erro intermitente que ninguém reproduz", proporcional ao tráfego.
---

# Agent: graceful-shutdown

Orquestrador — Docker, Kubernetes, systemd, provedor de PaaS — manda `SIGTERM` e
espera alguns segundos antes do `SIGKILL`. Um processo que ignora o `SIGTERM` é
morto no meio do que estava fazendo:

- requisição sem resposta (o cliente vê erro de rede);
- transação sem commit **nem rollback**, segurando lock até o timeout;
- mensagem consumida da fila e nunca processada;
- conexão de banco pendurada até o pool do outro lado expirar.

Nada disso aparece em teste, porque o teste não reinicia o processo no meio da
carga. Aparece em produção, **a cada deploy, em proporção ao tráfego** — e vira
"erro intermitente que ninguém reproduz".

## O que o check já garante

[`check-graceful-shutdown.sh`](../templates/checks/check-graceful-shutdown.sh):

| Situação | Severidade |
|---|---|
| Nenhum handler de `SIGTERM`/`SIGINT` | **med** |
| Handler que chama `process.exit` direto | **med** |
| Handler sem fechamento de servidor, pool ou consumidor | **med** |
| `CMD ["npm", "start"]` — gerenciador como PID 1 | **med** |

Auto-skip em projeto sem processo de longa duração.

## Os dois modos de falha silenciosa

**Handler que só sai mais rápido.** `process.on("SIGTERM", () => process.exit(0))`
é *pior* que não ter handler: transforma um kill em dez segundos num kill
imediato, e parece resolvido. O código existe, a revisão aprova, e o
comportamento piorou.

**Sinal que nunca chega.** `CMD ["npm", "start"]` faz o `npm` ser o PID 1. Ele
recebe o `SIGTERM` e **não repassa** ao filho. O handler está lá, correto,
testado — e nunca é chamado. Chame o runtime direto (`CMD ["node", "src/server.js"]`)
ou use um init (`tini`, `docker run --init`).

## A ordem que funciona

1. **Marcar como não-pronto** (`/health/ready` responde 503) e esperar o
   balanceador tirar da rotação. Fechar antes disso é cortar tráfego que ainda
   está sendo enviado.
2. **Parar de aceitar conexão nova** (`server.close()`), mantendo as em voo.
3. **Esperar as requisições em curso**, com teto — 15 a 25 segundos, menor que o
   `terminationGracePeriodSeconds` do orquestrador.
4. **Parar consumidores de fila** e devolver o que não foi processado.
5. **Fechar o pool de banco** e clientes externos.
6. Sair com 0.

O passo 1 é o mais esquecido, e é o único que evita erro visível ao usuário.

## O que só se prova exercitando

| Verificar | Como |
|---|---|
| Nenhum 502 durante o deploy | rampa de carga + `kubectl rollout restart` |
| A janela do handler cabe na do orquestrador | handler de 30s com grace de 10s é kill igual |
| Job longo sobrevive ou é devolvido | mate o worker no meio de um job e veja se ele volta |
