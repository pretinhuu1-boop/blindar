---
name: backup-restore-tested
category: data
module: 7
priority: P0
lead: data-lead
authority: implement
description: |
  Backup nunca restaurado é backup de Schrödinger. Cobra a evidência de restore EXERCITADO — script, teste, job de CI ou runbook com verificação — em projeto que já tem rotina de backup.
---

# Agent: backup-restore-tested

O dump roda todo dia, o arquivo aparece no bucket, o painel fica verde. Nada
disso é informação sobre a capacidade de voltar.

O que se descobre só na hora do desastre: o dump está truncado porque o disco
encheu no meio; o `pg_dump` rodou contra a réplica atrasada; a versão do servidor
mudou e o formato não carrega mais; a chave de criptografia está no mesmo
servidor que pegou fogo; ninguém sabe o comando exato e são 4h da manhã.

O único fato que importa sobre backup é o tempo entre "vou restaurar" e
"aplicação de pé com dado bom". Esse número só existe se alguém tiver medido.

Divisão com o [`backup-recovery`](backup-recovery.md): lá é a política completa
(PITR, replicação, retenção, criptografia). Aqui é uma pergunta só — já foi
restaurado alguma vez?

## O que o check já garante

[`check-backup-restore-tested.sh`](../templates/checks/check-backup-restore-tested.sh):

| Situação | Severidade |
|---|---|
| Backup existe, nenhuma evidência de restore | **high** |
| Restore existe, nenhum registro de drill ou RTO medido | **med** |

Aceita como evidência: `scripts/restore*.sh`, `pg_restore`, `mongorestore`,
`restic restore`, `wal-g backup-fetch`, teste automatizado que restaura, job de
CI com restore, ou runbook com passo de verificação.

Auto-skip quando não há rotina de backup — a ausência de backup é assunto do
[`backup-recovery`](backup-recovery.md), não daqui.

## O drill que vale

Restaurar num banco descartável e conferir que o dado abre não basta. O drill que
vale mede o caminho inteiro:

1. **Escolher o backup pela idade certa** — o de ontem, não "o último que der".
2. **Restaurar num ambiente limpo**, sem acesso ao original: é essa a condição
   real do desastre.
3. **Subir a aplicação contra ele** e fazer uma operação de escrita.
4. **Cronometrar** do comando inicial até o tráfego voltar. Esse número é o RTO
   real; o RTO do documento é ficção até ser medido.
5. **Anotar a data.** Drill de dezoito meses atrás não descreve o sistema de hoje.

## O que só se prova fora do repositório

| Verificar | Por que o arquivo não basta |
|---|---|
| O backup **não está vazio** | script que falha em silêncio gera arquivo de 0 byte todo dia |
| A chave de criptografia sobrevive | guardada junto com o que protege, morre no mesmo incidente |
| Permissão de leitura no bucket | credencial de escrita não implica credencial de restauração |
| Retenção real × declarada | política de 30 dias com lifecycle de 7 dias no bucket |
