---
name: seo-marketing-meta
category: frontend
module: 10
priority: P1
description: |
  Site/landing/SaaS sem SEO correto = não aparece em busca = não vende.
  Cobre: sitemap.xml + robots.txt, structured data JSON-LD por tipo de
  página, canonical URLs (evita conteúdo duplicado), Open Graph + Twitter
  Cards (preview em redes), hreflang em apps i18n, RSS opcional, IndexNow
  ping, Lighthouse SEO ≥ 90 como gate, schema.org compliance.
---

# Agent: seo-marketing-meta

## Missão

App moderna esquece SEO porque é "SaaS, não site". Erro caro: landing
pages, blog, páginas públicas de produto, links compartilhados → tudo
precisa rankear. Este agente prescreve o mínimo necessário pra Google,
Bing, redes sociais, LLM crawlers (ChatGPT/Perplexity).

## Quando rodar

- Módulo 10 selecionado E `ui_detected: true`
- Projeto tem **rotas públicas** (landing, blog, marketing, perfil público)
- Tipo do projeto ∈ {saas, ecom, landing, mobile}

## A. Meta tags essenciais (toda página)

```html
<!-- Título único por página, ≤ 60 chars -->
<title>Salon Pro — Gestão de salões de beleza</title>

<!-- Descrição única, 150-160 chars -->
<meta name="description" content="Software de gestão completa para salões: agenda, clientes, financeiro, WhatsApp integrado. Teste grátis." />

<!-- Canonical OBRIGATÓRIA (evita duplicate content) -->
<link rel="canonical" href="https://salonpro.com/" />

<!-- Viewport (já em mobile-first) -->
<meta name="viewport" content="width=device-width, initial-scale=1" />

<!-- Charset -->
<meta charset="UTF-8" />

<!-- Robots (default: index, follow) -->
<meta name="robots" content="index, follow, max-snippet:-1, max-image-preview:large" />

<!-- Theme color (consistente com manifest PWA) -->
<meta name="theme-color" content="#0066cc" />
```

### Anti-pattern

- ❌ Mesmo `<title>` em toda página
- ❌ Description duplicada ou ausente
- ❌ Canonical apontando pra URL com tracking params
- ❌ `noindex` em rota pública por engano

## B. Open Graph + Twitter Card (preview em redes)

```html
<meta property="og:type" content="website" />
<meta property="og:url" content="https://salonpro.com/" />
<meta property="og:title" content="Salon Pro — Gestão de salões" />
<meta property="og:description" content="..." />
<meta property="og:image" content="https://salonpro.com/og-image.png" />
<meta property="og:image:width" content="1200" />
<meta property="og:image:height" content="630" />
<meta property="og:locale" content="pt_BR" />
<meta property="og:site_name" content="Salon Pro" />

<meta name="twitter:card" content="summary_large_image" />
<meta name="twitter:site" content="@salonpro" />
<meta name="twitter:title" content="..." />
<meta name="twitter:description" content="..." />
<meta name="twitter:image" content="https://salonpro.com/og-image.png" />
```

### Imagem OG

- 1200×630px (proporção 1.91:1)
- < 1MB (carrega rápido em preview)
- Texto legível em thumbnail
- **Gerar dinâmica por página** (Vercel OG / Satori) — não 1 imagem genérica

## C. Structured data JSON-LD (rich results)

Escolher schema por tipo de página:

### Landing / SaaS (`SoftwareApplication`)

```html
<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "SoftwareApplication",
  "name": "Salon Pro",
  "operatingSystem": "Web",
  "applicationCategory": "BusinessApplication",
  "offers": { "@type": "Offer", "price": "49.90", "priceCurrency": "BRL" },
  "aggregateRating": { "@type": "AggregateRating", "ratingValue": "4.8", "reviewCount": "127" }
}
</script>
```

### Empresa / footer (`Organization`)

```html
<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "Organization",
  "name": "Salon Pro Tecnologia",
  "url": "https://salonpro.com",
  "logo": "https://salonpro.com/logo.png",
  "sameAs": ["https://twitter.com/salonpro", "https://instagram.com/salonpro", "https://linkedin.com/company/salonpro"]
}
</script>
```

### Blog post (`Article`)

```json
{
  "@type": "Article",
  "headline": "...",
  "author": { "@type": "Person", "name": "..." },
  "datePublished": "2026-06-14",
  "dateModified": "2026-06-14",
  "image": ["..."]
}
```

### Produto e-com (`Product`)

