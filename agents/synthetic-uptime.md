---
name: synthetic-uptime
category: ops
module: 6
priority: P1
lead: sre-lead
authority: implement
description: |
  Monitor sintético externo — ping de fora. O /healthz responde de dentro: quando a máquina desliga, o certificado vence ou o DNS expira, não sobra ninguém para responder, e o silêncio fica indistinguível de "está tudo bem".
---

# Agent: synthetic-uptime

`/healthz` responde **de dentro**. Se o processo morreu, o disco encheu, o DNS
expirou, o certificado venceu ou a máquina desligou, não há ninguém dentro para
responder — e o silêncio é indistinguível de "está tudo bem".

Probe de liveness do Kubernetes tem o mesmo defeito quando o que caiu foi o
cluster. Todo monitoramento que roda dentro do sistema monitorado compartilha o
destino dele.

A única medição honesta de disponibilidade vem de fora: **um serviço em outra
rede batendo na URL pública em intervalo fixo, com alerta para um humano**.

## O que o check já garante

[`check-synthetic-uptime.sh`](../templates/checks/check-synthetic-uptime.sh):

| Situação | Severidade |
|---|---|
| Nenhum monitor sintético externo configurado | **med** |

Aceita: UptimeRobot, BetterStack, Pingdom, StatusCake, healthchecks.io, Cronitor,
Checkly, updown.io, Site24x7, Oh Dear, Datadog Synthetics, Grafana Synthetic
Monitoring, `blackbox_exporter`, Uptime Kuma, ou job de CI **agendado** batendo
numa URL externa.

O roster está marcado com `revisar semestralmente — últ. revisão: 2026-09`.
Provedor fora dele não é "sem monitor": é não classificado, e a mensagem do
achado diz o que o check aceita como prova.

Auto-skip em projeto sem serviço exposto.

## O que monitorar além do 200

Bater na raiz e conferir status 200 pega a queda total e mais nada. O conjunto
que pega o que realmente acontece:

| Verificação | O que pega |
|---|---|
| Rota que toca o **banco** | app de pé com banco fora — o `/healthz` raso não vê |
| Validade do **certificado TLS** | expiração de certificado é queda total, agendada, e evitável |
| Resolução de **DNS** | domínio que não renovou derruba tudo com o servidor intacto |
| Conteúdo esperado no corpo | página de erro do proxy também devolve 200 |
| Latência, não só disponibilidade | 8 segundos de resposta é queda para o usuário |
| De **duas regiões** | uma sonda só não distingue "caiu" de "a sonda perdeu rede" |

## O detalhe que decide

**O alerta precisa sair por um canal que não depende da sua infraestrutura.** Se
o e-mail de alerta passa pelo servidor que caiu, você descobre a queda quando ele
voltar.

## O que só se prova exercitando

| Verificar | Como |
|---|---|
| O alerta chega | derrube o serviço em homologação de propósito |
| Chega fora do horário comercial | o plantão real é às 3h de domingo |
| Não há falso positivo crônico | monitor que alerta toda semana já foi silenciado |
