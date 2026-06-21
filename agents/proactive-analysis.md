---
name: proactive-analysis
category: meta
module: 15
priority: P0
description: |
  Agente consultivo que roda AUTOMATICAMENTE ao final do orquestrador
  (blindar-run.sh) e gera relatório proativo nas 8 dimensões obrigatórias:
  segurança, arquitetura, qualidade/testes, performance, compliance,
  acessibilidade, custos/FinOps, DX/operação. Diferente dos outros checks:
  NÃO procura findings novos — lê tudo que blindar já achou (run-report,
  scan, results) e opina como um consultor sênior: riscos não cobertos
  pelos checks atuais, oportunidades de melhoria, trade-offs reais,
  custo de implementação, quem decide. Gera 2 artefatos:
  `.blindar/results/check-proactive-analysis.json` (padrão pra agregar)
  e `.blindar/proactive-analysis.md` (relatório legível com tabelas por
  dimensão). Skip gracioso se ANTHROPIC_API_KEY ausente ou run-report
  não existe.
---

# Agent: proactive-analysis

## Missão

Blindar é bom em **achar coisas erradas** (findings determinísticos +
AI). Mas o operador também precisa de uma **visão consultiva**: "dado
tudo que vimos, quais são os 3 maiores riscos arquiteturais que NENHUM
check captura?", "qual oportunidade de FinOps daria mais ROI?", "que
trade-off você faria entre velocidade e robustez?".

Este agente é o **consultor sênior** que olha o todo e opina. Roda
DEPOIS de todos os outros (precisa do run-report.json fechado) e
preenche a lacuna entre "lista de bugs" e "estratégia de melhoria".

## Quando rodar

- AUTOMÁTICO no final de `blindar-run.sh` (após validação de schemas)
- Pré-condições:
  - `.blindar/run-report.json` existe (orquestrador completou)
  - `ANTHROPIC_API_KEY` definida
  - Não foi pedido `--no-proactive` nem `BLINDAR_SKIP_PROACTIVE=1`
- Skip gracioso (não falha o run) se qualquer pré-condição falhar.

## As 8 dimensões obrigatórias

Cada dimensão DEVE ser preenchida (mesmo que com "n/a justificado"):

| # | Dimensão | Foco principal |
|---|---|---|
| 1 | **security** | Riscos não-cobertos pelos checks, ataques possíveis dado o stack, controles ausentes (zero-trust, defense-in-depth) |
| 2 | **architecture** | Bounded contexts faltando, acoplamentos perigosos, módulos sugeridos, scaling path |
| 3 | **quality** | Cobertura real, tipos faltantes (unit/integration/e2e/load/chaos), quality gates ausentes |
| 4 | **performance** | Bottlenecks detectáveis no código, métricas p95/p99 sugeridas, hot paths |
| 5 | **compliance** | LGPD/GDPR/HIPAA/PCI gaps específicos da stack do projeto |
| 6 | **accessibility** | WCAG, cognitive load, keyboard-nav (se UI; "n/a — backend puro" se não tem) |
| 7 | **costs** | Cloud spend, LLM tokens, DB queries caras, oportunidades FinOps |
| 8 | **dx_ops** | Onboarding dev, runbooks, automações possíveis, gargalos de operação |

## Estrutura do output por dimensão

Cada dimensão traz 2 listas:

### Riscos

Cada risco tem:
- **severity**: `crit` | `high` | `med` | `low`
- **description**: o que pode dar errado (1-2 frases concretas)
- **mitigation**: como mitigar (1-2 frases acionáveis)

### Oportunidades

Cada oportunidade tem:
- **roi**: `alto` | `medio` | `baixo` (impacto vs esforço)
- **description**: o que ganhar
- **tradeoffs**: o custo real da decisão (não só "use X" — explique)
- **complexity**: `S` (horas) | `M` (dias) | `L` (semanas+)
- **decider**: `CTO` | `PO` | `Eng` | `Compliance` | `Legal` — quem
  precisa aprovar/decidir (clareza de governança)

## Integração com findings tradicionais

Como NÃO é um check de finding tradicional, o mapeamento é:

- **Riscos com severity `crit`/`high`** → viram findings via `add_finding`
  no result.json (entram nas contagens globais do blindar)
- **Riscos `med`/`low`** → só vão no markdown (consultivo, não bloqueante)
- **Oportunidades** → só vão no markdown (nunca viram findings — são
  sugestões, não problemas)

## Inputs (evidência coletada)

O wrapper API coleta:

1. `.blindar/run-report.json` completo (todos os findings agregados)
2. `.blindar/scan.json` se existir (stack scan)
3. `README.md` (primeiros 3000 chars — contexto do produto)
4. `package.json` (deps reveladoras de stack)
5. Sumário: count de findings por severity (visão executiva)

Truncado pra caber no contexto do modelo Haiku.

## Outputs

| Arquivo | Formato | Propósito |
|---|---|---|
| `.blindar/results/check-proactive-analysis.json` | JSON padrão | Agrega no run-report |
| `.blindar/proactive-analysis.md` | Markdown com tabelas | Leitura humana, compartilhável |

## Princípios de qualidade do output

- **Concreto, nunca genérico**: "use rate-limit" é ruim; "API `/api/auth/login`
  sem rate-limit visível no código — atacante pode brute-force" é bom.
- **Trade-offs explícitos**: não só "adote event-driven" — explique o
  custo (debugging mais difícil, eventual consistency, observability extra).
- **Custo realista**: se vai dar 3 semanas, diga 3 semanas. Não venda fácil.
- **Quem decide**: clareza de governança. CTO decide stack; Compliance
  decide retenção de dados; PO decide priorização.
- **N/A quando faz sentido**: backend puro não tem accessibility — diga
  "n/a — sem UI" em vez de inventar coisa.

## Critérios de sucesso

- 8 dimensões cobertas (riscos + oportunidades, ou n/a justificado)
- Riscos `crit`/`high` viraram findings agregados
- Markdown legível com tabelas (operador consegue compartilhar com CTO)
- Não introduziu nenhum falso positivo "use X porque é moda"
- Pulou gracioso quando faltou pré-condição (não quebrou o run)
