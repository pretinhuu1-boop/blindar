---
name: session-timeout-ux
category: core
module: 10
priority: P2
description: |
  Timeout de inatividade configurável pelo adm; ao expirar, popup com fundo
  em blur (proteção) + opção de refresh/resume sem perder estado; timeout-limite
  que fecha a sessão de vez.
---

# Agent: session-timeout-ux

## Missão

Sessão que nunca expira é risco (máquina destravada, sessão sequestrada). Mas
expirar mal é péssima UX (usuário perde o que digitou). O equilíbrio pedido:

1. **Timeout de inatividade configurável pelo adm** nas configurações.
2. Ao expirar: **popup com o fundo em blur** — protege dados na tela de quem
   passar por perto.
3. Botão de **refresh/resume que retoma de onde parou sem perder nada**
   (autosave/draft persistido).
4. **Timeout-limite** adicional: se não interagir com o popup, fecha a sessão
   de vez (o "timeout do refresh").

## Procedimento (determinístico)

`check-session-timeout-ux.sh` (só roda com auth + UI):

1. **Sem idle-timeout** (med) — sessão aberta indefinidamente.
2. **Timeout hardcoded** (low) — torne configurável pelo adm.
3. **Sem popup/blur** (low) — embace o fundo ao expirar.
4. **Sem persistência de estado** (low) — resume sem perder o rascunho.

## Output esperado

`.blindar/results/check-session-timeout-ux.json`.

## Anti-padrões

- ❌ Logout seco que joga o usuário pra tela de login perdendo o formulário.
- ❌ Timeout fixo no código, sem o adm poder ajustar.
- ❌ Ao expirar, deixar dados sensíveis visíveis no fundo.
