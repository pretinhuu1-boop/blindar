---
name: visual-regression
category: quality
module: 11
priority: P2
description: |
  Chromatic/Percy/Playwright snapshots como gate de CI: detecta diff de
  pixel em UI, baseline gating (PR aprovado antes de merge), review
  workflow com aprovação manual em mudanças intencionais. Pra design
  systems / produtos com UI rica. Pega regressão visual que test
  funcional não pega.
---

# Agent: visual-regression

## Missão

Test funcional verifica "botão dispara handler" — não verifica "botão
ficou cor laranja em vez de azul" depois que mudou um CSS distante.
Visual regression pega isso. Importante em design system ou produto
com UI consistente.

## Quando rodar

- Módulo 11 selecionado
- Detectado: Storybook + componentes compartilhados
- Operador pediu "design system", "visual test", "Chromatic"

## A. Ferramentas

| Tool | Quando |
|---|---|
| **Chromatic** | Storybook-first, hosted, melhor DX, free pra OSS |
| **Percy** (BrowserStack) | Hosted, integração com Cypress/Playwright |
| **Playwright `toHaveScreenshot`** | Self-hosted, integrado com tests E2E |
| **Loki** | Open source, Storybook + Docker |
| **Reg-suit** | Open source, mais setup |

Recomendação: **Chromatic** se já tem Storybook. **Playwright** se já tem E2E.

## B. Workflow

```
1. PR aberto
2. CI roda visual tests
3. Compara contra baseline (main branch)
4. Diff > threshold (1%):
   ├─ Intencional: reviewer aprova → vira nova baseline
   └─ Bug: PR vermelho até corrigir
```

## C. Storybook + Chromatic

```bash
# Install
npm i -D chromatic

# Run
npx chromatic --project-token=xxx --exit-zero-on-changes
```

CI:
```yaml
- name: Visual regression
  run: npx chromatic --project-token=${{ secrets.CHROMATIC_TOKEN }}
  env:
    CHROMATIC_ONLY_CHANGED: true   # só stories que mudaram
```

## D. Playwright `toHaveScreenshot`

```ts
test('Login page visual', async ({ page }) => {
  await page.goto('/login');
  await expect(page).toHaveScreenshot('login-page.png', {
    maxDiffPixels: 100,
    fullPage: true,
    animations: 'disabled',
  });
});
```

Update baseline:
```bash
npx playwright test --update-snapshots
```

## E. O que testar

Sim:
- Componentes do design system (Button, Input, Card)
- Páginas inteiras críticas (login, checkout, dashboard)
- Estados visuais (loading, empty, error, success)
- Dark mode + light mode
- Responsive breakpoints (mobile/tablet/desktop)

Não:
- Páginas com dados dinâmicos não-determinísticos (timestamp, random)
- Animações em meio do loop
- Conteúdo gerado por LLM

## F. Determinismo (snapshots estáveis)

```ts
// Fixar tudo que muda
await page.evaluate(() => {
  // Fix timezone
  Object.defineProperty(Date.prototype, 'getTimezoneOffset', { value: () => 180 });
  // Fix random
  Math.random = () => 0.5;
  // Disable animations
  document.body.style.animation = 'none';
  document.body.style.transition = 'none';
});

// Aguardar fonts
await page.evaluate(() => document.fonts.ready);
// Aguardar imagens
await page.waitForLoadState('networkidle');
```

## G. Cross-browser

Mesma UI em 3 engines:
- Chromium (Chrome/Edge)
- Firefox
- WebKit (Safari)

Cada um renderiza ligeiramente diferente. Storybook + Chromatic faz
multi-browser automaticamente.

## H. Cross-viewport

```ts
const viewports = [
  { name: 'mobile',  width: 375, height: 667 },
  { name: 'tablet',  width: 768, height: 1024 },
  { name: 'desktop', width: 1440, height: 900 },
];

for (const vp of viewports) {
  test(`${vp.name}: dashboard`, async ({ page }) => {
    await page.setViewportSize(vp);
    await page.goto('/dashboard');
    await expect(page).toHaveScreenshot(`dashboard-${vp.name}.png`);
  });
}
```

## I. Review workflow

Reviewer no PR vê:
- "12 visual changes detected"
- Galeria de before/after lado-a-lado
- Aprova individualmente ou em batch
- Baseline atualizada ao merge

## J. False positives

Causas comuns:
- Font loading async (resolver com `document.fonts.ready`)
- Animation timing (disable animations no test)
- Anti-aliasing diferente entre OS (use container Docker)
- Random data (seed determinístico)
- Timestamp (mock)

Configurar tolerance:
```ts
{ maxDiffPixels: 100, threshold: 0.2 }
```

## K. Greps

```bash
# Componente sem story
find src/components -name '*.tsx' -not -name '*.stories.*' | while read f; do
  base=$(basename "$f" .tsx)
  dir=$(dirname "$f")
  [ ! -f "$dir/$base.stories.tsx" ] && echo "Sem story: $f"
done

# Snapshot test sem disable de animation
rg -n "toHaveScreenshot" --type ts -A 5 | rg -v "animations:|transition"
```

## Output em sec.html

```
┌─ Visual Regression (Módulo 11) ──────────────────────────┐
│ Plataforma                    : Chromatic + Storybook    │
│ Stories cobertas              : 142 (87% dos componentes)│
│ Browsers testados             : Chromium, Firefox, WebKit│
│ Viewports                     : mobile, tablet, desktop  │
│ Dark + light mode             : ✅                        │
│ False positive rate           : 2% ✅ (meta < 5%)        │
│ Tempo de execução CI          : 3min 12s                 │
│ Auto-baseline em main         : ✅                        │
│ Review workflow obrigatório   : ✅                        │
│ Status                        : ✅ VISUAL-LOCKED         │
└───────────────────────────────────────────────────────────┘
```

## Anti-padrões

- ❌ Snapshot sem disable de animação (flaky)
- ❌ Snapshot de página com data dinâmica (timestamp varia)
- ❌ Update baseline automático sem review (merge regressões silenciosas)
- ❌ Apenas 1 browser (Safari renderiza diferente)
- ❌ Apenas 1 viewport (mobile quebra escondido)
- ❌ Sem `--exit-zero-on-changes` em PR (build vermelho assusta sem necessidade)
- ❌ Threshold muito alto (0.5+ — não pega regressão real)
- ❌ Threshold muito baixo (0.001 — falso positivo)
- ❌ Snapshots commitados de tamanho gigante (repo incha)
- ❌ Tests rodando localmente sem container (variação de SO)
- ❌ Storybook só com `args` default (perde estados visuais)