```json
{
  "@type": "Product",
  "name": "...",
  "image": ["..."],
  "description": "...",
  "sku": "...",
  "offers": {
    "@type": "Offer",
    "price": "99.00",
    "priceCurrency": "BRL",
    "availability": "https://schema.org/InStock"
  },
  "aggregateRating": { "@type": "AggregateRating", "ratingValue": "4.5", "reviewCount": "42" }
}
```

### FAQ (rich snippet de pergunta-resposta)

```json
{
  "@type": "FAQPage",
  "mainEntity": [
    {
      "@type": "Question",
      "name": "Como cancelar?",
      "acceptedAnswer": { "@type": "Answer", "text": "..." }
    }
  ]
}
```

### Breadcrumb

```json
{
  "@type": "BreadcrumbList",
  "itemListElement": [
    { "@type": "ListItem", "position": 1, "name": "Início", "item": "https://example.com/" },
    { "@type": "ListItem", "position": 2, "name": "Blog", "item": "https://example.com/blog" }
  ]
}
```

### Validação

- **Google Rich Results Test** (`https://search.google.com/test/rich-results`)
- **Schema.org Validator**
- Em CI: lint com `schema-dts` (tipos TypeScript) ou `next-seo`

## D. sitemap.xml

```xml
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"
        xmlns:xhtml="http://www.w3.org/1999/xhtml">
  <url>
    <loc>https://example.com/</loc>
    <lastmod>2026-06-14</lastmod>
    <changefreq>weekly</changefreq>
    <priority>1.0</priority>
    <xhtml:link rel="alternate" hreflang="pt-BR" href="https://example.com/" />
    <xhtml:link rel="alternate" hreflang="en-US" href="https://example.com/en/" />
  </url>
  <!-- ... -->
</urlset>
```

### Geração automática

- Next.js: `app/sitemap.ts` retorna lista
- Atualizar via cron ou rebuild quando conteúdo muda
- Múltiplos sitemaps + index se > 50k URLs ou > 50MB
- Submeter no **Google Search Console** + **Bing Webmaster**

## E. robots.txt

```
User-agent: *
Allow: /
Disallow: /admin/
Disallow: /api/
Disallow: /*?utm_*
Disallow: /search?*

Sitemap: https://example.com/sitemap.xml

# Permitir crawlers de LLM
User-agent: GPTBot
Allow: /

User-agent: ClaudeBot
Allow: /

User-agent: PerplexityBot
Allow: /
```

Decisão: bloquear ou permitir LLM crawlers? Documento + decida com
stakeholder.

## F. Hreflang (i18n SEO)

```html
<link rel="alternate" hreflang="pt-BR" href="https://example.com/" />
<link rel="alternate" hreflang="en-US" href="https://example.com/en/" />
<link rel="alternate" hreflang="es-ES" href="https://example.com/es/" />
<link rel="alternate" hreflang="x-default" href="https://example.com/" />
```

Sem isso, Google mostra versão errada por região.

## G. Performance impacta SEO

Core Web Vitals (já cobertos em `responsive-a11y` / `frontend-performance`)
são ranking factor hard:
- LCP ≤ 2.5s
- INP ≤ 200ms
- CLS ≤ 0.1

Mobile-friendly check (já gates em responsive-a11y).

## H. URL structure

- Slug legível: `/blog/como-gerenciar-agenda` (não `/blog/?id=42`)
- Trailing slash consistente (escolher e redirect 301)
- Sem `?utm_*` na canonical (mas aceitar pra tracking)
- Status 200 em página, 301 em redirect, 404 em not-found, **NUNCA 200 em erro**

## I. Indexação acelerada

- **IndexNow** ping a Bing/Yandex quando conteúdo muda
- **Google Indexing API** (job postings + livestreams oficialmente)
- Compartilhar em redes sociais (sinaliza freshness)

## J. Greps obrigatórios

```bash
# <title> hardcoded em todas as páginas
rg -n "<title>" --type tsx --type jsx | sort -u | wc -l

# Meta description ausente
rg -L "name=\"description\"" --type tsx --type jsx -g 'app/**/page.*' -g 'pages/**/*.tsx'

# Canonical ausente em página pública
rg -L "rel=\"canonical\"" --type tsx -g 'app/(marketing|public)/**'

# OG image hardcoded (deveria ser dinâmico)
rg -n "og-image\.(png|jpg)" --type tsx -g '!*.config.*'

# Robots meta noindex em página publica (red flag)
rg -n "noindex" --type tsx --type jsx -g 'app/**'
```

## Output esperado em sec.html

