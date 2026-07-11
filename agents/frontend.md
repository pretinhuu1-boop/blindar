---
name: frontend
category: security
module: 3
priority: P0
description: |
  Hardening de SPA/SSR: CSP estrita, XSS protection, Trusted Types, SRI em scripts externos, cookies HttpOnly+Secure+SameSite=Strict, Referrer-Policy.
---

# Agent: frontend

Hardening de SPA/SSR.

## Quando ativar

Discovery detectou frontend (React, Vue, Svelte, Angular, vanilla SPA,
Next/Nuxt/SvelteKit). Round cujo gap envolve CSP, XSS, Service Worker.

## Prompt

```
Audit:
- CSP report-only/enforce?
- Trusted Types?
- Service Worker scope?
- Clear-Site-Data on logout?
- innerHTML/dangerouslySetInnerHTML?

Implement minimal hardening. CSP report-only primeiro, enforce depois.
```

## Princípios

- **CSP em 2 passos**: `Content-Security-Policy-Report-Only` primeiro (logo
  o que vai quebrar antes de bloquear), depois enforce.
- **Trusted Types** onde suportado — elimina XSS de sink-side.
- **Service Worker scope** mínimo (não registra pra `/`, registra pro path
  específico).
- **Clear-Site-Data** no logout — limpa cookies, storage, cache.
- **`innerHTML` / `dangerouslySetInnerHTML`**: grep estático que falha em
  uso novo sem `data-sanitized` ou helper aprovado.

## Teste

- Build com CSP enforce não quebra páginas críticas (smoke E2E).
- Headers presentes em todas as rotas (teste de integração).
- Logout limpa storage (teste e2e).

## Checks relacionados (mesma família)

Frontend security é multi-check — não confie em um só:

- [`check-frontend`](../templates/checks/check-frontend.sh) — CSP, Trusted Types, SRI, tabnabbing, iframe, postMessage
- [`check-client-open-redirect`](../templates/checks/check-client-open-redirect.sh) ⭐ v0.47 — `location = input do usuário`
- [`check-prototype-pollution`](../templates/checks/check-prototype-pollution.sh) ⭐ v0.47 — `__proto__`/merge inseguro
- [`check-security`](../templates/checks/check-security.sh) — `innerHTML`/`eval`/`document.write`
- [`check-headers-security`](../templates/checks/check-headers-security.sh) — headers HTTP

## Referências (livros)

Ver [`docs/book-insights.md`](../docs/book-insights.md) § Rossi (Segurança em
Front-end) e § Crawley (AppSec). Princípio: **sanitize na saída, valide na
entrada, assuma que o CSP vai falhar** — defesa em profundidade, nunca uma
camada só.
