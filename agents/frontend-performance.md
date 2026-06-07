# agent: frontend-performance

Fluidez percebida pelo usuário: Core Web Vitals, animation jank,
hidratação, latência percebida.

⚠ **Diferença vs `performance.md`**: aquele mede gargalo backend
(EXPLAIN ANALYZE, k6 p95). Este mede o que o **navegador do usuário**
sente.

## Quando ativar

Discovery detectou frontend (React, Vue, Svelte, Next, Nuxt, SvelteKit,
SPA vanilla, mobile web). Round cujo gap é da categoria
`frontend_performance` ou `ux_jank`.

## Métricas-alvo (Core Web Vitals, padrões Google 2024+)

| Métrica | Bom | Precisa melhorar | Ruim |
|---|---|---|---|
| **LCP** (Largest Contentful Paint) | ≤ 2.5s | 2.5-4s | > 4s |
| **INP** (Interaction to Next Paint) | ≤ 200ms | 200-500ms | > 500ms |
| **CLS** (Cumulative Layout Shift) | ≤ 0.1 | 0.1-0.25 | > 0.25 |
| **TTFB** (Time to First Byte) | ≤ 800ms | 0.8-1.8s | > 1.8s |
| **FCP** (First Contentful Paint) | ≤ 1.8s | 1.8-3s | > 3s |

> INP substituiu FID como Core Web Vital em março/2024. FID media só
> a primeira interação; INP mede todas e reflete melhor a fluidez real.

## Budget de bundle (sugerido — ajuste por contexto)

| Tipo | Mobile 3G | Desktop |
|---|---|---|
| JS inicial (gzipped) | ≤ 170kb | ≤ 350kb |
| CSS crítico inline | ≤ 14kb | ≤ 14kb |
| Imagem hero | ≤ 100kb | ≤ 200kb |
| Total above-the-fold | ≤ 500kb | ≤ 1MB |

## Prompt

```
Audit frontend perf:

1. Medir CWV reais (não só lab):
   - Lab: Lighthouse CI em PR (orçamento configurado).
   - RUM: ferramenta (web-vitals lib + endpoint próprio, OU
     Cloudflare/Vercel/Sentry analytics). Sem RUM, não há prova
     de fluidez real.

2. LCP — primeira pintura útil:
   - Preload do recurso LCP (font/imagem hero).
   - Image otimizada: AVIF/WebP, srcset, sizes, loading="eager" só
     no above-the-fold.
   - Sem render-blocking JS no <head> (defer/async).
   - SSR/SSG quando o conteúdo permite.

3. INP — responsividade a interações:
   - JS handler curto (≤50ms). Trabalho pesado → Web Worker ou
     scheduler.postTask + yieldToMain.
   - Evitar long tasks (>50ms) na main thread.
   - Throttle/debounce em handlers de scroll/input.
   - React: memo/useCallback APENAS onde profiler mostrou gargalo
     (não premature opt). Concurrent features (useTransition) pra
     state updates não-urgentes.

4. CLS — estabilidade visual:
   - width/height em <img> e <video> (calcula aspect ratio).
   - font-display: optional ou swap + size-adjust pra reduzir
     FOIT/FOUT shift.
   - Sem injeção dinâmica de conteúdo above-the-fold (banner,
     consent, etc.) sem reservar espaço.

5. Bundle size:
   - Code splitting por rota.
   - Lazy import de componentes pesados (modal, gráfico).
   - Tree shaking auditado (analyzer no CI).
   - Polyfills só pra navegadores alvo (browserslist atualizado).

6. Hydration (SSR):
   - Partial/Selective hydration onde a framework suporta
     (React Server Components, Astro islands, Qwik).
   - Defer hidratação de componentes below-the-fold.

7. Animações:
   - Só transform e opacity (compositor, não dispara layout).
   - will-change usado com parcimônia (custa memória).
   - 60fps mínimo (16.6ms budget); 120fps em mobile moderno (8.3ms).
   - Evitar animar layout (width/height/top/left).

Implement (≤80 LOC + config):
- Lighthouse CI configurado no CI com orçamento por métrica.
- web-vitals lib instalada, RUM enviando p/ endpoint.
- 1 fix do top-1 gargalo identificado.
- Teste de regressão: build falha se bundle inicial passa de N kb.
- sec.html: categoria frontend_performance com métricas baseline.

Princípio: MEDIÇÃO ANTES DE OTIMIZAR. Premature opt em frontend é
ainda pior que backend — gasta tempo otimizando coisa que o usuário
nem sente.
```

