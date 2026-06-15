---
name: blindar
description: |
  Audita, blinda, otimiza e prepara o projeto para produção. Pipeline:
  launcher interativo (4 perguntas + menu de 15 módulos) → baseline →
  discovery → bootstrap sec.html → rounds pequenos (1 PR cada) →
  adversarial review → production checklist → relatório. Mantém sec.html
  como dashboard vivo. Termina quando: 0 crit + ≤2 high após adversarial.
  Modos: AUTO (sem pausar), SUPERVISIONADO (pausa por módulo), ESCOLHIDOS
  (só módulos selecionados). Cobre segurança, escalabilidade, fluidez,
  LGPD, a11y, responsividade e elimina mocks/console.log/TODOs.

triggers:
  - "blindar"
  - "blinda este projeto"
  - "deixa pronto pra produção"
  - "production ready"
  - "harden this project"
---

# blindar — orquestrador

## Princípio fundador: SECURITY-FIRST

**Segurança é a fundação.** Toda decisão (back, front, banco, infra, CI)
passa pelo crivo de segurança antes de ser considerada "completa".

Aplicação prática:
- **Round picking**: em empate de severidade, categoria de segurança vence
  performance/scalability/UX/etc.
- **Quality gate**: PR não-security só mergeia se NÃO degradar nenhuma
  defesa existente (grep estático cobre isso).
- **Discovery sempre roda lens de segurança primeiro.**
- **Adversarial review** (Fase 5) tem lens `security` obrigatório, mesmo
  que outras lenses sejam opcionais.
- **Frontend / backend / DB**: cada camada tem seu agente de segurança
  ativável — não é "1 agente cobre tudo".

## Princípio: SEMPRE MULTI-AGENTE

Mesmo em AI single-threaded (ChatGPT, Gemini, etc.), o pipeline é
**simulado multi-agente por turnos sequenciais isolados** —
nunca um prompt monolítico. Ver [`MULTI-AI.md`](MULTI-AI.md).

Em Claude Code: paralelo real via Workflow API.
Em outras AIs: role-play sequencial, contexto isolado por turno.

## Comportamento

Invocado → roda **launcher curto** (4 perguntas + menu) → depois executa o
que foi escolhido conforme o modo:

- **AUTO** → vai do início ao fim sem pedir confirmação (default sugerido)
- **SUPERVISIONADO** → pausa entre módulos pra revisar
- **ESCOLHIDOS** → roda só os módulos numerados que o operador selecionou

Após o launcher, não há mais perguntas (a não ser em modo supervisionado).
Operador acompanha em tempo real abrindo `sec.html` no browser.

### Launcher (Fase 00)

Ver [`pipeline/00-launcher.md`](pipeline/00-launcher.md). Faz 4 perguntas
objetivas:

1. **Tipo de projeto** (SaaS / MVP / LP / E-com / API / Mobile / CLI)
2. **Sensibilidade de dados** (Alta / Média / Baixa — define peso do módulo LGPD)
3. **Modo de execução** (Auto / Supervisionado / Escolhidos)
4. **Rigor** (Produção / Compliance / MVP)

E exibe o menu numerado de **15 módulos** (próxima seção). Aceita "tudo",
"defaults", "1,3,5,7", "1-8", "tudo menos 13,14".

Grava `.blindar/config.yml` com as escolhas. Pula automaticamente em
`--resume` ou `--headless` (CI/cron).

## Menu de módulos (15 numerados)

