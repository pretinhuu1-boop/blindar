---
name: functional-e2e
category: functional
module: 11
priority: P0
description: |
  Garante que todo botão, formulário, rota, dropdown e link do projeto
  funciona ponta-a-ponta com dados REAIS (não mock). Gera Playwright specs
  auto-descobertas para cada tela. Bloqueia release se algum elemento
  interativo for "vazio".
---

# Agent: functional-e2e

## Missão

Cada elemento interativo da UI faz algo real, observável e persistente.
Cada rota retorna conteúdo. Cada API retorna 2xx pra payload válido.
Nada é decorativo sem propósito.

## Quando rodar

- Módulo 11 selecionado
- Antes de Fase 6 (Production checklist) — sempre
- Após cada PR que toca UI ou rota

## Descoberta automática (greps)

### Frontend
```bash
# Rotas
rg -n "(<Route|<Link to|router\.push|navigate\(|href=)" --type tsx --type jsx
rg -n "createBrowserRouter|defineRoutes" --type ts

# Botões / forms
rg -n "<button|<form|<Button|<Form|<input.*type=.submit" --type tsx --type jsx

# Handlers
rg -n "(onClick|onSubmit|onChange|onBlur|onKeyDown)" --type tsx --type jsx
```

### Backend
```bash
# Endpoints
rg -n "(app\.(get|post|put|patch|delete)|router\.(get|post|put|patch|delete))" --type ts --type js
rg -n "@(Get|Post|Put|Patch|Delete)\(" --type ts  # NestJS / decorators
rg -n "func\s+\w+.*http\.ResponseWriter" --type go
```

## Geração automática de Playwright spec

Para cada rota descoberta, gerar um `.spec.ts` que:

1. **Navega** até a rota (com auth se necessário)
2. **Detecta** todos os elementos interativos visíveis
3. **Clica** em cada botão (não-destrutivo) e verifica:
   - Status code da request gerada (200-299 ou 3xx esperado)
   - Mudança visual (toast, modal, navegação, atualização DOM)
   - Ausência de erro no console
4. **Preenche** cada formulário com dados válidos e dispara submit
5. **Verifica persistência** (query no banco ou GET subsequente retorna dado)
6. **Verifica responsividade**: roda em 3 viewports (mobile 375x667, tablet 768x1024, desktop 1440x900)

Template do spec:

```ts
// auto-gerado por blindar/agents/functional-e2e
import { test, expect } from '@playwright/test';

const VIEWPORTS = [
  { name: 'mobile',  width: 375,  height: 667 },
  { name: 'tablet',  width: 768,  height: 1024 },
  { name: 'desktop', width: 1440, height: 900 },
];

test.describe('Funcional E2E — /dashboard', () => {
  for (const vp of VIEWPORTS) {
    test(`viewport=${vp.name}: todos elementos interativos respondem`, async ({ page }) => {
      await page.setViewportSize(vp);
      await page.goto('/dashboard');

      // capturar erros do console
      const consoleErrors: string[] = [];
      page.on('console', m => m.type() === 'error' && consoleErrors.push(m.text()));

      // 1. todos botões visíveis devem ter handler ou href
      const buttons = await page.locator('button:visible, a:visible').all();
      expect(buttons.length, 'página deve ter elementos interativos').toBeGreaterThan(0);

      for (const btn of buttons) {
        const text = await btn.textContent();
        if (!text?.trim()) continue;       // ignora ícones decorativos
        if (await btn.isDisabled()) continue;

        // captura request gerada pelo clique
        const reqPromise = page.waitForRequest(r => true, { timeout: 1500 }).catch(() => null);
        await btn.click({ trial: false, force: false }).catch(() => null);
        await page.waitForTimeout(300);

        // pelo menos UMA das condições deve ser verdadeira:
        const navigated = page.url() !== '/dashboard';
        const req = await reqPromise;
        const toastVisible = await page.locator('[role="status"], [data-toast]').isVisible().catch(() => false);
        const modalVisible = await page.locator('[role="dialog"]').isVisible().catch(() => false);

        const didSomething = navigated || !!req || toastVisible || modalVisible;
        expect(didSomething, `botão "${text.trim()}" deve fazer algo`).toBe(true);

        // volta pra rota base
        if (navigated) await page.goto('/dashboard');
      }

      // 2. zero erro no console
      expect(consoleErrors).toEqual([]);
    });
  }
});
```

## Checklist por tela

Para cada tela do projeto, validar:

- [ ] Rota carrega com 200 (sem 500/erro JS)
- [ ] Título da página (`<title>`) é único e descritivo
- [ ] Botão primário visível "above the fold" (mobile + desktop)
- [ ] Cada botão visível tem handler real (NÃO `onClick={()=>{}}`)
- [ ] Cada `<form>` submete pra endpoint real e retorna feedback
- [ ] Cada input tem `<label>` associado (a11y) — ver módulo 10
- [ ] Empty states têm ícone + texto + ação sugerida
- [ ] Loading states usam skeleton (não spinner genérico)
- [ ] Erros mostram mensagem amigável + sugestão
- [ ] Confirmação modal antes de ações destrutivas
- [ ] Logout sempre visível ao usuário autenticado
- [ ] Voltar / breadcrumb em telas profundas

## Backend — endpoints reais

Para cada endpoint descoberto, gerar `tests/api/<endpoint>.test.ts`:

```ts
test('POST /api/v1/users — happy path', async () => {
  const res = await fetch(`${BASE}/api/v1/users`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${TOKEN}` },
    body: JSON.stringify({ name: 'Real Name', email: `user-${Date.now()}@blindar.test` }),
  });
  expect(res.status).toBe(201);
  const body = await res.json();
  expect(body.data.id).toBeTruthy();          // UUID real, não "mock-id"
  expect(body.data.id).not.toMatch(/^(mock|test|fake|dummy)/);
});

test('POST /api/v1/users — input inválido retorna 422', async () => {
  const res = await fetch(`${BASE}/api/v1/users`, {
    method: 'POST',
    body: JSON.stringify({ name: '', email: 'not-an-email' }),
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${TOKEN}` },
  });
  expect(res.status).toBe(422);
});
```

## Output esperado

Atualizar `sec.html`:

```
┌─ Funcional E2E (Módulo 11) ──────────────────────────────┐
│ Rotas descobertas            : 23                          │
│ Specs gerados                : 23 (mobile/tablet/desktop)  │
│ Botões testados              : 187                         │
│ Botões sem ação              : 0   ✅                      │
│ Forms testados               : 31                          │
│ Forms sem persistência       : 0   ✅                      │
│ Endpoints API testados       : 54                          │
│ Endpoints retornando mock    : 0   ✅                      │
│ Status                       : ✅ GREEN                    │
└───────────────────────────────────────────────────────────┘
```

## Bloqueia merge se

- Qualquer rota retorna 5xx
- Qualquer botão visível não dispara nada (request/navegação/toast/modal)
- Qualquer form não persiste no banco
- Qualquer endpoint retorna dado com ID que comece com `mock`, `test`, `fake`, `dummy`
- Spec falha em qualquer viewport

## Anti-padrões

- ❌ Marcar spec como `.skip` pra passar CI
- ❌ Botão que mostra `alert('em breve!')` — feature incompleta NÃO sobe
- ❌ Form que mostra "salvo!" sem ter realmente salvado
- ❌ Endpoint que retorna 200 com `{ todo: 'implementar' }`
