---
name: responsive-a11y
category: frontend
module: 10
priority: P1
description: |
  Garante que a UI funciona em mobile/tablet/desktop, atende WCAG AA,
  passa nos Core Web Vitals e tem fluidez (animações ≤300ms, sem layout
  shift). Mobile-first obrigatório. Bloqueia release se Lighthouse < 90.
---

# Agent: responsive-a11y

## Missão

A UI é:
1. **Responsiva**: funciona em 320px–4K sem scroll horizontal
2. **Acessível**: WCAG AA mínimo (AAA em texto principal se viável)
3. **Fluida**: 60fps, animações ≤300ms, zero layout shift acima da dobra
4. **Mobile-first**: design começa do mobile, expande pra desktop

## Quando rodar

- Módulo 10 selecionado
- Sempre se `ui_detected: true` (Fase 1)
- Após cada PR que toca CSS / componentes visuais

## Auditorias obrigatórias

### 1. Lighthouse CI (4 pilares)

```yaml
# .github/workflows/lighthouse.yml (criar se não existir)
- uses: treosh/lighthouse-ci-action@v11
  with:
    urls: |
      http://localhost:3000/
      http://localhost:3000/dashboard
    budgetPath: .lighthouserc.json
    uploadArtifacts: true
```

```json
// .lighthouserc.json
{
  "ci": {
    "assert": {
      "assertions": {
        "categories:performance":   ["error", { "minScore": 0.90 }],
        "categories:accessibility": ["error", { "minScore": 0.95 }],
        "categories:best-practices":["error", { "minScore": 0.95 }],
        "categories:seo":           ["error", { "minScore": 0.90 }],
        "largest-contentful-paint": ["error", { "maxNumericValue": 2500 }],
        "cumulative-layout-shift":  ["error", { "maxNumericValue": 0.10 }],
        "interaction-to-next-paint":["error", { "maxNumericValue": 200 }]
      }
    }
  }
}
```

### 2. Responsividade — viewport matrix

Playwright spec roda em **5 breakpoints**:

| Viewport | Largura | Dispositivo de referência |
|---|---|---|
| Mobile S | 320 | iPhone SE legacy |
| Mobile L | 375 | iPhone 13/14/15 |
| Tablet | 768 | iPad portrait |
| Desktop | 1440 | Laptop MBP 14" |
| Wide | 1920 | Monitor FHD |

Para cada viewport:
- [ ] Zero scroll horizontal (`document.documentElement.scrollWidth <= clientWidth`)
- [ ] Nenhum texto cortado (`text-overflow: ellipsis` ou wrap)
- [ ] Botões com touch target ≥ 44x44px (mobile)
- [ ] Sidebar/menu colapsa em mobile (≤ 768px)
- [ ] Imagens não estouram container (`max-width: 100%`)
- [ ] Tabelas têm scroll horizontal próprio ou viram cards (mobile)

```ts
// auto-gerado por blindar/agents/responsive-a11y
test.describe('Responsividade', () => {
  for (const vp of VIEWPORTS) {
    test(`${vp.name} (${vp.width}px) — sem scroll horizontal`, async ({ page }) => {
      await page.setViewportSize({ width: vp.width, height: 800 });
      await page.goto('/');
      const overflow = await page.evaluate(
        () => document.documentElement.scrollWidth - document.documentElement.clientWidth
      );
      expect(overflow, `scroll horizontal de ${overflow}px em ${vp.name}`).toBeLessThanOrEqual(1);
    });

    test(`${vp.name} — touch targets ≥ 44x44px (se mobile)`, async ({ page }) => {
      if (vp.width > 768) test.skip();
      await page.setViewportSize({ width: vp.width, height: 800 });
      await page.goto('/');
      const small = await page.locator('button:visible, a:visible').evaluateAll(
        els => els
          .map(e => e.getBoundingClientRect())
          .filter(r => r.width < 44 || r.height < 44)
          .length
      );
      expect(small, `${small} elementos abaixo de 44px em ${vp.name}`).toBe(0);
    });
  }
});
```

### 3. Acessibilidade (WCAG AA)

Usar **axe-core** via Playwright:

```ts
import AxeBuilder from '@axe-core/playwright';

test('a11y — zero violações WCAG AA', async ({ page }) => {
  await page.goto('/');
  const results = await new AxeBuilder({ page })
    .withTags(['wcag2a', 'wcag2aa', 'wcag21aa'])
    .analyze();
  expect(results.violations, JSON.stringify(results.violations, null, 2)).toEqual([]);
});
```

Greps específicos:

```bash
# Imagens sem alt
rg -n "<img(?![^>]*alt=)" --type tsx --type jsx --type html

# Botões / links sem texto acessível
rg -n "<button[^>]*>\s*</button>" --type tsx --type jsx
rg -n "<a[^>]*>\s*</a>" --type tsx --type jsx
rg -n "<button[^>]*>\s*<svg" --type tsx --type jsx | rg -v "aria-label"

# outline:none sem :focus-visible substituto
rg -n "outline:\s*none|outline:\s*0" --type css --type scss

# Inputs sem label
# (precisa de análise estrutural — Playwright fica responsável)

# Heading hierarchy quebrada — checada via axe
```

### 4. Fluidez (motion)

- Animações duram 150–300ms (não mais que 500ms)
- `prefers-reduced-motion: reduce` desativa animações
- Transições usam `transform` e `opacity` (não `width`/`height`/`top`/`left`)
- Zero CLS acima da dobra
- Hover/focus tem feedback < 100ms