## Princípios não-negociáveis

- **RUM > Lab.** Lighthouse local mede 1 device com rede simulada.
  RUM mede milhares de devices reais. Sem RUM, você está medindo
  o seu MacBook Pro, não o usuário com Android low-end em 3G.
- **Budget enforçado em CI.** Bundle passou do limite → PR vermelho.
  Sem isso, regride mês a mês.
- **Otimização guiada por profiler.** React DevTools, Chrome
  Performance tab. Sem profile = sem PR.
- **Main thread é sagrada.** Tudo que não precisa renderizar vai
  pra Web Worker (parsing, criptografia client-side, ML inferência).
- **Layout / paint / composite** — sabe a diferença. Animar
  `transform` é composite (cheap). Animar `width` é layout (caro,
  cascateia).
- **Acessibilidade interage com perf.** Prefers-reduced-motion deve
  ser respeitado — não é opcional.

## Teste obrigatório (≥3 asserts)

- **Happy**: build produz bundle dentro do budget.
- **Edge**: import dinâmico de rota carrega chunk separado (CI verifica
  chunk file existe).
- **Regression**: snapshot de Lighthouse score; PR falha se cai >5
  pontos em qualquer métrica CWV.

## Ferramentas comuns

| Categoria | Ferramentas |
|---|---|
| Lab | Lighthouse, Lighthouse CI, WebPageTest |
| RUM | web-vitals lib + endpoint próprio, Sentry Performance, Vercel Analytics, Cloudflare Web Analytics |
| Bundle analyzer | webpack-bundle-analyzer, rollup-plugin-visualizer, vite-bundle-visualizer, source-map-explorer |
| Profiler | Chrome Performance, React DevTools Profiler |
| Image | Squoosh CLI, Sharp, imagemin (em build) |

## Adaptação por stack

| Stack | Atenção extra |
|---|---|
| **React (CSR)** | Concurrent features (useTransition, useDeferredValue), Suspense |
| **React Server Components / Next 14+** | Server Components default, client islands explícitos |
| **Vue 3** | Async components, defineAsyncComponent, KeepAlive |
| **Svelte/SvelteKit** | Compile-time já ajuda; foco em data fetching e prerendering |
| **Astro** | Islands architecture — ship JS apenas onde precisa |
| **Vanilla SPA** | Cuidado com framework "leve" virando pesado em features (~50kb vira ~300kb) |

## Mapeamento de frameworks

| Framework | Item relacionado |
|---|---|
| OWASP ASVS | V14 (configuration) — perf não é foco da ASVS |
| Web Performance Working Group | Core Web Vitals como métricas oficiais |
| Google Search ranking | CWV são fator de ranking desde 2021 |

## Limitações honestas

- **Não cobre app mobile nativo** (iOS/Android nativo tem outros KPIs:
  FPS, jank rate, ANR, cold start). Web Vitals é só web.
- **Não substitui UX research.** Métrica boa + UX ruim ainda existe.
- **Hidratação parcial está em evolução** — patterns mudam por
  framework. Defaults aqui podem envelhecer rápido.

## Origem dos números

Web Vitals thresholds são definidos publicamente pelo Google em
[web.dev/vitals](https://web.dev/vitals/) com base em Chrome UX Report
(CrUX), dataset de bilhões de pageviews reais. Não são chute deste
skill.
