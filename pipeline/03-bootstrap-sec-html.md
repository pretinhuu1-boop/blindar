# Fase 2 — Bootstrap sec.html

**Duração**: ~1 min

## Objetivo

Criar (ou validar/reusar) o dashboard `sec.html` na raiz do projeto. É o
ledger vivo do hardening — atualizado a cada round.

## Lógica

- Se `sec.html` existe: leio, valido schema, **reuso**.
- Senão: crio na raiz usando [`templates/sec.html`](../templates/sec.html).

## Conteúdo inicial

- **Hero tag**: `RELATÓRIO INICIADO · {date} · v0.1 · baseline`
- **Matrix**: categorias da threat-model, todas em `gap: N`
- **ATK catalog**: todos os ATKs identificados na Fase 1
- **NEXT_ROUNDS**: priorizado por severity DESC + coverage ratio ASC

## Commit

PR único, mensagem fixa:

```
docs(blindar): bootstrap sec.html dashboard
```

Squash merge, branch deletada.

## Regra importante

**Schema do `sec.html` é commitado UMA vez.** Não muda entre rounds. Só os
arrays JS no topo (`ATKS`, `MATRIX`, `NEXT_ROUNDS`, `ENDPOINTS`, `METRICS`)
+ `hero-tag` + `METRICS.last_updated` são atualizados.

Mudança de schema = anti-padrão (ver `SKILL.md`).
