---
name: retention-job-agendado
category: compliance
module: 8
priority: P1
lead: privacy-lead
authority: implement
description: |
  Política de retenção declarada sem job que a execute. Config sem executor é retenção de mentira: passa em auditoria de papel e reprova em auditoria de banco — dado de 2019 vivo com política declarada de 90 dias é declaração falsa.
---

# Agent: retention-job-agendado

O padrão é sempre o mesmo: alguém escreve `RETENCAO_DIAS=90` no `.env`, a variável
entra no README como "política de retenção", e nada nunca apaga nada.

Passa em auditoria de papel e reprova em auditoria de banco. **Dado de 2019 vivo
com política declarada de 90 dias é pior que não ter política** — é declaração
falsa, e a organização fica em posição pior do que se nada tivesse afirmado.

Este check só roda quando **há** política declarada. Ausência de política é
assunto do [`compliance-lgpd-br`](compliance-lgpd-br.md); aqui a pergunta é se o
que foi declarado executa.

## O que o check já garante

[`check-retention-job-agendado.sh`](../templates/checks/check-retention-job-agendado.sh):

| Situação | Severidade |
|---|---|
| Política declarada e nenhum agendador no repositório | **med** |
| Agendador presente, mas nenhuma rotina de purga | **med** |

Aceita como agendador: `node-cron`, `@nestjs/schedule`, `@Cron`, Celery beat,
APScheduler, BullMQ repeat, `pg_cron`, `CREATE EVENT`, sidekiq-cron, systemd
`OnCalendar`, `schedule:` de workflow de CI, crontab versionado.

Aceita como purga: `purge`, `prune`, `cleanup`, `deleteMany`, `delete_expired`,
`DELETE FROM`, anonimização.

TTL de cache, Redis, sessão e JWT são ignorados de propósito — são outra coisa.

## O que o job precisa fazer

1. **Rodar em lote com teto.** `DELETE FROM eventos WHERE created_at < ...` numa
   tabela grande trava a tabela. Apague em blocos, com pausa.
2. **Registrar quanto apagou.** Job de retenção que roda e apaga zero por um mês
   está quebrado, e sem métrica ninguém percebe — é a mesma armadilha do "run que
   mediu nada saiu com sucesso".
3. **Alertar quando falha.** Job silencioso que parou de rodar é
   indistinguível de job que não tinha o que apagar.
4. **Respeitar a exceção legal.** Nota fiscal tem prazo próprio; o job precisa
   saber o que não pode tocar.
5. **Ser idempotente e interrompível.** Vai ser morto no meio em algum deploy
   (ver [`graceful-shutdown`](graceful-shutdown.md)).

## O que só se prova no banco

| Verificar | Como |
|---|---|
| O registro mais antigo respeita a política | `SELECT min(created_at)` na tabela coberta |
| O job rodou nas últimas 24h | métrica ou log com contagem, não a existência do arquivo |
| Backups também expiram | apagar da base e manter no bucket por 5 anos não cumpre a política |
| Réplicas e data warehouse | a cópia analítica costuma ficar de fora e guardar tudo |
