---
name: chaos-run
category: resilience
module: 13
priority: P1
lead: sre-lead
authority: validate
description: |
  Chaos EXECUTADO. Congela a dependencia com docker pause e mede tres coisas que
  nenhuma leitura de codigo responde: quanto o health pendura, se a rota
  independente continua viva, e se o sistema volta sozinho. Materializa em check
  o que chaos-engineering.md so prescrevia.
---

# chaos-run

## Por que este agente existe separado do `chaos-engineering`

`chaos-engineering.md` e o playbook: GameDay, hipotese, blast radius planejado,
staging, "6+ meses de producao". Ele descreve a **disciplina**.

Este agente e a **execucao minima** dela, e roda em qualquer projeto com Docker
- inclusive num MVP, onde o playbook completo nao se aplica. A diferenca e a
mesma entre ter um plano de evacuacao e ja ter feito o simulado uma vez.

## O que o check mede

| Medicao | Pergunta | Reprova quando |
|---|---|---|
| Latencia da falha | quanto o health pendura com a dependencia congelada | > `BLINDAR_CHAOS_MAX_HANG_MS` (5s) |
| Blast radius | a rota que nao depende dela continua viva | rota independente cai junto |
| Recuperacao | volta sozinho ao descongelar | nao volta em `BLINDAR_CHAOS_MAX_RECOVER_S` (60s) |

## Por que `docker pause` e nao `docker stop`

`stop` fecha o socket: quem chama recebe `ECONNREFUSED` imediatamente, e
praticamente todo cliente trata esse caso. `pause` congela o processo com o
socket **aberto**: ninguem recebe RST, e quem espera resposta espera para
sempre.

E o modo de falha que mais doi e o menos coberto por teste. Um pool sem timeout
de conexao esgota em minutos, e a aplicacao inteira para por causa de uma
dependencia que nem chegou a cair.

## Seguranca do experimento

O check **nao** congela container por semelhanca de nome. Ele so toca o que
esta amarrado ao alvo - mesmo projeto compose de quem publica a porta - ou o que
o operador passou explicitamente em `--service`.

Isso nao e preciosismo: ao exercitar este proprio check pela primeira vez, a
selecao por padrao de nome congelou um Redis de outro projeto da maquina. Um
check de resiliencia causando o incidente que deveria estar medindo.

`dyn_freeze` sempre instala `trap ... EXIT INT TERM`: Ctrl+C no meio do
experimento descongela antes de sair.

## Quando o resultado e NOT EXERCISED

Sem alvo, sem Docker, sem dependencia amarrada, ou com o alvo ja doente antes de
congelar nada - o check **nao** sai `passed`. Ele sai `skipped` com o motivo, e
o gate `RESILIENCE` fica `NOT EXERCISED`.

Medir degradacao a partir de um sistema que ja estava quebrado nao mede nada, e
dizer "passou" nesse caso seria pior que nao rodar.
