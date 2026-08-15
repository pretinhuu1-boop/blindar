---
phase: 10-deployment-target
title: Alvo de deploy — estado desejado e artefato de handoff
duration_estimate: ~2 min
output: .blindar/deployment-plan.json
runs_after: 06b-release-gates.md
runs_before: 07-final-report.md
---

# Fase 10 — Alvo de deploy

Define **o que precisa estar verdadeiro** para o projeto ir ao ar, e emite isso
como artefato. Não executa deploy.

> A fase termina com um arquivo, não com um servidor mudado. Definir e executar
> são responsabilidades diferentes; misturá-las acopla o `blindar` a um
> provider.

Conduzida por [`deployment-readiness`](../agents/deployment-readiness.md).

---

## Passo 1 — Qual é o alvo

| `target` | Quando |
|---|---|
| `vps` | servidor único, Docker Compose, proxy reverso (**default deste operador**) |
| `docker-compose` | mesma forma, sem compromisso com host específico |
| `k8s` | cluster |
| `cloud` | PaaS gerenciado |

Detecte pelo que existe: `fly.toml`, `render.yaml`, `vercel.json`, `k8s/`,
`helm/`, `ansible/`, ou apenas `docker-compose.yml`. Na ausência de sinal e com
`operation_mode` de produção, assuma `vps` e confirme.

## Passo 2 — Estado desejado

Sete blocos, todos obrigatórios no `deployment-plan.json`: artefatos,
configuração, dados, rede, saúde, **volta**, e dado em risco.

O bloco **volta** é o que mais falta e o mais usado sob pressão. Ele responde
três perguntas separadas, que costumam ser tratadas como uma:

1. Como reverter o **código**? (normalmente trivial — tag anterior)
2. Como reverter o **schema**? (normalmente não trivial)
3. O que acontece com o **dado escrito** entre o deploy e o rollback?

A terceira é a que decide se o rollback é possível. Se a migration removeu uma
coluna, reverter o código não traz o dado de volta.

## Passo 3 — Verificação

[`check-vps-readiness.sh`](../templates/checks/check-vps-readiness.sh) roda
sobre o compose e alimenta o gate `DEPLOYMENT` da
[Fase 06b](06b-release-gates.md). Lembrando que aquele gate só chega a `PASS`
com rollback documentado — é aqui que essa documentação nasce.

## Passo 4 — Handoff

O `.blindar/deployment-plan.json` fica disponível. **Ninguém é chamado.**

A skill irmã [`ancorar`](https://github.com/pretinhuu1-boop/ancorar) cobre a
outra metade — o que só se prova no host: firewall, certificado, backup fresco,
DNS, vizinhos de container. Ela lê o que quiser e roda por conta própria, em
modo supervisionado com dry-run.

A dependência é **ancorar → blindar**, nunca o contrário. O `blindar` não
invoca o `ancorar` e não escreve em `.ancorar/`. O único ponto de contato é o
`scripts/smoke-run.sh`, que o `ancorar` consome via `--url` de forma read-only
— e que por isso é **API pública**: mudar sua assinatura é breaking change.

## Anti-padrões

- ❌ Executar deploy nesta fase.
- ❌ Chamar o `ancorar`, ou escrever em `.ancorar/`.
- ❌ Emitir plano sem o bloco de volta.
- ❌ Duplicar os checks de host do `ancorar` dentro do `blindar`.
- ❌ Declarar alvo `vps` e deixar porta de banco publicada — em VPS a regra
  publicada pelo Docker atravessa o firewall de host.