| # | Módulo | Quando default ON | Agentes |
|---|---|---|---|
| 1 | Baseline & Discovery | sempre | [`strategic-scanner`](agents/strategic-scanner.md) |
| 2 | Segurança aplicacional core + AI/LLM + Tenant isolation + File uploads + MLOps | sempre | [`access-control`](agents/access-control.md), [`cryptography`](agents/cryptography.md), [`business-logic`](agents/business-logic.md), [`runtime-secrets`](agents/runtime-secrets.md), [`security`](agents/security.md), [`auth-premium`](agents/auth-premium.md), [`ai-llm-safety`](agents/ai-llm-safety.md), [`tenant-isolation-tests`](agents/tenant-isolation-tests.md), [`file-uploads`](agents/file-uploads.md), [`mlops`](agents/mlops.md) |
| 3 | Frontend hardening (CSP/XSS/SRI/Trusted Types) | se UI detectada | [`frontend`](agents/frontend.md) |
| 4 | Rede & API + Payments + Realtime + API Gateway + GraphQL + gRPC | tipo ∈ SaaS/E-com/API | [`network-security`](agents/network-security.md), [`api-design`](agents/api-design.md), [`payments`](agents/payments.md), [`realtime`](agents/realtime.md), [`api-gateway`](agents/api-gateway.md), [`graphql`](agents/graphql.md), [`grpc-internal`](agents/grpc-internal.md) |
| 5 | Supply chain & patch + SBOM/SLSA (compliance 2026) | sempre | [`supply-chain`](agents/supply-chain.md), [`patch-management`](agents/patch-management.md), [`sbom-slsa`](agents/sbom-slsa.md) |
| 6 | Observabilidade & audit + Cost monitoring | tipo ∈ SaaS/E-com/API | [`observability`](agents/observability.md), [`cost-observability`](agents/cost-observability.md) |
| 7 | Banco de dados + Backup & DR + Multi-region + Data Warehouse/ETL | se DB detectado | [`backup-recovery`](agents/backup-recovery.md), [`db-architect`](agents/db-architect.md), [`multi-region`](agents/multi-region.md), [`data-warehouse-etl`](agents/data-warehouse-etl.md) |
| 8 | Compliance: LGPD + GDPR + HIPAA + PCI-DSS + frameworks | sensibilidade ≠ Baixa OU compliance | [`compliance-lgpd-br`](agents/compliance-lgpd-br.md), [`compliance`](agents/compliance.md), [`compliance-gdpr`](agents/compliance-gdpr.md), [`compliance-hipaa`](agents/compliance-hipaa.md), [`compliance-pci-deep`](agents/compliance-pci-deep.md) |
| 9 | Performance backend + Query + CDN strategy | tipo ∈ SaaS/E-com/API | [`performance`](agents/performance.md), [`db-architect`](agents/db-architect.md), [`cdn-strategy`](agents/cdn-strategy.md) |
| 10 | Fluidez completa + SEO + Frontend gen + Search + Push + Mobile native + Analytics + Audio + Video | se UI detectada | [`frontend-performance`](agents/frontend-performance.md), [`responsive-a11y`](agents/responsive-a11y.md), [`pwa-installable`](agents/pwa-installable.md), [`i18n-tz`](agents/i18n-tz.md), [`state-cache-data`](agents/state-cache-data.md), [`onboarding-ux`](agents/onboarding-ux.md), [`seo-marketing-meta`](agents/seo-marketing-meta.md), [`frontend-generator`](agents/frontend-generator.md), [`search-quality`](agents/search-quality.md), [`push-notifications`](agents/push-notifications.md), [`mobile-native`](agents/mobile-native.md), [`embedded-analytics`](agents/embedded-analytics.md), [`audio-voice`](agents/audio-voice.md), [`video-streaming`](agents/video-streaming.md) |
| 11 | Funcional E2E + Testing strategy + Visual regression | sempre | [`functional-e2e`](agents/functional-e2e.md), [`testing-strategy`](agents/testing-strategy.md), [`visual-regression`](agents/visual-regression.md) |
| 12 | Anti-mock + Externalização + Content quality (gramática/tom/glossário) | sempre | [`mock-killer`](agents/mock-killer.md), [`config-externalization`](agents/config-externalization.md), [`content-quality`](agents/content-quality.md) |
| 13 | Resiliência + escalabilidade + Process + Scheduled jobs + Chaos + Event-driven | rigor ≠ MVP | [`resilience`](agents/resilience.md), [`scalability`](agents/scalability.md), [`process-resilience`](agents/process-resilience.md), [`scheduled-jobs`](agents/scheduled-jobs.md), [`chaos-engineering`](agents/chaos-engineering.md), [`event-driven`](agents/event-driven.md) |
| 14 | DX + Flags + Backoffice + Email + Docs + Reports + Architect + Delivery + Project bootstrap | sempre | [`devops`](agents/devops.md), [`feature-flags`](agents/feature-flags.md), [`backoffice-admin`](agents/backoffice-admin.md), [`email-deliverability`](agents/email-deliverability.md), [`documentation-live`](agents/documentation-live.md), [`execution-report`](agents/execution-report.md), [`architect`](agents/architect.md), [`delivery-bundle`](agents/delivery-bundle.md), [`project-bootstrap`](agents/project-bootstrap.md) |
| 15 | Pentest + adversarial review | sempre | [`pentest`](agents/pentest.md), [`adversarial-reviewer`](agents/adversarial-reviewer.md) |

