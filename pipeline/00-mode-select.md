---
phase: 00-mode-select
title: Seleção de modo de operação — GREENFIELD / HARDEN / FEATURE / EVOLVE / RECOVERY
duration_estimate: 20s–1min
output: .blindar/config.yml (operation_mode)
runs_before: 00-launcher.md
---

# Fase 00-mode-select — qual é a natureza deste trabalho?

Roda **antes do launcher**. Responde uma pergunta que muda todo o resto:

> O projeto precisa ser **criado**, **blindado**, **ampliado**, **evoluído** ou
> **consertado**?

Até a v0.50 o `blindar` só tinha um caminho: projeto existente e saudável.
Rodar esse caminho num diretório vazio produz ruído; rodar num projeto que não
sobe produz um relatório de segurança sobre escombros; rodar em produção com
autonomia total produz risco.

> **Quando pular:** se `.blindar/config.yml` já tem `operation_mode`, pula
> (retomada). `--headless` assume `harden`.

---

## Passo 1 — Detecção (determinística, nesta ordem)

A ordem é precedência: a primeira que casar vence. Não continue avaliando.

### 1º — RECOVERY (o sistema está quebrado)

Casa se **qualquer uma**:

- A suite de testes existe e está **vermelha**.
- O build falha (`npm run build`, `tsc`, `go build`, `cargo build`).
- Há `docker-compose.yml`/`Dockerfile` e o container **não sobe** ou o
  healthcheck não responde.
- A CI está vermelha no último commit de `main`.
- O operador descreveu sintoma de incidente ("não sobe", "caiu", "quebrou",
  "está fora do ar", "parou de funcionar").

RECOVERY vence tudo. Não se blinda escombro, não se evolui o que não roda.

### 2º — GREENFIELD (não há o que blindar)

Casa se **todas**:

- Não há código-fonte de aplicação, ou há apenas scaffold de gerador
  (`create-next-app`, `cargo new`, `django-admin startproject` intactos).
- Sem histórico de git relevante (0 commits, ou só o commit inicial do
  scaffold).
- Sem dependências de aplicação declaradas além das do template.

Sinal prático: menos de ~10 arquivos-fonte próprios e nenhuma rota/endpoint de
negócio.

### 3º — EVOLVE (está em produção)

Casa se **qualquer uma**:

- O operador informou URL de produção, ou disse que já está no ar / tem
  usuários / tem clientes.
- Há tags de release e histórico de deploy (`.github/workflows/*deploy*`,
  `fly.toml`, `render.yaml`, `vercel.json`, `ansible/`, `k8s/`).
- Há migrations já aplicadas em ambiente não-local (evidência em runbook,
  `.env.production`, ou backup datado).

### 4º — FEATURE (detectado pelo PEDIDO, não pelo disco)

Os três anteriores se detectam pelo **estado do repositório**. Este não: um
projeto saudável que vai receber uma feature é indistinguível, no disco, de um
projeto saudável que vai ser auditado. O sinal está no **pedido**.

Casa se o operador pediu para **acrescentar capacidade**: "implementa",
"adiciona", "cria a tela de", "quero um módulo de", "preciso que também faça".

Segue por [`FEATURE.md`](FEATURE.md).

**Composição, não substituição**: se o projeto também está em produção, este
modo **soma** as travas do `evolve` (round ≤40 LOC, `supervised`, migration
destrutiva proibida) à disciplina de construção. Feature em sistema com usuários
é as duas coisas ao mesmo tempo — grave `operation_mode: feature` e
`production: true` na evidência.

### 5º — HARDEN (default)

Nenhuma das anteriores. Projeto existente, saudável, e o pedido é de
**auditoria/blindagem**, não de construção.

---

## Passo 2 — Confirmação (uma linha, não um interrogatório)

Mostre a detecção com a **evidência** que a produziu e deixe o operador
sobrescrever. Nunca decida em silêncio: o modo muda o que o `blindar` pode
fazer com o projeto.

```
Modo detectado: HARDEN
  (projeto existente, suite verde, sem sinais de produção)

  G) GREENFIELD — criar do zero: arquitetura → stack → implementação → produção
  H) HARDEN     — blindar projeto existente (default, pipeline completo)
  F) FEATURE    — acrescentar capacidade a projeto saudável, sem estragar o resto
  E) EVOLVE     — já está em produção: incremental, compatível, reversível
  R) RECOVERY   — está quebrado: estabilizar primeiro, blindar depois

Enter aceita HARDEN.
```

