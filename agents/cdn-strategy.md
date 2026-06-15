---
name: cdn-strategy
category: performance
module: 9
priority: P1
description: |
  Estratégia de cache em camadas: browser → CDN → app → DB. Cache hit
  rate > 80%, immutable assets com hash, signed URLs com expiração,
  invalidação correta por tag/path, image optimization (AVIF/WebP/
  BlurHash placeholder), Cloudflare/Fastly/Vercel headers, anti-hotlink.
  Resolve "performance ruim com custo alto" — fora típico de cache cego
  ou cache ausente.
---

# Agent: cdn-strategy

## Missão

Cache errado = lentidão + custo. Cache ausente = origin servidor saturado.
Cache infinito em dado dinâmico = user vê dado velho. Este agente
prescreve a estratégia em camadas correta.

## Quando rodar

- Módulo 9 selecionado
- Detectado: Cloudflare, Vercel, Fastly, AWS CloudFront em config
- Operador pediu "cache", "CDN", "performance assets"

## A. Camadas de cache

```
Browser cache (immutable, 1 ano)
   ↓ (miss)
CDN edge (Cloudflare/Vercel/Fastly)
   ↓ (miss)
App cache (Redis, 60s-1h)
   ↓ (miss)
DB
```

## B. Cache-Control por tipo de conteúdo

| Tipo | Header | TTL |
|---|---|---|
| Asset estático com hash (`/_next/static/abc.js`) | `public, max-age=31536000, immutable` | 1 ano |
| Imagem de produto (estável) | `public, max-age=2592000, stale-while-revalidate=86400` | 30 dias |
| Avatar de user (muda eventualmente) | `public, max-age=3600, stale-while-revalidate=86400` | 1h + 1d SWR |
| Homepage (atualiza diário) | `public, max-age=60, stale-while-revalidate=3600` | 60s + 1h SWR |
| Página de produto (preço pode mudar) | `public, max-age=30, stale-while-revalidate=300, must-revalidate` | 30s |
| API GET (read-only) | `private, max-age=10, stale-while-revalidate=30` | 10s |
| API com user data | `private, no-cache` | 0 |
| Auth / pagamento | `private, no-store` | 0 |

## C. Immutable assets com hash

```
✅ /_next/static/chunks/main-abc123.js  ← max-age=31536000, immutable
✅ /images/logo.v3.png                    ← versionado no path
❌ /images/logo.png                       ← se mudar, todos browsers cacheam errado
```

Next.js, Vite, webpack fazem hash automático em build.

## D. Invalidação por TAG (não por path)

```ts
// Vercel/Next.js
import { revalidateTag } from 'next/cache';
await db.product.update({ where: { id }, data: { price } });
revalidateTag(`product:${id}`);
revalidateTag(`category:${product.categoryId}`);   // lista também invalida

// Fetch com tag
const data = await fetch(url, { next: { tags: [`product:${id}`] } });
```

Tag-based scale melhor que path-based em sites com milhares de URLs.

## E. Image optimization

```tsx
import Image from 'next/image';

<Image
  src="/photos/foo.jpg" alt="Cabelo cor castanho"
  width={800} height={600}
  sizes="(max-width: 768px) 100vw, 800px"
  placeholder="blur" blurDataURL={blurhash}
  priority={isAboveFold}
/>
```

- Servido AVIF/WebP com fallback JPEG (Accept header)
- Resize on-the-fly via Cloudflare Images / imgproxy / Next.js
- BlurHash placeholder (300 bytes) → LCP melhora
- `priority` em hero image (preload)
- `loading="lazy"` em tudo abaixo da dobra (default)

## F. Signed URLs (conteúdo privado)

```ts
// S3 / R2
const url = await s3.getSignedUrl('getObject', {
  Bucket: 'docs', Key: file.key,
  Expires: 900,                                 // 15min
  ResponseContentDisposition: `attachment; filename="${sanitize(file.name)}"`,
});
```

