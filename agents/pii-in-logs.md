---
name: pii-in-logs
category: compliance
module: 6
priority: P0
lead: privacy-lead
authority: implement
description: |
  Dado pessoal e credencial indo parar no arquivo de log. Varredura completa com arquivo e linha: campo de PII citado na chamada, objeto inteiro da requisição, e cabeçalho de autorização. LGPD art. 6 / GDPR art. 5.
---

# Agent: pii-in-logs

Log é o lugar onde dado pessoal vaza **sem que ninguém tenha decidido nada**.

Ele sai da aplicação, entra no agregador (Datadog, CloudWatch, Loki, Sentry), é
replicado, indexado, guardado por meses, e fica acessível a todo mundo que tem
acesso ao painel de observabilidade — que é um grupo consideravelmente maior do
que quem tem acesso ao banco. Para a LGPD isso é **tratamento**, com todas as
obrigações que vêm junto: base legal, minimização, retenção, e notificação se
vazar.

O caso mais comum não é logar `user.cpf` de propósito. É `logger.info(req.body)`
no handler de cadastro. O objeto inteiro vai — senha, CPF, cartão, tudo que o
cliente mandou, inclusive o que você nunca decidiu guardar.

Divisão com o [`observability`](observability.md): lá há uma regra pontual de PII
em log. Aqui é a varredura completa, e cada achado sai com arquivo e linha.

## O que o check já garante

[`check-pii-in-logs.sh`](../templates/checks/check-pii-in-logs.sh):

| Padrão | Severidade |
|---|---|
| Credencial de sessão em log (`Authorization`, cookie, token, apiKey) | **crit** |
| Campo de PII citado na chamada de log | **high** |
| Objeto inteiro da requisição/usuário despejado | **high** |

Campos reconhecidos em português e inglês: CPF, CNPJ, RG, senha/password, CVV,
número de cartão, telefone/WhatsApp, endereço, CEP, data de nascimento, nome
completo, e-mail, SSN, passaporte.

Arquivo de teste, mock, fixture e exemplo são ignorados.

Auto-skip em projeto sem nenhuma chamada de log.

## Credencial em log é pior que PII em log

Por isso é **crit** e não **high**: quem lê o painel de log passa a poder se
autenticar como o usuário. Não é um vazamento de dado — é um vazamento de acesso,
e ele não expira quando o log expira, porque alguém já copiou.

O `req.headers` inteiro é o vetor: parece inofensivo ("é só o cabeçalho") e leva
`authorization` e `cookie` junto.

## A correção que funciona

Não é revisar cada chamada. É **redigir na saída do logger**, uma vez:

- lista de campos proibidos aplicada por serializer (`pino` tem `redact`,
  `winston` tem formatter, `structlog` tem processor);
- **allowlist em vez de denylist** onde der: logar `{ usuarioId, evento }`, nunca
  o objeto. Denylist esquece o campo novo que alguém adicionou ontem;
- ID em vez de dado. `usuarioId: 91af…` responde tudo que a investigação precisa
  sem carregar nada de pessoal.

## O que só se prova no agregador

| Verificar | Por quê |
|---|---|
| A redação está ativa **em produção** | config por ambiente costuma divergir |
| O log de erro não escapa | stack trace com o objeto anexado passa por fora do serializer |
| Retenção do agregador | 400 dias de log com PII é 400 dias de exposição |
| Quem tem acesso ao painel | o grupo é maior do que se imagina, e raramente é revisado |
