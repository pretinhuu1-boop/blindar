---
name: client-open-redirect
category: security
module: 3
priority: P1
description: |
  Detecta open redirect no lado cliente — window.location/.href/.assign/
  window.open recebendo valor derivado de location.search/query/param sem
  validação de allowlist. Vetor de phishing que o check server-side não pega.
---

# Agent: client-open-redirect

## Missão

Impedir que um link tipo `app.com/go?url=https://phishing.com` redirecione o
usuário pra fora do domínio. O `check-security` já cobre o redirect **servidor**
(`res.redirect(req.query...)`); este cobre o **navegador**
(`location.href = params.get('url')`), que grep server-side não alcança.
Fonte: [`docs/book-insights.md`](../docs/book-insights.md) § Rossi.

## Quando rodar

- Módulo 3 (frontend hardening) — se UI detectada
- Complementa `check-frontend` e `check-security`

## O que dispara finding

| Padrão | Severidade |
|---|---|
| `location.href = <valor de location.search/query/param>` | high |
| `location.assign(x)` / `location.replace(x)` com x do usuário | high |
| `window.open(userUrl)` sem validação | high |
| Variável extraída de `URLSearchParams`/`params.get` atribuída a `location` sem allowlist | high |

## Como blindar

```js
// Allowlist de destinos ou caminho relativo
function safeRedirect(raw) {
  // 1. Só caminho relativo interno
  if (raw.startsWith('/') && !raw.startsWith('//')) return raw;
  // 2. Ou host explicitamente permitido
  const ALLOW = ['app.example.com', 'account.example.com'];
  try {
    const u = new URL(raw, location.origin);
    if (ALLOW.includes(u.host)) return u.href;
  } catch {}
  return '/';                       // fallback seguro
}
location.href = safeRedirect(params.get('url'));
```

## Falso positivo — como suprimir

- O check já ignora linhas/arquivos com `allowlist`, `whitelist`, `isSafe`,
  `sanitizeUrl`, `new URL(`, `startsWith('/')` ou marcador `@blindar:keep`.
- Redirect pra constante fixa (não-usuário) não dispara.

## Intelligence

Respeita `.blindar/intelligence.yml` via `load_intelligence_globs`.