CDN respeita signed URL via Cloudflare Workers ou Vercel rewrites.

## G. Anti-hotlink

```ts
// Cloudflare Worker
addEventListener('fetch', event => {
  const url = new URL(event.request.url);
  const referer = event.request.headers.get('Referer');
  if (url.pathname.startsWith('/images/private/') && referer && !referer.includes('example.com')) {
    return event.respondWith(new Response('Forbidden', { status: 403 }));
  }
});
```

OU: signed URLs sempre.

## H. Cache hit rate (métrica chave)

```bash
# Cloudflare analytics
# Meta: > 80% pra assets estáticos, > 60% pra páginas
```

Hit rate baixo = config errada (TTLs curtos, miss de header, query params variando).

### Causas comuns de cache miss

- `?utm_*` na URL (cada UTM = nova chave)
- Cookie no request (sem `cache-control: public`)
- Headers `Authorization` cruzando CDN
- `Vary: User-Agent` (cada UA = nova entrada)
- `Set-Cookie` no response

## I. Egress (custo)

```yaml
# Cloudflare R2 / Backblaze B2: ZERO egress
# AWS S3: $0.09/GB
# Servir imagem grande do S3 direto = caro
```

Pra projetos com vídeo/imagem pesado, **migrar pra R2** economiza milhares
por mês.

## J. Headers obrigatórios

```
Strict-Transport-Security: max-age=31536000; includeSubDomains; preload
Vary: Accept-Encoding, Accept                   ← variação correta
X-Content-Type-Options: nosniff
Cross-Origin-Resource-Policy: same-origin       ← anti-XSSI
Content-Security-Policy: default-src 'self'; ...
```

## K. Greps

```bash
# Asset sem hash no path (cache eterno = bug eterno)
rg -n "src=['\"](/images|/assets)[^'\"]*\.(js|css|png|jpg)['\"]" --type tsx | rg -v "[a-f0-9]{6,}"

# fetch sem next.tags ou cache directive
rg -n "fetch\(['\"]https?://api" --type ts -A 3 | rg -v "(next:|cache:|revalidate:)"

# Cache-Control faltando
rg -n "res\.send|res\.json" --type ts -B 5 | rg -v "Cache-Control"

# Imagem sem next/image (sem optimization)
rg -n "<img " --type tsx -g '!**/email/**'
```

## Output em sec.html

```
┌─ CDN Strategy (Módulo 9) ────────────────────────────────┐
│ Provider                      : Cloudflare                │
│ Assets immutable (hash)       : ✅ 100%                   │
│ Cache hit rate                : 94% ✅ (meta > 80%)       │
│ Image optimization (AVIF/WebP): ✅ + BlurHash placeholder │
│ Signed URLs em privado        : ✅ 15min                  │
│ Anti-hotlink                  : ✅ Worker                 │
│ Tag-based invalidation        : ✅ Next.js cache tags     │
│ Egress (mês)                  : 2.1 TB (R2 - gratuito)    │
│ Vary headers corretos         : ✅                        │
│ Status                        : ✅ FAST + CHEAP          │
└───────────────────────────────────────────────────────────┘
```

## Anti-padrões

- ❌ Asset sem hash no nome (mudou, browser cacheia errado)
- ❌ `Cache-Control: no-cache` em tudo (CDN inútil)
- ❌ `Cache-Control: max-age=31536000` em dado dinâmico (user vê velho)
- ❌ `Cache-Control` com cookie no request (CDN não cacheia)
- ❌ `?utm_*` na canonical (cada variação vira nova entrada)
- ❌ Imagem servida do S3 direto (egress caro)
- ❌ `<img>` cru sem next/image (sem optimization, sem lazy)
- ❌ Invalidação por path em catálogo grande (lento, custoso)
- ❌ Cache hit < 50% sem investigar
- ❌ `Vary: *` (cache só não)
- ❌ Sem CORP header (asset vaza pra outros sites cross-origin)
- ❌ Signed URL eterna (deveria ter expiração curta)
