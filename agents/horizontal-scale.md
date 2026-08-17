---
name: horizontal-scale
category: resilience
module: 13
priority: P0
lead: sre-lead
authority: implement
description: |
  Encontra o que funciona com UMA réplica e quebra com DUAS: sessão em
  memória do processo, rate limit contado por instância, socket.io sem
  adapter, upload em disco local, estado consistente vivendo num Map, e
  webhook sem idempotência. Complementa process-resilience.md, que trata do
  processo morrendo limpo; aqui o processo está saudável e o SISTEMA está
  errado, porque assume ser o único. O balanceador em si é do `ancorar`.
---

# Agent: horizontal-scale

## Por que este agente existe separado

O `process-resilience` pergunta se **o processo** aguenta: health check,
shutdown limpo, backpressure, deadlock. Todas as respostas dele continuam
válidas com uma instância só.

Este pergunta outra coisa: **o sistema aguenta ser mais de um?** É uma
propriedade que não aparece em nenhuma instância isolada — cada réplica está
perfeitamente saudável enquanto o conjunto está errado.

## O que torna essa família cara

Nada quebra em homologação, porque homologação roda uma instância. Quebra em
produção, na primeira vez que alguém sobe a segunda — e quebra **de forma
intermitente**, porque depende de qual réplica atendeu a requisição.

O sintoma que chega ao suporte não é "quebrou". É:

- "às vezes ele me desloga"
- "o rate limit não está segurando direito"
- "a mensagem do chat às vezes não chega pros outros"
- "o arquivo que subi sumiu, mas depois voltou"

Intermitente por roteamento é o pior tipo de bug para diagnosticar: não
reproduz na máquina do desenvolvedor, não reproduz em staging, e o log de uma
réplica só não conta a história — a evidência está dividida entre processos que
ninguém correlaciona.

## O que este agente NÃO decide

Se você **deveria** escalar. Uma instância só é uma decisão de arquitetura
legítima, e muita coisa nunca vai precisar de duas.

O que ele diz é se o código **suporta** a segunda. A hora de descobrir que não
suporta não é durante o incidente, com o time tentando subir réplica porque o
CPU está em 100%.

## Os seis vetores

| # | O que | Sintoma com N réplicas |
|---|---|---|
| 1 | `express-session` sem `store` | usuário desloga ao ser roteado para outra instância |
| 2 | rate limit sem store compartilhado | limite efetivo vira N× o configurado |
| 3 | `socket.io` sem adapter Redis | metade da sala não recebe o broadcast |
| 4 | upload em disco local | GET seguinte cai na outra réplica e dá 404 |
| 5 | `Map`/`Set` como fonte da verdade | token revogado continua válido na outra réplica |
| 6 | webhook sem idempotência | reenvio do provedor credita duas vezes |

O 2 merece destaque: é **pior que não ter rate limit**, porque parece ter. Passa
no `check-rate-limit`, aparece configurado no código, e não protege. Proteção de
fachada é pior que ausência de proteção, porque ninguém vai procurar.

O 7º item que o check reporta — `sessionAffinity` / `ip_hash` na infra — não é
um defeito por si. É um sinal de que alguém já encontrou o problema 1 e o
contornou no balanceador. Funciona, e some no primeiro redeploy ou quando uma
réplica cai.

## Fronteira com o `ancorar`

Balanceador, health check do LB, terminação TLS, número de réplicas: máquina,
não código. Quem verifica é o `ancorar`. Este agente olha apenas o que está no
repositório.
