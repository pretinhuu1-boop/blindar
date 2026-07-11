---
name: llm-system-prompt-leak
category: security
module: 2
priority: P1
description: |
  OWASP LLM07 — System Prompt Leakage. Detecta system prompt devolvido em
  resposta HTTP ou logado, expondo instruções internas (que viram munição
  pra prompt injection e revelam lógica de negócio/guardrails).
---

# Agent: llm-system-prompt-leak

## Missão

Impedir vazamento do **system prompt** — as instruções que definem o
comportamento e os guardrails do assistente. Se ele vaza (numa resposta de
API, num log, numa mensagem de erro), o atacante aprende exatamente como
contornar as defesas e quais regras internas existem. É o LLM07 do
[OWASP Top 10 para LLM 2025](https://genai.owasp.org/). Complementa
`ai-llm-safety` (que cobre LLM01/02/05/06/09/10, mas não LLM07). Fonte:
[`docs/book-insights.md`](../docs/book-insights.md) § Engenharia de IA.

## Quando rodar

- Módulo 2 (segurança core) — só se lib de LLM detectada no `package.json`
  (openai, anthropic, langchain, @vercel/ai, etc.). Self-skip caso contrário.

## O que dispara finding

| Padrão | Severidade |
|---|---|
| `res.json({ systemPrompt })` / `Response.json(...systemPrompt...)` — prompt devolvido ao cliente | high |
| `console.log(systemPrompt)` / `logger.info(...systemPrompt...)` — prompt logado | med |

Variáveis reconhecidas: `systemPrompt`, `system_prompt`, `SYSTEM_PROMPT`,
`SYSTEM_MESSAGE`, `systemMessage`.

## Como blindar

- **Nunca** devolva o system prompt ao cliente. A resposta da API expõe só a
  saída do modelo, nunca as instruções.
- Não logue o prompt em nível info/debug que vá pra sink persistente. Se
  precisar debugar, use nível trace local com redação.
- Trate o system prompt como segredo operacional: quem o vê, contorna.
- Assuma que ele PODE vazar mesmo assim → não coloque secret/credencial dentro
  dele (ver `check-secrets`, `config-externalization`).

## Falso positivo — como suprimir

- Marcador `@blindar:keep` na linha (ex: endpoint de admin interno atrás de auth
  forte que legitimamente expõe o prompt pra debug).
- `.blindar/intelligence.yml` seção `llm-system-prompt-leak: ignore_paths`.

## Intelligence

Respeita `.blindar/intelligence.yml` via `load_intelligence_globs`.