> **Total**: 72 agentes em v0.21. Fonte da verdade: [`pipeline/MODULE-MAP.json`](pipeline/MODULE-MAP.json).

**Módulos não-negociáveis** (sempre rodam, mesmo em "MVP"): **1, 2, 11, 12, 15**.

## Modos de execução

| Modo | Comportamento | Quando usar |
|---|---|---|
| `auto` | Roda módulos selecionados do início ao fim, sem pausar. Default. | Operador confia, projeto familiar |
| `supervised` | Pausa após cada módulo, pede "seguir? (s/n)" | Primeira vez no projeto, ou módulo crítico |
| `chosen` | Roda só os módulos em `selected_modules`, em ordem numérica, termina | A-la-carte (ex: só LGPD, ou só pentest) |

Em `auto`, ainda assim **bloqueia** se gate fatal (CI vermelha, suite quebrada,
crit não-confirmado) — não bypassa qualidade.

## Smart loop

- Termination padrão: **0 crit + ≤2 high após adversarial**
- **Auto-skip**: se um módulo não tem ATKs aplicáveis (ex: módulo 8 LGPD num
  CLI), pula com 1 round vazio em vez de loopar
- **Budget opcional** (`max_budget_usd` no config): para quando ultrapassa
- **Resume**: estado em `.blindar/state.json` permite retomar de onde parou

## Defaults (não negocia)

| Parâmetro | Valor |
|---|---|
| Branch | `main` (pula se não existir) |
| Round size | ≤ 80 LOC, 1 PR, squash merge |
| Adversarial cadência | a cada 10 rounds |
| Budget | sem cap (roda até termination) |
| Autonomia | total (não pergunta) |
| Risk acceptance | `.accept-risk.md` na raiz (cria se não existir) |
| sec.html location | raiz do projeto |
| Test required | sim, sempre — assertion real + grep estático |
| Round priority | security wins ties |

## 10 princípios não-negociáveis

1. **Security-first em ties** — ver acima
2. Round pequeno + mergível (1 vetor, ≤ 80 LOC, ≤ 1h)
3. `sec.html` é o ledger vivo — atualizado a cada round
4. Defesa em código + guard estático grep — ambos sempre
5. N/A vira teste de regressão (detecta adição futura)
6. Multi-agent adversarial a cada 10 rounds (4 lenses + verify)
7. CI verde antes de merge, sempre
8. Suite cresce, nunca diminui
9. Runbook em `docs/` para defesa procedural
10. Reservation pattern > check-then-act
11. Cache health checks com TTL
12. Nenhum agente novo sem bug real observado em produção

## Pipeline (sequencial, com launcher na frente)

