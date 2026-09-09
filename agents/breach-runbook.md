---
name: breach-runbook
category: compliance
module: 8
priority: P1
lead: privacy-lead
authority: implement
description: |
  Runbook de notificação de incidente/vazamento. LGPD: 3 dias úteis para ANPD e titulares (Res. CD/ANPD 15/2024). GDPR: 72h. O relógio começa quando alguém descobre — de madrugada, sem tempo de decidir quem assina e o que se diz.
---

# Agent: breach-runbook

A LGPD dá prazo de **3 dias úteis** para comunicar a ANPD e os titulares
(Resolução CD/ANPD nº 15/2024); o GDPR dá **72 horas**. Esse relógio começa a
correr quando a organização toma conhecimento — no meio da madrugada, com o time
ainda tentando entender o que aconteceu.

Quem improvisa o comunicado nessas condições erra o escopo (diz "não houve
vazamento de senha" antes de conferir), erra o prazo, ou fala demais.

Runbook não é burocracia: é a decisão já tomada para o momento em que não vai dar
tempo de tomá-la.

## O que o check já garante

[`check-breach-runbook.sh`](../templates/checks/check-breach-runbook.sh):

| Situação | Severidade |
|---|---|
| Sem runbook de incidente/vazamento | **med** |
| Runbook sem prazo explícito | **low** |
| Runbook sem responsável nomeado | **low** |

Auto-skip em projeto sem sinal de titular de dado.

## O que o runbook precisa ter

| Seção | Por quê |
|---|---|
| **Quem declara** o incidente | sem uma pessoa nomeada, todo mundo espera outro decidir |
| **Como se mede o escopo** | quais tabelas, quantos titulares, quais categorias de dado — as três perguntas da ANPD |
| **Linha do tempo** | quando começou, quando foi descoberto, quando foi contido. É o que a autoridade pergunta primeiro |
| **Texto-base ao titular** | escrito com calma antes, não redigido às 4h |
| **Canal da autoridade** | o link, o formulário, quem tem acesso |
| **Prazo** | 3 dias úteis / 72h, escrito, porque é a primeira coisa que se perde sob pressão |
| **Quem fala com a imprensa** | e quem não fala |

## A ordem dos primeiros 60 minutos

1. **Conter.** Revogar chave, isolar o serviço, cortar o acesso. Antes de
   entender, parar.
2. **Preservar evidência.** Log, snapshot, imagem do disco — apagar para "limpar"
   destrói a investigação e a defesa.
3. **Registrar o horário de tudo.** Inclusive o horário em que você soube: é ele
   que inicia o prazo legal.
4. **Só então** medir o escopo. Comunicar antes de saber o tamanho produz uma
   segunda comunicação corrigindo a primeira.

## O que só se prova exercitando

| Verificar | Como |
|---|---|
| O runbook é executável às 3h | simulação com quem está de plantão, não com quem escreveu |
| Os acessos existem | quem precisa entrar no painel da ANPD tem credencial? |
| A lista de titulares é obtível | notificar exige saber quem foi afetado |
| O jurídico está no fluxo | comunicação regulatória sem revisão jurídica cria o segundo problema |