```bash
# Animações longas demais
rg -n "transition:[^;]*([5-9]\d{2}ms|[1-9]s)" --type css

# Falta prefers-reduced-motion
rg -l "prefers-reduced-motion" --type css || \
  echo "⚠ Nenhum CSS respeita prefers-reduced-motion — adicionar"
```

### 5. Dark mode (se aplicável)

- [ ] Tokens semânticos (`--color-bg-primary`), nunca hardcoded
- [ ] `prefers-color-scheme` detectado + override manual
- [ ] Aplicado antes do render (sem flash — script inline no `<head>`)
- [ ] Contraste WCAG AA em ambos os temas
- [ ] Imagens/ícones usam `currentColor` ou variantes por tema

## Checklist visual (manual ou via screenshots Playwright)

- [ ] Empty states: ícone + título + texto + CTA (nunca vazio)
- [ ] Loading: skeleton, não spinner
- [ ] Erros: mensagem amigável + sugestão de ação
- [ ] Sidebar fecha ao navegar (mobile)
- [ ] Modal trava scroll do body
- [ ] Toast some sozinho em 4–6s
- [ ] Form: erro inline ao perder foco do campo
- [ ] Botão de submit: loading state + previne double-click
- [ ] Scroll-to-top em páginas longas
- [ ] Breadcrumb em navegação profunda (≥ 2 níveis)

## Output esperado

Atualizar `sec.html`:

```
┌─ Fluidez + a11y + responsivo (Módulo 10) ────────────────┐
│ Lighthouse Performance       : 94  ✅                      │
│ Lighthouse Accessibility     : 98  ✅                      │
│ Lighthouse Best Practices    : 96  ✅                      │
│ Lighthouse SEO               : 100 ✅                      │
│ LCP (mobile)                 : 1.8s ✅                     │
│ CLS                          : 0.04 ✅                     │
│ INP                          : 145ms ✅                    │
│ axe violations (WCAG AA)     : 0   ✅                      │
│ Touch targets < 44px (mobile): 0   ✅                      │
│ Scroll horizontal            : 0   ✅                      │
│ prefers-reduced-motion       : ✅ respeitado               │
│ Status                       : ✅ GREEN                    │
└───────────────────────────────────────────────────────────┘
```

## Bloqueia merge se

- Lighthouse < 90 em qualquer pilar (Perf/A11y/BP/SEO)
- Qualquer violação axe-core WCAG AA
- Scroll horizontal em qualquer viewport
- Touch target < 44x44px em mobile
- LCP > 2.5s no mobile
- CLS > 0.1
- INP > 200ms

## Intelligence (⭐ v0.21) — quando NÃO acusar

Responsive-a11y respeita decisões intencionais documentadas em
`.blindar/intelligence.yml`:

```yaml
responsive-a11y:
  respect_aria_hidden: true        # default — elementos com aria-hidden="true" são ignorados
  respect_data_blindar_skip: true  # qualquer elemento com data-blindar-skip="true"

  desktop_only_routes:
    # Rotas intencionalmente desktop-only (admin, BI dashboards complexos)
    - "/admin/reports/*"
    - "/admin/analytics"
    - "/internal/data-explorer"
    # blindar não acusa "scroll horizontal em mobile" nessas rotas

  mobile_only_routes:
    # Rotas intencionalmente mobile-first (checkout, payment)
    - "/checkout/*"
    - "/pay/*"

  touch_target_exempt_selectors:
    # Elementos que LEGITIMAMENTE são menores que 44x44
    - "button.icon-only[aria-label]"   # ícone com label tem hit area expandida via CSS
    - ".badge"                          # decorativo, não clicável
    - ".inline-link"                    # link inline no meio de texto

  lighthouse_thresholds_per_route:
    # Threshold por rota — admin/internal pode ser mais permissivo
    "/admin/*":
      performance: 70                  # admin não precisa de 90
    "/checkout/*":
      performance: 95                  # checkout é crítico, mais rigor

  ignore_violations:
    # axe-core rule IDs aceitos com motivo documentado
    - rule: "color-contrast"
      selector: ".disabled-button"
      reason: "Visual tem propósito UX — disabled é menos contraste de propósito"
      adr: "docs/adr/0008-disabled-state-contrast.md"
```

### Markers inline no JSX

```tsx
<div aria-hidden="true">
  {/* ícone decorativo — blindar ignora */}
  <Icon name="sparkle" />
</div>

<div data-blindar-skip="true">
  {/* tooltip que tem renderização específica */}
  <Tooltip />
</div>

{/* @blindar:viewport-desktop-only -- BI dashboard precisa de espaço */}
<DataExplorer />
```

### Auto-detecção

- Elemento com `aria-hidden="true"` → não acusa contraste/tamanho
- Elemento com `role="presentation"` → decorativo, ignora a11y rules
- Elemento dentro de `<svg>` sem `aria-label` → decorativo
- Componente Storybook (`*.stories.tsx`) → não acusa (é showcase, não rota real)

### Modo dev vs prod

```yaml
responsive-a11y:
  strict_in_production_only:
    # CRIT em prod, WARN em dev (não bloqueia merge local)
    - lighthouse_performance
    - lcp_threshold
    - cls_threshold
  always_strict:
    # CRIT em qualquer ambiente
    - touch_target_size
    - color_contrast
    - aria_required
```

## Anti-padrões

- ❌ `outline: none` sem substituto visível para foco
- ❌ Placeholder como label (`<input placeholder="Email">` sem `<label>`)
- ❌ Usar só cor pra indicar erro (precisa de ícone/texto também)
- ❌ Texto < 14px em mobile
- ❌ Contraste < 4.5:1 em texto normal
- ❌ Animar `width`/`height`/`top`/`left` (causa layout shift)
- ❌ `position: fixed` em mobile sem testar com teclado virtual aberto
