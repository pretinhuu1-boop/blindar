---
phase: 00-launcher
title: Launcher interativo — perguntas + menu de módulos
duration_estimate: 30s–2min
output: .blindar/config.yml (modo + módulos selecionados)
runs_before: 00-strategic-scan.md
---

# Fase 00 — Launcher

Este é o **ponto de entrada** do `blindar`. Roda ANTES de qualquer outra fase.
Substitui o comportamento "100% autônomo desde a primeira linha" por um
**onboarding curto e objetivo** (≤4 perguntas) que define modo de execução e
módulos a rodar.

> **Quando pular:** se `.blindar/config.yml` já existir com `mode` e
> `selected_modules` definidos (ex: retomada de execução), o launcher é
> pulado e vai direto pra Fase 0 (Strategic Scan).

---

## Passo 1 — 4 perguntas objetivas

Faça as 4 perguntas abaixo em sequência, **sem rodeios**. Aceite respostas
curtas (número, palavra). Não explique opções a menos que o usuário peça.

### Pergunta 1/4 — Tipo de projeto

```
Qual o tipo do projeto?
  1) SaaS / Produção (multi-tenant, escala)
  2) MVP / Validação
  3) Landing page / Site institucional
  4) E-commerce / Marketplace
  5) API / Microsserviço
  6) Mobile / PWA
  7) CLI / Lib / Script
  8) Outro
Responda com o número.
```

### Pergunta 2/4 — Sensibilidade de dados (LGPD)

```
Sensibilidade dos dados que o sistema processa?
  A) ALTA  — PII, financeiro, saúde, autenticação (LGPD forte + módulo 8 obrigatório)
  M) MÉDIA — login básico, perfil simples
  B) BAIXA — conteúdo público, sem dados pessoais
Responda A / M / B.
```

### Pergunta 3/4 — Modo de execução

```
Como devo rodar?
  1) AUTO          — vai do início ao fim sem pedir confirmação (recomendado)
  2) SUPERVISIONADO — pausa entre módulos pra você revisar
  3) ESCOLHIDOS     — você escolhe módulos específicos no menu seguinte
Responda 1 / 2 / 3.
```

### Pergunta 4/4 — Nível de rigor

```
Rigor?
  P) PRODUÇÃO   — todos os gates, suite + CI + adversarial
  C) COMPLIANCE — produção + framework alvo (LGPD/SOC2/PCI/ISO)
  M) MVP        — gates essenciais (segurança + funcional E2E), sem perfumaria
Responda P / C / M.
```

---

## Passo 2 — Menu de módulos

Exiba **exatamente** a tabela abaixo. Sempre mostre os 15 módulos (independente
das respostas das perguntas 1–4 — elas só ajustam defaults).

```
═══════════════════════════════════════════════════════════════════
                       BLINDAR — MENU DE MÓDULOS
═══════════════════════════════════════════════════════════════════
  #   MÓDULO                                              DEFAULT
───────────────────────────────────────────────────────────────────
  1   Baseline & Discovery (obrigatório)                  ✓ ON
  2   Segurança aplicacional core (auth, crypto, ASVS)    ✓ ON
  3   Frontend hardening (CSP/XSS/SRI/Trusted Types)      [ui-only]
  4   Rede & proxy (WAF/rate-limit/headers)               [saas/ecom/api]
  5   Supply chain & patch (lockfile/SHA-pin/Renovate)     ✓ ON
  6   Observabilidade & audit (logs estruturados)         [saas/ecom/api]
  7   Backup & DR (cifrado + restore testado)              [tem-DB]
  8   LGPD/ANPD + compliance (consent/export/deletion)     [sens=A/M]
  9   Performance backend (N+1, cache, índices)           [saas/ecom/api]
 10   Fluidez + a11y + responsivo (CWV, WCAG AA, mobile)  [ui-only]
 11   Funcional E2E (todo botão/rota/form funcionando)     ✓ ON
 12   Anti-mock & cleanup (mocks, console.log, TODOs)      ✓ ON
 13   Resiliência & escalabilidade (breakers, 10x)         [rigor≠mvp]
 14   DX & onboarding (.env.example, scripts, README)      ✓ ON
 15   Pentest + adversarial review                         ✓ ON
═══════════════════════════════════════════════════════════════════

Como você quer rodar?
  • "tudo"        → roda os 15 módulos
  • "defaults"    → roda apenas os marcados ✓ ON (recomendado por padrão)
  • "1,3,5,7,10"  → roda apenas esses
  • "1-8"         → roda do 1 ao 8 (faixa)
  • "tudo menos 13,14" → roda todos exceto os listados
```

