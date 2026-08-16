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

## Passo 4 — Verificar o host (⭐ v0.66)

```bash
bash scripts/ancorar-bridge.sh --host meu.servidor.com
```

A [ponte](../scripts/ancorar-bridge.sh) emite o plano, encontra o
[`ancorar`](https://github.com/pretinhuu1-boop/ancorar) e roda as fases de
**leitura** dele: baseline de segurança do host (16 checks por SSH), verdade de
runtime e regressão de co-inquilinos.

**As fases que mutam ficam com o operador.** Provisionar, migrar dado, virar
tráfego e decommissionar mudam o servidor; a ponte recusa e diz o comando certo.
Automatizá-las daqui trocaria o *supervisionado + dry-run* do ancorar pelo
*auto* do blindar.

Sem o ancorar instalado, o plano é emitido e a ponte avisa — **ausência de
verificação, não aprovação**.

O blindar lê `.ancorar/results/` e nunca escreve lá. O `scripts/smoke-run.sh`
segue sendo **API pública** consumida pelo ancorar na fase 7: mudar sua
assinatura é breaking change.

## Anti-padrões

- ❌ Executar deploy nesta fase.
- ❌ Invocar fase do ancorar que **muta** o host a partir daqui, ou passar
  `ANCORAR_APPLY`. Ler o resultado dele é certo; decidir por ele não é.
- ❌ Escrever em `.ancorar/`.
- ❌ Emitir plano sem o bloco de volta.
- ❌ Duplicar os checks de host do `ancorar` dentro do `blindar`.
- ❌ Declarar alvo `vps` e deixar porta de banco publicada — em VPS a regra
  publicada pelo Docker atravessa o firewall de host.
