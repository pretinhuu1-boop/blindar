# Rodando o blindar em qualquer AI

Este skill foi extraído de execução no **Claude Code**, onde execução
paralela real (`Workflow` / `agent()` / `parallel()`) está embutida. Mas
o conteúdo é **markdown puro com prompts em texto** — qualquer AI moderna
consegue seguir.

Este documento descreve como rodar em outros assistentes.

## Modos de execução

| AI | Modo | Paralelo real? | Velocidade relativa |
|---|---|---|---|
| **Claude Code (CLI/IDE)** | Nativo | sim (Workflow API) | 1x (referência) |
| **Claude.ai web** | Manual | não (sequencial) | ~3-5x mais lento |
| **ChatGPT (Plus/Team)** | Manual | não | ~3-5x mais lento |
| **Gemini Advanced** | Manual | não | ~3-5x mais lento |
| **Cursor / Windsurf** | Híbrido (agentes próprios) | parcial | ~2-3x mais lento |
| **Copilot Chat** | Manual | não | ~3-5x mais lento |

## Princípio fundamental — sempre multi-agente

Mesmo em AI single-threaded, o blindar **simula multi-agente** por
**role-play sequencial**. Cada papel (inventory, threats, security,
adversarial reviewer) vira um turno separado da conversa, com o
**contexto isolado por turno** para evitar viés.

Nunca rode o pipeline com 1 prompt monolítico do tipo "blinda esse
projeto inteiro" — perde a vantagem do skill. Sempre **um agente por
turno**.

## Como rodar em modo manual (qualquer AI)

### Passo 0 — Carregar contexto

Cole no início da conversa:

```
Você vai operar como o skill "blindar" descrito em SKILL.md (em anexo).
A partir de agora, eu vou te pedir pra assumir um papel por vez do
roster em agents/. Você responde APENAS no papel pedido, sem vazar
contexto de outros papéis.

Quando eu pedir um papel novo, esqueça o tom do papel anterior — só
fatos do projeto persistem.

Para cada round: você implementa, eu valido, eu confirmo merge.
```

Depois cole `SKILL.md` + `pipeline/00-baseline.md`. Em conversas com
janela menor, cole os outros arquivos sob demanda.

### Passo 1 — Baseline (Fase 0)

Cole [`pipeline/00-baseline.md`](pipeline/00-baseline.md). Peça:
> "Atue como agente de Baseline. Detecte stack, conte testes, verifique
> git status. Retorne JSON conforme schema."

### Passo 2 — Discovery (Fase 1)

3 turnos separados (sequencial):
1. **Inventory**: cola `pipeline/01-discovery.md`, papel "inventory"
2. **Threats**: novo turno, papel "threat-model"
3. **Architecture**: novo turno, papel "architecture"

Cada turno responde JSON do schema. **Não misture** num turno só — a
isolação é o que vale.

### Passo 3 — Bootstrap sec.html

Cole [`templates/sec.html`](templates/sec.html) + outputs dos 3 turnos
acima. Peça a AI para popular os arrays JS no topo conforme discovery.

### Passo 4 — Rounds (Fase 3)

**Cada round = ≥2 turnos**:

1. **Pick** (você ou um agente "scheduler"): escolhe gap de maior severity.
2. **Implementer**: cole `agents/<categoria>.md`, peça implementação.
   Recebe diff + teste + grep estático.
3. **Verifier** (turno separado, contexto limpo): cole o diff do
   implementer + `agents/adversarial-reviewer.md` lens correspondente.
   Peça: "tente refutar. default refuted=true if uncertain."

Se verifier passar: merge. Se não: round volta com finding como input.

### Passo 5 — Adversarial review (Fase 4)

A cada 10 rounds, **4 turnos separados** — 1 por lens:
- security, races, failmodes, regression

Depois, **para cada finding**, 1 turno de verify (default refute).

Confirmados (`isReal=true`) → entram na fila como novos rounds.

### Passo 6 — Production checklist (Fase 5)

Cole [`pipeline/05-production-checklist.md`](pipeline/05-production-checklist.md).
Peça checklist preenchido por agente "auditor" (1 turno).

### Passo 7 — Relatório final (Fase 6)

Cole histórico (sumário de cada round + sec.html final). Peça PR de
relatório (1 turno).

## Limitações em AI single-threaded

| Limitação | Mitigação |
|---|---|
| Janela de contexto pequena | Sumarize estado a cada 10 rounds (sec.html é o estado) |
| Sem execução real (Bash, gh) | Você executa, AI escreve os comandos |
| Sem JSON schema enforcement | Cole o schema no prompt e peça validação |
| Sem cache de prompts | Cada turno reaplica contexto — mais lento e caro |
| Sem MCP/tools (web fetch, etc.) | Você faz as buscas e cola resultado |

## Quando NÃO usar modo manual

- Projeto com >50 ATKs identificados → o overhead manual fica proibitivo.
  Vale ir pro Claude Code (ou similar) só pra esse projeto.
- Time grande com vários blindares em paralelo → coordenação manual
  vira gargalo.

## Receita rápida pra começar em qualquer AI

```
1. Cola SKILL.md, README.md, pipeline/00-baseline.md no chat
2. "Atue como agente Baseline conforme blindar. Output JSON do schema."
3. Cola pipeline/01-discovery.md
4. 3 turnos de discovery (inventory, threats, architecture)
5. Cola templates/sec.html
6. "Popule arrays com base nos 3 outputs anteriores. Cole sec.html pronto."
7. Você commita sec.html no projeto. Abre no browser.
8. Cola pipeline/03-rounds-loop.md + agents/<categoria>.md do top gap
9. "Atue como agente <categoria>. Implemente o round."
10. Você revisa diff, roda testes, commita, mergeia.
11. A cada 10 rounds: 4 turnos de adversarial + N turnos de verify.
12. Termina conforme pipeline/06-final-report.md.
```

Single-thread funciona. Só é mais lento.