### Resolução dos defaults

Aplique nesta ordem (cada regra sobrepõe a anterior):

1. **Sempre ON**: 1, 2, 11, 12, 15 (núcleo não-negociável)
2. **ON se tem UI** (detectado em Fase 1 — `package.json` com react/vue/svelte/next, `index.html`, etc.): 3, 10
3. **ON se tem DB** (detectado em Fase 1 — `DATABASE_URL`, prisma, drizzle, migrations/): 7
4. **ON se sensibilidade ≠ B**: 8
5. **ON se tipo ∈ {SaaS, E-com, API}**: 4, 6, 9, 13
6. **ON sempre**: 5, 14

Se o usuário respondeu **rigor = MVP**: desligue 13 e exiba aviso "rigor MVP →
módulo 13 desativado por padrão (escalabilidade não cabe em MVP)".

Se o usuário respondeu **rigor = COMPLIANCE**: ligue **todos** + pergunte qual
framework alvo (ISO27001 / NIST-CSF / CIS / ASVS-L2 / PCI-DSS / SOC2 / LGPD).

---

## Passo 3 — Confirmação final

Antes de gravar config e seguir, mostre o **resumo** e peça 1 confirmação:

```
═══════════════════════════════════════════════════════════════════
                       RESUMO DA EXECUÇÃO
═══════════════════════════════════════════════════════════════════
  Tipo de projeto    : SaaS / Produção
  Sensibilidade      : ALTA (LGPD forte)
  Modo               : AUTO (sem pausar)
  Rigor              : COMPLIANCE (alvo: LGPD)
  Módulos selecionados: 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15 (todos)
  Termination        : 0 crit + ≤2 high após adversarial
  Branch base        : main
  Dashboard          : sec.html (raiz do projeto)
═══════════════════════════════════════════════════════════════════

Confirma e segue? (s/n)  [default: s em 10s se AUTO]
```

- Se **AUTO**: aceita Enter / timeout 10s como "sim".
- Se **SUPERVISIONADO**: exige "s" explícito.
- Se **n**: volta ao menu (Passo 2).

---

## Passo 4 — Gravar `.blindar/config.yml`

Crie o arquivo (sobrescreve se existir) com este conteúdo:

```yaml
# .blindar/config.yml — gerado pelo launcher
schema: blindar/config@v0.8
mode: auto              # auto | supervised | chosen
selected_modules:       # números do menu (1..15)
  - 1
  - 2
  - 11
  - 12
  - 15
project_type: saas      # saas|mvp|landing|ecom|api|mobile|cli|other
data_sensitivity: high  # high|medium|low
rigor: compliance       # production|compliance|mvp
target_framework: lgpd  # null se rigor != compliance
ui_detected: true       # detectado em Fase 1, pode atualizar
db_detected: true
branch: main
launcher_completed_at: "<ISO timestamp>"
```

Também atualize `.blindar/state.json` com:

```json
{
  "phase": "00-launcher-done",
  "selected_modules": [1, 2, 3, ...],
  "mode": "auto",
  "rigor": "compliance"
}
```

---

## Passo 5 — Próxima fase

- Se `mode = auto`     → segue direto pra `01-baseline.md` sem mais perguntas
- Se `mode = supervised` → após cada módulo, perguntar "seguir pro próximo? (s/n)"
- Se `mode = chosen`   → roda só os módulos em `selected_modules`, na ordem
  numérica, e termina (sem entrar no loop infinito da Fase 4)

---

## Modos especiais

### `blindar --resume`
Pula launcher se `.blindar/config.yml` existir. Retoma do `state.json`.

### `blindar --reset`
Apaga `.blindar/` e roda launcher do zero.

### `blindar --dry-run`
Roda launcher normalmente mas grava `dry_run: true` no config. Simula
módulos sem commits/PRs.

### `blindar --headless`
Pula launcher e usa defaults (módulos ON por detecção, modo auto, rigor
produção). Para CI/cron.

---

## Anti-padrões deste launcher

- ❌ NÃO faça perguntas longas com explicação de cada opção (a tabela já explica)
- ❌ NÃO peça confirmação a cada pergunta — só uma confirmação final
- ❌ NÃO trave em loop se usuário responder errado — sugira a resposta válida
  mais próxima e pergunte de novo (máx 2x, depois assume default)
- ❌ NÃO grave config até confirmação final (Passo 3)
- ✅ DEFAULTS são inteligentes: na dúvida, marque ON nos críticos (1,2,11,12,15)
