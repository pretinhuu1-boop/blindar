# Tendências 2026 — incorporar quando aplicável

> Curadoria semestral. Última atualização: 2026-06-14.
> Referência pra agentes do blindar quando o contexto encaixar.

## Frontend / React

### React Compiler v1 (out/2025)
- **Impacto**: compilador otimiza memoization automaticamente
- **Ação blindar**: agente `frontend-performance` deve **rejeitar PRs** que
  adicionem `useMemo`/`useCallback`/`React.memo` agressivos quando o projeto
  usa React 19+ com Compiler ativado. Manuais ainda OK quando há benchmark
  provando ganho.
- **Greps**:
  ```bash
  rg -n "useMemo|useCallback|React\.memo" --type tsx --type jsx | wc -l
  # Se > 20 em projeto com Compiler ativo, sugerir auditoria
  ```

### React Server Components (RSC) — default
- **Impacto**: Next.js 15+ trata RSC como default. Client components viram
  exceção opt-in via `'use client'`.
- **Ação blindar**: agente `frontend` deve verificar que diretiva `'use client'`
  só aparece em componentes que **realmente** precisam (state, effect,
  browser API). Server component vazando `'use client'` desnecessário é finding.

### Edge runtime
- **Impacto**: Cloudflare Workers, Vercel Edge Functions → TTFB < 50ms
- **Ação blindar**: agente `performance` deve sugerir edge runtime pra rotas
  stateless (auth check, redirect, A/B test, geo routing). Mas alertar:
  Node APIs limitadas em edge (sem `fs`, `child_process`, etc.).

### Performance budget
- **Impacto**: vira ranking factor SEO. ≤ 400KB JS gzipped é o teto.
- **Ação blindar**: agente `frontend-performance` deve **bloquear merge** se:
  - Bundle inicial > 400KB gzipped
  - LCP > 2.5s no mobile
  - INP > 200ms
- **Ferramenta**: `next/bundle-analyzer`, `vite-bundle-visualizer`,
  `webpack-bundle-analyzer`

## Segurança

### Headers HTTP de segurança ainda subutilizados (2026)
Pesquisa de mercado mostra que maioria das apps em produção falta pelo menos
1 header crítico. **Não negociar**:

```
Content-Security-Policy: default-src 'self'; ...
Strict-Transport-Security: max-age=31536000; includeSubDomains; preload
X-Frame-Options: DENY
X-Content-Type-Options: nosniff
Referrer-Policy: strict-origin-when-cross-origin
Permissions-Policy: camera=(), microphone=(), geolocation=()
Cross-Origin-Embedder-Policy: require-corp
Cross-Origin-Opener-Policy: same-origin
```

- **Ação blindar**: agente `network-security` valida todos os headers acima
  via curl em endpoint principal. Falta de qualquer um = CRIT.

### Supply chain — SHA-pin obrigatório em CI
- **Impacto**: ataques tipo GitHub Actions hijack (vide tj-actions/changed-files
  incident 2025) forçaram SHA-pinning como baseline
- **Ação blindar**: agente `supply-chain` deve **bloquear** uses de actions
  por tag (`uses: actions/checkout@v4`) — exige `uses: actions/checkout@<full-sha>`

## LGPD / ANPD (Brasil) — 2026

### Prioridades de fiscalização ANPD 2026-2027
1. **Dados de crianças e adolescentes** — Estatuto Digital + LGPD
2. **IA / biometria** — uso e enviesamento
3. **Scraping de dados** — limites e responsabilização

- **Ação blindar**: agente `compliance-lgpd-br` deve perguntar (ou inferir
  da Fase 0) se o projeto:
  - Aceita usuários menores de 18 → módulo dedicado ON
  - Usa IA pra decisão automatizada → DPIA obrigatório
  - Faz scraping → política de uso + termos

### Transferência internacional — SCC obrigatória
- **Impacto**: ANPD publicou Standard Contractual Clauses oficiais; uso
  obrigatório em todo contrato de processamento que envolve país sem
  decisão de adequação.
- **Ação blindar**: agente `compliance-lgpd-br` cria template SCC em
  `docs/legal/scc-international-transfer.md` se detectar provider fora do
  Brasil (Vercel US, AWS US, Supabase US, etc.).

### Breach notification — 3 dias úteis
- **Impacto**: prazo formalizado. Antes era "em prazo razoável".
- **Ação blindar**: agente `compliance-lgpd-br` exige runbook
  `docs/runbooks/breach-notification.md` com:
  - Detecção → classificação → notificação ANPD em ≤ 3 dias úteis
  - Notificação aos titulares afetados
  - Comunicação pública se for de impacto relevante

## AI-assisted dev (auto-aplicado pelo blindar)

### CLAUDE.md disciplina
- **Impacto**: 70% de adesão a regras em CLAUDE.md vs ~100% em hooks
  determinísticos. Pra regras críticas, **hooks > instruções**.
- **Ação blindar**: agente `devops` deve sugerir hooks pra:
  - `pre-commit`: bloquear secrets (gitleaks ou similar)
  - `pre-push`: bloquear push direto na `main`
  - `pre-tool`: bloquear `rm -rf` em pasta de produção

### Skills focadas
- Padrão 2026: skill faz **uma** coisa. Companions on-demand. blindar já é
  esse padrão ✓

## Como agentes do blindar devem consumir este arquivo

Cada agente relevante deve incluir, no topo:

```yaml
references:
  - docs/trends-2026.md#<seção>
```

E aplicar regras correspondentes. Quando o arquivo for atualizado (próxima
curadoria semestral em dez/2026), agentes consultam de novo.