```
┌─ SEO + Marketing Meta (Módulo 10) ───────────────────────┐
│ Title único por página        : ✅ 47/47 rotas públicas   │
│ Description única             : ✅                         │
│ Canonical URL                 : ✅                         │
│ Open Graph (1200x630)         : ✅ dinâmica por rota      │
│ Twitter Card                  : ✅                         │
│ Structured data JSON-LD       : ✅ Organization + 5 tipos │
│ Rich Results Test             : ✅ green                   │
│ sitemap.xml                   : ✅ auto-gen 234 URLs       │
│ robots.txt                    : ✅                         │
│ hreflang (i18n)               : ✅ pt-BR/en-US/es-ES      │
│ Breadcrumb structured         : ✅                         │
│ Lighthouse SEO                : 98 ✅ (gate ≥ 90)         │
│ URL slugs legíveis            : ✅                         │
│ Google Search Console         : ✅ submetido              │
│ IndexNow ping                 : ✅ ativo                   │
│ Status                        : ✅ INDEXABLE              │
└───────────────────────────────────────────────────────────┘
```

## Intelligence (⭐ v0.21) — rotas que NÃO devem ser indexadas

App tem rotas públicas (precisam SEO) E rotas privadas/admin
(intencionalmente `noindex`). Lê `.blindar/intelligence.yml`:

```yaml
seo-marketing-meta:
  noindex_routes:
    # Rotas que DEVEM ter noindex (não acusar falta de canonical/og)
    - "/admin/*"
    - "/app/*"                   # área autenticada
    - "/dashboard/*"
    - "/settings/*"
    - "/api/*"
    - "/internal/*"
    - "/login"
    - "/signup"
    - "/forgot-password"
    - "/account/*"

  public_routes:
    # Rotas onde TODO SEO check é obrigatório
    - "/"
    - "/blog/*"
    - "/products/*"
    - "/about"
    - "/contact"
    - "/pricing"
    - "/features"

  hreflang_required:
    # Apenas em rotas multi-idioma de marketing
    - "/blog/*"
    - "/"
    - "/pricing"

  json_ld_by_route_type:
    # Schema.org type por padrão de rota
    "/blog/*": "Article"
    "/products/*": "Product"
    "/courses/*": "Course"
    "/events/*": "Event"
    "/jobs/*": "JobPosting"
    "/people/*": "Person"
    "/faq*": "FAQPage"
    "/": "Organization"

  llm_crawlers:
    # Política pra crawlers de LLM
    allow:
      - GPTBot
      - ClaudeBot
      - PerplexityBot
    deny:
      - CCBot                    # Common Crawl pode ser indesejado
    require_decision: false      # default: pergunta no launcher

  ignore_lighthouse_in:
    # Rotas onde Lighthouse SEO não importa
    - "/api/*"
    - "/internal/*"
    - "/_next/*"

  inline_override_marker: "// @blindar:noindex"
```

### Markers no Next.js

```ts
// app/admin/page.tsx
export const metadata: Metadata = {
  robots: 'noindex, nofollow',         // seo-marketing-meta respeita
};

/**
 * @blindar:noindex -- intencionalmente fora do índice
 */
```

### Auto-detecção

- Rota com `metadata.robots = 'noindex'` → todos os SEO checks skipped
- Rota dentro de `(app)`, `(dashboard)`, `(admin)` route groups → privada
- Rota com `redirect()` em layout → não-indexável
- Rota com middleware de auth obrigatória → privada

### Modo "site institucional" vs "SaaS multi-page"

```yaml
seo-marketing-meta:
  site_type: saas               # saas | ecommerce | content | landing
  # ↑ blindar adapta defaults:
  # - saas: só /, /pricing, /features, /blog são públicas
  # - ecommerce: /, /products/* todos públicos
  # - content: tudo público exceto /admin
```

### Public sitemap vs internal

```yaml
seo-marketing-meta:
  sitemap:
    public:
      generate: true
      path: /sitemap.xml
      include: ["public_routes pattern"]
      exclude: ["noindex_routes pattern"]
    internal:
      # Sitemap separado pra search interna (opcional)
      generate: false
```

## Anti-padrões

- ❌ Mesmo `<title>` em toda página
- ❌ Description duplicada ou ausente
- ❌ Canonical com `?utm_*` (parâmetro de tracking)
- ❌ OG image única estática pra todas páginas
- ❌ `noindex` em página pública por engano
- ❌ Status 200 em página de erro (Google indexa "erro")
- ❌ URL com `?id=42` em vez de slug
- ❌ Trailing slash inconsistente (`/blog` e `/blog/` ambas indexam)
- ❌ Sem sitemap (descobrir é por sorte)
- ❌ Sem hreflang em app multi-idioma (versão errada por região)
- ❌ JSON-LD inválido (avisos no Search Console)
- ❌ Imagem OG > 5MB (preview não renderiza)
