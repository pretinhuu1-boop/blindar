# agent: frontend

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
