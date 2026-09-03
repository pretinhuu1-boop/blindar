---
name: rollback-ready
category: deployment
module: 18
priority: P1
lead: release-lead
authority: implement
description: |
  Reversibilidade do deploy: tag de imagem versionada (não só :latest) e procedimento de rollback escrito. Sem os dois, voltar um deploy ruim é improviso na pior hora possível.
---

# Agent: rollback-ready

`image: meuapp:latest` significa que **não existe versão anterior nomeável**. O
deploy quebrou às 22h e a pergunta "volta para qual?" não tem resposta: a tag
aponta para o que acabou de subir.

Sobra reconstruir do commit anterior — se alguém souber qual é, se o build for
reprodutível (ver [`npm-ci-lockfile`](npm-ci-lockfile.md)), e se der tempo.

Rollback não é ter backup. É poder dizer, em trinta segundos e sem build, **qual
artefato estava no ar antes e como colocá-lo de volta**.

## O que o check já garante

[`check-rollback-ready.sh`](../templates/checks/check-rollback-ready.sh):

| Situação | Severidade |
|---|---|
| Deploy publica imagem sem versão (`:latest` ou sem tag) | **med** |
| Sem procedimento de rollback escrito | **med** |

Aceita como versionada: `:${GITHUB_SHA}`, `:${IMAGE_TAG}`, `:v1.2.3`,
`@sha256:…`. Aceita como procedimento: runbook, script, ou passo no pipeline que
mencione rollback, `kubectl rollout undo`, `helm rollback`.

Auto-skip em projeto sem manifesto de deploy no repositório.

## O que torna o rollback real

1. **Tag imutável por build**, derivada do commit. `meuapp:9ae5723` nunca é
   reescrita, e diz exatamente qual código está dentro.
2. **As N últimas mantidas no registry.** Política de limpeza que apaga tudo
   menos a `latest` transforma tag versionada em decoração.
3. **Comando único, escrito.** Uma linha que qualquer pessoa de plantão executa
   sem entender a arquitetura.
4. **Migração de banco compatível para trás.** É aqui que a maioria dos rollbacks
   morre: o código volta, o esquema não. Migração que remove coluna torna o
   deploy irreversível — separe em duas entregas (adicionar e parar de usar
   agora; remover na próxima).
5. **Drill com tempo medido.** Rollback que nunca foi executado tem o mesmo
   status do backup nunca restaurado (ver
   [`backup-restore-tested`](backup-restore-tested.md)).

## O que só se prova exercitando

| Verificar | Como |
|---|---|
| A imagem anterior ainda existe | `docker image ls` no registry, não na sua máquina |
| O rollback leva o tempo que se diz | cronometre em homologação |
| O esquema do banco aceita o código antigo | rode a versão N-1 contra a migração N |
| Cache e CDN não servem a versão nova | asset com hash antigo precisa continuar disponível |