| Fase | Arquivo | Duração |
|---|---|---|
| **00 — Launcher** ⭐ v0.8 | [`pipeline/00-launcher.md`](pipeline/00-launcher.md) | 30s–2min |
| 0 — Strategic Scan & Planning | [`pipeline/00-strategic-scan.md`](pipeline/00-strategic-scan.md) | ~3 min |
| 1 — Baseline | [`pipeline/01-baseline.md`](pipeline/01-baseline.md) | ~2 min |
| 2 — Discovery | [`pipeline/02-discovery.md`](pipeline/02-discovery.md) | ~3 min |
| 3 — Bootstrap sec.html | [`pipeline/03-bootstrap-sec-html.md`](pipeline/03-bootstrap-sec-html.md) | ~1 min |
| 4 — Loop de rounds | [`pipeline/04-rounds-loop.md`](pipeline/04-rounds-loop.md) | até termination |
| 5 — Adversarial review | [`pipeline/05-adversarial-review.md`](pipeline/05-adversarial-review.md) | ~10 min (a cada 10 rounds) |
| 6 — Production checklist | [`pipeline/06-production-checklist.md`](pipeline/06-production-checklist.md) | ~3 min |
| 7 — Relatório final | [`pipeline/07-final-report.md`](pipeline/07-final-report.md) | ~2 min |
| 8 — **Maintenance** (opt-in, trimestral) | [`pipeline/08-maintenance.md`](pipeline/08-maintenance.md) | ~5 min |
| 9 — **Drift detection** (subfase de 8) | [`pipeline/09-drift-detection.md`](pipeline/09-drift-detection.md) | ~3 min |

## Roster de agentes

Agentes de **segurança** (sempre carregados primeiro):

| Categoria | Agente |
|---|---|
| Controle de acesso (auth/MFA/RBAC) | [`agents/access-control.md`](agents/access-control.md) |
| Criptografia (TLS / at-rest / secrets) | [`agents/cryptography.md`](agents/cryptography.md) |
| Segurança aplicacional geral | [`agents/security.md`](agents/security.md) |
| **Strategic Scanner** (Fase 0) | [`agents/strategic-scanner.md`](agents/strategic-scanner.md) |
| Lógica de negócio (ASVS V11) | [`agents/business-logic.md`](agents/business-logic.md) |
| Secrets em runtime (memória/env/log) | [`agents/runtime-secrets.md`](agents/runtime-secrets.md) |
| Frontend / CSP / XSS | [`agents/frontend.md`](agents/frontend.md) |
| Rede em código (WAF/rate-limit/IaC) | [`agents/network-security.md`](agents/network-security.md) |
| Observabilidade / audit / logs | [`agents/observability.md`](agents/observability.md) |
| Backup / DR / recuperação | [`agents/backup-recovery.md`](agents/backup-recovery.md) |
| Patch management (OS/runtime/deps) | [`agents/patch-management.md`](agents/patch-management.md) |
| Supply chain / lockfiles / CI | [`agents/supply-chain.md`](agents/supply-chain.md) |
| Pentest automatizado (SAST/DAST/SCA) | [`agents/pentest.md`](agents/pentest.md) |

Agentes de **não-segurança** (carregados sob demanda):

| Categoria | Agente |
|---|---|
| Performance (backend / gargalo medido) | [`agents/performance.md`](agents/performance.md) |
| Fluidez frontend (Web Vitals / CWV) | [`agents/frontend-performance.md`](agents/frontend-performance.md) |
| **Responsivo + a11y (mobile-first/WCAG AA)** ⭐ v0.8 | [`agents/responsive-a11y.md`](agents/responsive-a11y.md) |
| **Funcional E2E (cada botão funciona)** ⭐ v0.8 | [`agents/functional-e2e.md`](agents/functional-e2e.md) |
| **Anti-mock & cleanup** ⭐ v0.8 | [`agents/mock-killer.md`](agents/mock-killer.md) |
| Resiliência (threads/breakers/pools) | [`agents/resilience.md`](agents/resilience.md) |
| Escalabilidade (10x carga) | [`agents/scalability.md`](agents/scalability.md) |
| Compliance genérico | [`agents/compliance.md`](agents/compliance.md) |
| LGPD / ANPD (Brasil) | [`agents/compliance-lgpd-br.md`](agents/compliance-lgpd-br.md) |
| DevOps / CI/CD / boot scripts | [`agents/devops.md`](agents/devops.md) |
| Adversarial review (Fase 5) | [`agents/adversarial-reviewer.md`](agents/adversarial-reviewer.md) |

## Frameworks de referência

Mapeamento de controles, **não agentes**:

| Framework | Quando usar |
|---|---|
| [`frameworks/iso-27001.md`](frameworks/iso-27001.md) | Certificação corporativa, mais aceito globalmente |
| [`frameworks/nist-csf.md`](frameworks/nist-csf.md) | Operacional/estratégico + família SP 800 |
| [`frameworks/cis-controls.md`](frameworks/cis-controls.md) | Mais acionável; bom pra começar |
| [`frameworks/owasp-asvs.md`](frameworks/owasp-asvs.md) | **Régua de verificação por requisito** — L1/L2/L3 |
| [`frameworks/pci-dss.md`](frameworks/pci-dss.md) | Condicional — só processadores de cartão |
| [`frameworks/soc2.md`](frameworks/soc2.md) | SaaS / cloud / B2B |
| [`frameworks/cobit.md`](frameworks/cobit.md) | ⚠ stub — governança corporativa (pouco em código) |

Metodologias de pentest (PTES, OWASP WSTG, NIST SP 800-115, OSSTMM, CREST)
estão referenciadas em [`agents/pentest.md`](agents/pentest.md), não em
arquivos separados — todas tratam de **como testar**, não **o que
implementar**.

Discovery (Fase 2) detecta se projeto declara um framework alvo
(`.compliance-target`, `README`, `package.json`) e gera coverage report
no relatório final (Fase 6).

## Intelligence System (⭐ v0.20)

Registry compartilhado de exceções/whitelist que TODOS os agentes
consultam pra evitar falso positivo. Vive em
`.blindar/intelligence.yml` no projeto-alvo.

Schema formal: [`schemas/intelligence.schema.json`](schemas/intelligence.schema.json).

Por que existe: cada projeto tem casos legítimos onde uma "regra" não
aplica (ex: tabela `feature_flags` legitimamente não tem `tenant_id`).
Sem este registry, agentes geram ruído contínuo.

Cada agente declara sua seção. Exemplos:

```yaml
schema: blindar/intelligence@v1
mock-killer:
  ignore_paths: ["**/*.gen.ts", "**/__mocks__/**"]
db-architect:
  global_tables: [feature_flags, system_logs, migrations]
content-quality:
  protected_terms: ["Stripe", "WhatsApp", "MASTER"]
architect:
  router_mode: { auto_detect: true }
```

### Inline markers no código

Sem precisar editar YAML:

```ts
// @blindar:keep -- log intencional pra debug
console.warn('Falha de DB');

// @blindar:hardcode-ok -- código HTTP padrão
if (res.status === 429) backoff();
```

```sql
-- @blindar:global -- tabela legitimamente sem tenant_id
CREATE TABLE feature_flags ( ... );
```

### Learning mode

Quando ativado em `intelligence.yml`:

```yaml
global:
  learning_mode: true
```

Operador aprova override 1x interativamente → blindar grava em
`intelligence.yml` automaticamente. Próximas execuções respeitam sem
perguntar de novo.

## Templates

- [`templates/sec.html`](templates/sec.html) — dashboard single-file
- [`templates/execution-report.html`](templates/execution-report.html) — relatório técnico cumulativo
- [`templates/client-report.html`](templates/client-report.html) — relatório do cliente
- [`templates/frontend-preview.html`](templates/frontend-preview.html) ⭐ v0.20 — preview/aprovação de frontend
- [`templates/accept-risk.md`](templates/accept-risk.md) — riscos aceitos
- [`templates/role-hierarchy.md`](templates/role-hierarchy.md) — template de roles
- [`templates/pr-message.md`](templates/pr-message.md) — formato de PR

## Runbooks (fora de código, para projetos-alvo)

- [`runbooks/antimalware.md`](runbooks/antimalware.md) — EDR/AV (infra)
- [`runbooks/network-segmentation.md`](runbooks/network-segmentation.md) — físico
- [`runbooks/security-awareness.md`](runbooks/security-awareness.md) — treinamento
- [`runbooks/pentest-schedule.md`](runbooks/pentest-schedule.md) — pentest humano

Esses arquivos cobrem o que ISO 27001 / NIST CSF exigem mas que **não cabe
em PR**: antivírus em laptop, treinamento de RH, pentest manual humano.