Se a detecção deu **RECOVERY**, mostre o sintoma concreto encontrado
(suite vermelha com N falhas / build quebrado em X / container não sobe) — o
operador precisa ver o porquê, não só o veredito.

---

## Passo 3 — Consequências de cada modo

O modo não é um rótulo no relatório. Ele altera o pipeline.

| | GREENFIELD | HARDEN | FEATURE | EVOLVE | RECOVERY |
|---|---|---|---|---|---|
| Pipeline | `pipeline/GREENFIELD.md` | 00→09 (padrão) | `pipeline/FEATURE.md` | 00→09 com travas | `pipeline/RECOVERY.md` |
| Gate de suite vermelha (Fase 1) | N/A (não há suite ainda) | **PARA** | **PARA** | **PARA** | **é a condição de entrada** |
| Gate de repo sujo (Fase 1) | ignora | PARA | PARA | PARA | ignora |
| Modo default | supervised | auto | auto | **supervised** | supervised |
| Round máximo | livre (construção) | ≤80 LOC | livre (construção) | **≤40 LOC** | o mínimo p/ estabilizar |
| Escopo dos checks no fim | tudo | tudo | **`--since` (o diff)** | tudo | o que foi tocado |
| Troca de tecnologia | livre (nada existe) | permitida c/ ADR | segue o padrão do projeto | **proibida sem ADR + aprovação** | proibida |
| Migration destrutiva | livre | pede autorização | pede autorização | **proibida** | proibida |
| Módulo 19 (pentest ativo) | N/A | c/ autorização | c/ autorização | **nunca contra produção** | nunca |

**EVOLVE** é o modo cauteloso: o sistema tem usuários reais. Preservar
funcionamento vence melhorar arquitetura. Toda mudança precisa de caminho de
volta antes de ser aplicada.

**RECOVERY** é o modo cirúrgico: uma coisa de cada vez, a menor mudança que
restaura o serviço. Não refatore durante incêndio.

---

## Passo 4 — Gravar

Acrescente ao `.blindar/config.yml` (o launcher grava o resto):

```yaml
operation_mode: harden   # greenfield | harden | feature | evolve | recovery
operation_mode_source: detected   # detected | operator
operation_mode_evidence: "suite verde (42 testes), sem marcadores de produção"
```

`operation_mode_evidence` não é enfeite: quando o relatório final disser
"rodou em modo EVOLVE, não migrei o banco", precisa estar registrado **por que**
esse modo foi escolhido.

Atualize também `.blindar/state.json` com `"operation_mode"`.

---

## Passo 5 — Próxima fase

| Modo | Segue para |
|---|---|
| GREENFIELD | `pipeline/GREENFIELD.md` (o launcher roda depois, já com o alvo definido) |
| FEATURE | `pipeline/FEATURE.md` (+ travas do EVOLVE se estiver em produção) |
| HARDEN | `pipeline/00-launcher.md` |
| EVOLVE | `pipeline/00-launcher.md`, forçando `mode: supervised` |
| RECOVERY | `pipeline/RECOVERY.md` |

---

## Anti-padrões

- ❌ Detectar RECOVERY e mesmo assim rodar o pipeline de hardening "porque o
  operador pediu blindar" — blindar escombro gera relatório inútil. Estabilize,
  depois blinde. O RECOVERY termina entregando o projeto ao HARDEN.
- ❌ Assumir EVOLVE só porque existe `Dockerfile`. Container ≠ produção.
- ❌ Assumir GREENFIELD porque a pasta parece pequena. Confira ausência de
  rotas/endpoints de negócio, não contagem de arquivos.
- ❌ Perguntar o modo antes de tentar detectar. A detecção primeiro, a pergunta
  como confirmação.
- ❌ Cair em HARDEN quando o pedido era de construção. Auditar o projeto
  inteiro em resposta a "implementa o módulo X" entrega um relatório sobre o
  passado do projeto em vez da feature pedida — é o buraco que o FEATURE fecha.
- ❌ Tratar FEATURE em produção como feature comum. Lá ele **compõe** com o
  EVOLVE, não o substitui.
- ❌ Trocar de modo no meio da execução sem registrar. Mudança de modo é
  decisão arquitetural: vai para o Decision Log.
