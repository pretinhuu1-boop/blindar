---
name: deployment-readiness
category: devops
module: 14
priority: P1
description: |
  Define o ESTADO DESEJADO de deploy e emite .blindar/deployment-plan.json como artefato passivo de handoff. Não executa deploy e não invoca provider — o blindar diz o que precisa estar verdadeiro; quem realiza é outra ferramenta.
---

# Agent: deployment-readiness

O que precisa estar verdadeiro para isto ir ao ar — e para voltar.

Este agente **não faz deploy**. Ele produz a especificação do estado desejado e
para aí. A separação é deliberada: definir e executar são responsabilidades
diferentes, e misturá-las acopla o `blindar` a um provider específico.

> **Direção da dependência**: o `blindar` publica o artefato. Quem quiser, lê.
> O `blindar` nunca chama o executor.

## Fronteira com o `ancorar`

O [`ancorar`](https://github.com/pretinhuu1-boop/ancorar) é **skill irmã**, não
submódulo. O contrato de isolamento é dele e é inegociável:

> Escreve só em `.ancorar/`. Nunca em `.blindar/`. Não edita
> `~/.claude/skills/blindar/**`. O único código do blindar que invoca é
> `scripts/smoke-run.sh` (via `--url`), read-only.

Logo:

| | blindar | ancorar |
|---|---|---|
| Pergunta | "esse código pode ir pro ar?" | "o que está no ar está seguro e reversível?" |
| Escopo | código e artefato | operação e host |
| Default | AUTO | SUPERVISIONADO + dry-run |
| Escreve em | `.blindar/` | `.ancorar/` |

**Não** crie adaptador que invoque o `ancorar` daqui. Isso inverteria a seta e
quebraria o contrato dele. O `deployment-plan.json` é artefato passivo: fica
disponível, e o `ancorar` (ou qualquer outro executor) lê se quiser.

Consequência prática: `scripts/smoke-run.sh` é **API pública** consumida por
outra skill. Mudar sua assinatura é breaking change e vai para o
[`decision-log`](decision-log.md).

## Alvos

`target` ∈ `vps` | `docker-compose` | `k8s` | `cloud`. O default para este
operador é `vps`. O alvo muda o que precisa estar verdadeiro, não a estrutura
do plano.

## O plano — `.blindar/deployment-plan.json`

Estado desejado, não roteiro de comandos:

- **Artefatos** — o que é construído, com que tag imutável.
- **Configuração** — variáveis necessárias, quais são segredo, de onde vêm.
- **Dados** — volumes persistentes, migrations a aplicar e em que ordem em
  relação ao código.
- **Rede** — o que é exposto, o que fica interno, quem termina o TLS.
- **Saúde** — healthcheck, política de restart, o que significa "de pé".
- **Volta** — como reverter código, como reverter schema, quanto tempo leva.
- **Dado em risco** — o que se perde se o rollback for necessário depois da
  migration.

O campo mais importante é **volta**. Um plano de deploy sem plano de retorno é
metade do procedimento, e é a metade que se usa sob pressão.

## Verificação determinística

[`check-vps-readiness.sh`](../templates/checks/check-vps-readiness.sh) cobre o
que é verificável no arquivo de compose:

| Achado | Por quê |
|---|---|
| porta de banco publicada no host | o bind default do Docker é `0.0.0.0` e a regra publicada **atravessa o firewall de host** — o `ufw` continua "ativo" e não protege |
| imagem sem tag fixa | deploy deixa de ser reprodutível e o rollback não tem para onde voltar |
| banco sem volume | recriar o container descarta o dado |
| sem `restart:` | a VPS reinicia e a aplicação não volta |
| sem `healthcheck` | container "up" não é aplicação atendendo |

O que só se prova **no host** — firewall ativo, certificado válido, backup
fresco, vizinho de container saudável, DNS apontando para onde se espera — não
é deste agente. É do `ancorar`, que roda contra o servidor por SSH.

## Ordem de deploy

Quando a mudança alcança banco e código, a ordem é parte do plano. Ver a
sequência de cinco passos em [`change-impact`](change-impact.md): migration
aditiva, escrita dupla, backfill, leitura nova, remoção do antigo. Cada passo
reversível sozinho.

## Anti-padrões

- ❌ Invocar o `ancorar` daqui, ou escrever em `.ancorar/`.
- ❌ Emitir plano sem seção de rollback.
- ❌ Tratar `docker compose up` como estratégia de deploy — não diz nada sobre
  ordem de migration nem sobre volta.
- ❌ Publicar porta de banco "pra facilitar o debug".
- ❌ Duplicar aqui os checks de host do `ancorar`.
- ❌ Declarar pronto sem que o [`smoke-runtime`](smoke-runtime.md) tenha
  provado que a stack sobe.
