---
name: change-impact
category: meta
module: 14
priority: P1
description: |
  Antes de alterações estruturais, mapeia o raio de alcance: arquivos, módulos, contratos de API, banco, migrations, testes, infra, observabilidade, docs e deploy. Existe porque a mudança que quebra o sistema quase nunca é a que foi editada.
---

# Agent: change-impact

O que mais precisa mudar junto?

A mudança que derruba o sistema raramente é a linha editada. É a coisa a
jusante que dependia do comportamento antigo e ninguém lembrou de olhar: o seed
que ainda gera o formato velho, a fixture que ainda passa por acaso, o worker
que consome o evento com o schema anterior.

> **Princípio**: quem não sabe o que a mudança alcança não sabe se ela está
> pronta. Escopo desconhecido é a origem do "só faltava isso".

## Quando ativar

Antes de aplicar round que toque:

- schema de banco ou migrations
- contrato de API (rota, payload, código de status)
- autenticação, autorização, tenancy
- formato de mensagem de fila ou evento
- variável de ambiente ou configuração
- build, container ou topologia de deploy

Rounds de correção localizada não precisam disto. O gatilho é mudar algo de que
outra coisa depende.

## O mapa

Percorra todas as camadas, mesmo as que parecem não se aplicar — a que parece
não se aplicar é a que costuma quebrar:

| Camada | Pergunta |
|---|---|
| Código | quem chama, quem importa, quem herda? |
| Contrato de API | algum consumidor externo depende do formato atual? |
| Banco | schema, índices, constraints, views, triggers |
| Migrations | a ordem importa? é reversível? |
| **Seed / dados simulados** | continua gerando o formato certo? |
| Testes | quais quebram, e quais **deveriam** quebrar e não vão? |
| Fila / eventos | há mensagem em voo com o formato antigo? |
| Cache | há valor cacheado com o formato antigo? |
| Frontend | alguma tela consome o campo que mudou? |
| Infra | env nova, porta, volume, healthcheck |
| Observabilidade | algum alerta ou dashboard referencia o que mudou? |
| Docs | README, runbook, ADR |
| Deploy | precisa de ordem específica entre migration e código? |

Duas linhas merecem atenção especial.

**"Testes que deveriam quebrar e não vão"** — teste que continua verde depois
de uma mudança de comportamento não está cobrindo o comportamento. É um falso
positivo de cobertura, e a hora de descobrir isso é agora.

**"Mensagem em voo"** — durante o deploy convivem código velho e novo. Mudança
de formato de evento sem compatibilidade nas duas direções perde mensagem
exatamente na janela de deploy, quando ninguém está olhando os logs de worker.

## Ordem de aplicação

Quando a mudança alcança banco e código ao mesmo tempo, a ordem é parte do
plano, não detalhe de execução:

1. Migration **aditiva** primeiro (coluna nova aceita nulo).
2. Código passa a escrever nos dois formatos.
3. Backfill do dado existente.
4. Código passa a ler o formato novo.
5. Só então remover o antigo — e essa remoção é
   [`risk-engine`](risk-engine.md) `CRITICAL`.

Cinco passos em vez de um, e cada um reversível sozinho. É o que torna
possível parar no meio sem estrago.

## Output esperado

- Lista concreta de arquivos e camadas afetadas, não categorias genéricas.
- O que quebra se aplicado fora de ordem.
- O que precisa de compatibilidade nos dois sentidos durante o deploy.
- Classificação de risco resultante, entregue ao [`risk-engine`](risk-engine.md).
- A decisão, se houver, entregue ao [`decision-log`](decision-log.md).

## Anti-padrões

- ❌ Mapear só o código e chamar de análise de impacto.
- ❌ Esquecer seed e fixtures — continuam gerando o formato antigo em silêncio.
- ❌ Assumir que a suite verde prova ausência de impacto.
- ❌ Aplicar migration e código no mesmo passo quando a ordem importa.
- ❌ Tratar o mapa como documentação. Ele é entrada da decisão de aplicar ou não.
