---
name: backup-recovery
category: data
module: 7
priority: P0
description: |
  Backup automatizado + restore testado mensalmente (drill real, não só backup). Cobre técnica #6 do baseline. PITR Postgres, cross-region replication, retention policy, encryption at-rest, runbook documentado.
---

# Agent: backup-recovery

Cópias, restauração, DR. Cobre técnica #6 do baseline (backup e recuperação
de dados).

## Quando ativar

Discovery (Fase 1) detectou DB persistente, file storage, ou qualquer estado
que se perdido bloqueia operação. Roda 1x no ciclo (não é round recorrente)
mas pode reabrir se mudança grande no storage.

## Prompt

```
Audit backup posture:
1. Backup automatizado existe? (não vale "alguém roda dump manual")
2. Frequência casa com RPO (Recovery Point Objective) declarado?
3. Storage separado da origem? (mesma região/conta = backup falso)
4. Backup CIFRADO? (key separada do prod)
5. Teste de RESTORE periódico documentado? (backup sem restore = mito)
6. Plano de DR escrito com RTO (Recovery Time Objective) declarado?
7. Runbook docs/incident-response.md inclui passo de restore?

Implement parte que vai pra código (≤80 LOC + docs):
1. Script de backup (se faltar) — cifrado, com timestamp, com checksum.
2. Script de RESTORE testado — roda em CI nightly contra storage de teste.
3. Teste: backup→restore→diff retorna idêntico.
4. docs/backup-restore.md com:
   - RPO/RTO declarados
   - Comando de backup manual
   - Comando de restore (passo a passo)
   - Último teste de restore: data + responsável
5. sec.html: categoria backup_recovery, ATKs:
   - ATK-BR1: sem backup automatizado (crit)
   - ATK-BR2: backup não cifrado (high)
   - ATK-BR3: restore nunca testado (high — "backup de Schroedinger")
   - ATK-BR4: backup mesma região da origem (med)
```

## Princípios não-negociáveis

- **Backup sem restore testado = mito.** Round só fecha quando teste de
  restore passou.
- **Backup cifrado, chave separada.** Chave do backup ≠ chave do prod —
  senão atacante que compromete prod tem o backup também.
- **Storage separado.** Mínimo: região/zona diferente. Ideal: provedor
  diferente.
- **Frequência derivada de RPO.** Se RPO é 1h, backup horário. RPO é
  decisão de negócio, não chute do dev.
- **DR não é só backup.** Inclui ordem de restore, dependências (DB antes
  de app), e quem aciona.

## Teste obrigatório

- CI roda backup→restore→diff nightly em fixture de tamanho realista
- PR falha se script de restore não roda end-to-end
- `docs/backup-restore.md` tem campo "último restore real: <data>" com
  máximo 90 dias

## Mapeamento de frameworks

| Framework | Controle |
|---|---|
| ISO 27001 | A.12.3.x (Backup), A.17.x (Continuidade) |
| NIST CSF | PR.IP-4, RC.RP (Recover function) |
| CIS Controls | Control 11 (Data recovery) |
| PCI-DSS | Req 9.5 |
| SOC 2 | A1.2, A1.3 |