## Adaptação por stack

[`stacks.md`](stacks.md) — categorias extras por stack (Python/Node/Go/Rust/SPA/Mobile).

## Tendências 2026 (curadoria semestral)

[`docs/trends-2026.md`](docs/trends-2026.md) — React Compiler v1, RSC default,
Edge runtime, performance budget 400KB, headers HTTP, supply chain SHA-pin,
ANPD 2026 (crianças/IA/scraping/SCC/breach 3d). Agentes relevantes consultam
ao rodar.

## Quality gates (sem exceção)

| Gate | Verificação | Bloqueia |
|---|---|---|
| Suite | pytest/vitest/etc verdes após cada round | merge |
| CI | todos jobs verde | merge |
| sec.html | commit junto com código do round | commit |
| Test real | ≥ 3 assertions cobrindo happy + edge + attack | round |
| Guard estático | grep que falha se defesa regredir | round |
| Hash chain | audit nunca reescrito | sempre |
| Branch | 1 PR/round, squash, branch deletada | sempre |
| **Security-first** | PR não-security não pode degradar defesa existente | merge |

## Termination

Para quando todas as condições são verdadeiras:

- [ ] 0 confirmed crit no último adversarial
- [ ] ≤ 2 confirmed high (em `.accept-risk.md`)
- [ ] Categorias críticas ≥ 80% covered+partial
- [ ] 3 runbooks gerados em `docs/`: incident-response, key-rotation, supply-chain
- [ ] CI verde por 3 PRs consecutivos
- [ ] Production checklist Fase 6 ✓
- [ ] Coverage report do framework alvo (se declarado) gerado

## Quando NÃO rodar

- Suite atual já vermelha → reporta e para
- Sem CI configurado → para e adiciona CI mínima primeiro
- Repo sujo (git status com mudanças) → reporta e para
- Sem permissão de merge → reporta e para

Em todos: 1 reporte claro do que falta, sem tentar adivinhar.

## Anti-padrões (NUNCA)

- PR > 200 LOC ou > 5 arquivos → quebra em 2 rounds
- Implementação sem teste
- `sec.html` sem código mergeado
- Refactor durante hardening (PR próprio)
- Defesa nova quebrando teste antigo (refletir, ajustar contrato, não silenciar)
- CI vermelha mergeada
- Schema `sec.html` mudando entre rounds (schema é commitado uma vez)
- **Categoria não-security vencendo de security em empate** (security-first)

## Auto-update

Primeira fase (Baseline) roda `scripts/check-update.ps1 -Quiet` em background.
TTL de 24h, não bloqueia, avisa uma vez se versão nova existir.

Desativar: `BLINDAR_SKIP_UPDATE_CHECK=1`.
Forçar agora: `scripts/check-update.ps1 -Force`.

## Versão deste skill

Ver [`VERSION`](VERSION) e [`CHANGELOG.md`](CHANGELOG.md).

## Para humanos

- [`README.md`](README.md) — apresentação, instalação, uso
- [`USAGE.md`](USAGE.md) — guia completo passo-a-passo
- [`CHECKLIST.md`](CHECKLIST.md) — validação pós-download
- [`MULTI-AI.md`](MULTI-AI.md) — como rodar em qualquer AI
- [`ROADMAP.md`](ROADMAP.md) — o que ainda não está pronto, honestamente

## Para AIs (você que está lendo isso)

- [`AI-ENTRYPOINT.md`](AI-ENTRYPOINT.md) — **leia primeiro**, decision tree
- [`CONTRACT.md`](CONTRACT.md) — estrutura `.blindar/` no projeto-alvo
- [`schemas/`](schemas/) — JSON schemas pra output validável
- Estado no projeto-alvo: `.blindar/state.json` (ver CONTRACT.md)

## Origem

Skill extraído de execução real: 118 rounds, 68 ATKs fechados, 24 findings
adversariais fixados. Regras refletem bugs reais que já aconteceram.

Se parece dogmático demais, é porque foi pago em PR-vermelho-mergeado.
