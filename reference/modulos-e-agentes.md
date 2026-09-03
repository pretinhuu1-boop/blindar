# Catálogo: módulos, agentes e hierarquia

> Referência do `blindar`, extraída do `SKILL.md` para não ocupar o
> caminho quente. Carregue quando a etapa exigir.

## Menu de módulos (19 numerados)


| # | Módulo | Quando default ON | Agentes |
|---|---|---|---|
| 1 | Baseline & Discovery | sempre | [`strategic-scanner`](../agents/strategic-scanner.md) |
| 2 | Segurança aplicacional core + AI/LLM + Tenant isolation + File uploads + MLOps | sempre | [`access-control`](../agents/access-control.md), [`cryptography`](../agents/cryptography.md), [`business-logic`](../agents/business-logic.md), [`runtime-secrets`](../agents/runtime-secrets.md), [`security`](../agents/security.md), [`auth-premium`](../agents/auth-premium.md), [`ai-llm-safety`](../agents/ai-llm-safety.md), [`tenant-isolation-tests`](../agents/tenant-isolation-tests.md), [`file-uploads`](../agents/file-uploads.md), [`mlops`](../agents/mlops.md) |
| 3 | Frontend hardening (CSP/XSS/SRI/Trusted Types) | se UI detectada | [`frontend`](../agents/frontend.md) |
| 4 | Rede & API + Payments + Realtime + API Gateway + GraphQL + gRPC | tipo ∈ SaaS/E-com/API | [`network-security`](../agents/network-security.md), [`api-design`](../agents/api-design.md), [`payments`](../agents/payments.md), [`realtime`](../agents/realtime.md), [`api-gateway`](../agents/api-gateway.md), [`graphql`](../agents/graphql.md), [`grpc-internal`](../agents/grpc-internal.md) |
| 5 | Supply chain & patch + SBOM/SLSA (compliance 2026) | sempre | [`supply-chain`](../agents/supply-chain.md), [`patch-management`](../agents/patch-management.md), [`sbom-slsa`](../agents/sbom-slsa.md) |
| 6 | Observabilidade & audit + Log lifecycle/retenção + Cost monitoring | tipo ∈ SaaS/E-com/API | [`observability`](../agents/observability.md), [`log-ops-retention`](../agents/log-ops-retention.md), [`cost-observability`](../agents/cost-observability.md) |
| 7 | Banco de dados + Backup & DR + **Migração de engine** + **Paridade de ambientes** + Multi-region + Data Warehouse/ETL | se DB detectado | [`backup-recovery`](../agents/backup-recovery.md), [`db-architect`](../agents/db-architect.md), [`db-migration-guardian`](../agents/db-migration-guardian.md) ⭐, [`environment-parity`](../agents/environment-parity.md) ⭐, [`multi-region`](../agents/multi-region.md), [`data-warehouse-etl`](../agents/data-warehouse-etl.md) |
| 8 | Compliance: LGPD + GDPR + HIPAA + PCI-DSS + frameworks | sensibilidade ≠ Baixa OU compliance | [`compliance-lgpd-br`](../agents/compliance-lgpd-br.md), [`compliance`](../agents/compliance.md), [`compliance-gdpr`](../agents/compliance-gdpr.md), [`compliance-hipaa`](../agents/compliance-hipaa.md), [`compliance-pci-deep`](../agents/compliance-pci-deep.md) |
| 9 | Performance backend + Query + CDN strategy | tipo ∈ SaaS/E-com/API | [`performance`](../agents/performance.md), [`db-architect`](../agents/db-architect.md), [`cdn-strategy`](../agents/cdn-strategy.md) |
| 10 | Fluidez completa + SEO + Frontend gen + Search + Push + Mobile native + Analytics + Audio + Video | se UI detectada | [`frontend-performance`](../agents/frontend-performance.md), [`responsive-a11y`](../agents/responsive-a11y.md), [`pwa-installable`](../agents/pwa-installable.md), [`i18n-tz`](../agents/i18n-tz.md), [`state-cache-data`](../agents/state-cache-data.md), [`onboarding-ux`](../agents/onboarding-ux.md), [`seo-marketing-meta`](../agents/seo-marketing-meta.md), [`frontend-generator`](../agents/frontend-generator.md), [`search-quality`](../agents/search-quality.md), [`push-notifications`](../agents/push-notifications.md), [`mobile-native`](../agents/mobile-native.md), [`embedded-analytics`](../agents/embedded-analytics.md), [`audio-voice`](../agents/audio-voice.md), [`video-streaming`](../agents/video-streaming.md) |
| 11 | Funcional E2E + Testing strategy + Visual regression | sempre | [`functional-e2e`](../agents/functional-e2e.md), [`testing-strategy`](../agents/testing-strategy.md), [`visual-regression`](../agents/visual-regression.md) |
| 12 | Anti-mock + Externalização + Content quality (gramática/tom/glossário) | sempre | [`mock-killer`](../agents/mock-killer.md), [`config-externalization`](../agents/config-externalization.md), [`content-quality`](../agents/content-quality.md) |
| 13 | Resiliência + escalabilidade + Process + Scheduled jobs + Chaos + Event-driven | rigor ≠ MVP | [`resilience`](../agents/resilience.md), [`scalability`](../agents/scalability.md), [`process-resilience`](../agents/process-resilience.md), [`scheduled-jobs`](../agents/scheduled-jobs.md), [`chaos-engineering`](../agents/chaos-engineering.md), [`event-driven`](../agents/event-driven.md) |
| 14 | DX + Flags + Backoffice + Email + Docs + Reports + Architect + Delivery + Project bootstrap + **Governança de mudança** | sempre | [`devops`](../agents/devops.md), [`feature-flags`](../agents/feature-flags.md), [`backoffice-admin`](../agents/backoffice-admin.md), [`email-deliverability`](../agents/email-deliverability.md), [`documentation-live`](../agents/documentation-live.md), [`execution-report`](../agents/execution-report.md), [`architect`](../agents/architect.md), [`delivery-bundle`](../agents/delivery-bundle.md), [`project-bootstrap`](../agents/project-bootstrap.md), [`risk-engine`](../agents/risk-engine.md) ⭐, [`change-impact`](../agents/change-impact.md) ⭐, [`decision-log`](../agents/decision-log.md) ⭐ |
| 15 | Pentest + adversarial review + **Runtime adversarial** | sempre | [`pentest`](../agents/pentest.md), [`adversarial-reviewer`](../agents/adversarial-reviewer.md), [`runtime-adversarial`](../agents/runtime-adversarial.md) ⭐ |
| 16 | Product Evolution (opt-in, escopo separado — requer `ANTHROPIC_API_KEY`) | só se pedido | [`api-frontend-coverage`](../agents/api-frontend-coverage.md), [`user-journey-simulator`](../agents/user-journey-simulator.md), [`feature-gap-analyzer`](../agents/feature-gap-analyzer.md), [`growth-opportunities`](../agents/growth-opportunities.md), [`product-critic`](../agents/product-critic.md) |
| 17 | Ataque — recon passivo externo (requer URL alvo) | se URL fornecida | [`attack-recon`](../agents/attack-recon.md) |
| 18 | Smoke / Runtime Truth + checks de infra (prova que a app SOBE) | sempre (self-skip sem docker/URL) | [`smoke-runtime`](../agents/smoke-runtime.md) + 9 checks de infra/runtime |
| 19 | Pentest ATIVO — payloads reais (requer `.blindar/.accept-authorization`) | só com autorização | [`pentest-active`](../agents/pentest-active.md) |

> **Total**: 170 agentes em 19 módulos (130 checks determinísticos + 14 API-wrapped = 144 `check-*.sh`, + playbooks).
> Contagem verificada por `ls agents/*.md`, `ls templates/checks/check-*.sh` e
> `pipeline/MODULE-MAP.json` em v0.80 — a v0.80 acrescentou 27 checks operacionais
> e de compliance que antes eram só playbook advisory.
> Fonte da verdade: [`pipeline/MODULE-MAP.json`](../pipeline/MODULE-MAP.json).

**Módulos não-negociáveis** (sempre rodam, mesmo em "MVP"): **1, 2, 11, 12, 15** (+ 18, que self-skipa quando não há runtime pra subir).

## Hierarquia de agentes (⭐ v0.57)


117 especialistas chapados não convergem sozinhos: cada um está certo dentro do
próprio escopo e cego fora dele. `performance` quer Redis; `security` exige
Redis com auth, TLS e rede isolada; `db-architect` argumenta que o índice que
falta resolve o mesmo problema sem introduzir serviço. Nenhum está errado — e
sem árbitro vence quem rodou por último.

Cada `agents/*.md` declara `lead:` e `authority:` no frontmatter. É **camada de
metadata**: nenhum arquivo foi movido, nenhum agente foi fundido.

| Lead | Agentes | Lead | Agentes |
|---|---|---|---|
| `security-lead` | 20 | `runtime-lead` | 8 |
| `chief-architect` | 16 | `platform-lead` | 7 |
| `frontend-lead` | 16 | `data-lead` | 7 |
| `sre-lead` | 12 | `privacy-lead` | 7 |
| `product-lead` | 10 | `ai-lead` | 6 |
| `release-lead` | 5 | `qa-lead` | 3 |

[`chief-architect`](../agents/chief-architect.md) arbitra entre os leads, por
precedência declarada: perda de dado > segurança > reversibilidade >
simplicidade operacional > o que já existe. Ele **não implementa**.

### Autoridade

| `authority` | Pode | Agentes |
|---|---|---|
| `read-only` | só analisar | 4 |
| `plan` | planejar | 6 |
| `implement` | alterar código | 92 |
| `validate` | testar | 4 |
| `adversary` | tentar quebrar | 7 |
| `gate` | **bloquear entrega, sem editar** | 4 |

`gate` é exceção por construção — se quase todo agente pode bloquear, ninguém
bloqueia de fato. Somar autoridade de decisão à de execução é como uma decisão
ruim vira fato consumado antes de ser revista.

Validado por [`tests/agents-registry.test.mjs`](../tests/agents-registry.test.mjs)
nos dois sentidos: toda entrada do `MODULE-MAP` resolve para playbook ou check,
e todo playbook é ativado por algum módulo. Metadata que ninguém valida
apodrece em silêncio — o teste nasceu achando 2 agentes sem frontmatter e 2
playbooks que nenhum módulo executava.

## Roster de agentes


Agentes de **segurança** (sempre carregados primeiro):

| Categoria | Agente |
|---|---|
| Controle de acesso (auth/MFA/RBAC) | [`agents/access-control.md`](../agents/access-control.md) |
| Criptografia (TLS / at-rest / secrets) | [`agents/cryptography.md`](../agents/cryptography.md) |
| Segurança aplicacional geral | [`agents/security.md`](../agents/security.md) |
| **Strategic Scanner** (Fase 0) | [`agents/strategic-scanner.md`](../agents/strategic-scanner.md) |
| Lógica de negócio (ASVS V11) | [`agents/business-logic.md`](../agents/business-logic.md) |
| Secrets em runtime (memória/env/log) | [`agents/runtime-secrets.md`](../agents/runtime-secrets.md) |
| Frontend / CSP / XSS | [`agents/frontend.md`](../agents/frontend.md) |
| Rede em código (WAF/rate-limit/IaC) | [`agents/network-security.md`](../agents/network-security.md) |
| Observabilidade / audit / logs (conteúdo) | [`agents/observability.md`](../agents/observability.md) |
| Log em disco: rotação / retenção / guardas (continente) | [`agents/log-ops-retention.md`](../agents/log-ops-retention.md) |
| Backup / DR / recuperação | [`agents/backup-recovery.md`](../agents/backup-recovery.md) |
| Patch management (OS/runtime/deps) | [`agents/patch-management.md`](../agents/patch-management.md) |
| Supply chain / lockfiles / CI | [`agents/supply-chain.md`](../agents/supply-chain.md) |
| Pentest automatizado (SAST/DAST/SCA) | [`agents/pentest.md`](../agents/pentest.md) |

Agentes de **não-segurança** (carregados sob demanda):

| Categoria | Agente |
|---|---|
| Performance (backend / gargalo medido) | [`agents/performance.md`](../agents/performance.md) |
| Fluidez frontend (Web Vitals / CWV) | [`agents/frontend-performance.md`](../agents/frontend-performance.md) |
| **Responsivo + a11y (mobile-first/WCAG AA)** ⭐ v0.8 | [`agents/responsive-a11y.md`](../agents/responsive-a11y.md) |
| **Funcional E2E (cada botão funciona)** ⭐ v0.8 | [`agents/functional-e2e.md`](../agents/functional-e2e.md) |
| **Anti-mock & cleanup** ⭐ v0.8 | [`agents/mock-killer.md`](../agents/mock-killer.md) |
| Resiliência (threads/breakers/pools) | [`agents/resilience.md`](../agents/resilience.md) |
| Escalabilidade (10x carga) | [`agents/scalability.md`](../agents/scalability.md) |
| Compliance genérico | [`agents/compliance.md`](../agents/compliance.md) |
| LGPD / ANPD (Brasil) | [`agents/compliance-lgpd-br.md`](../agents/compliance-lgpd-br.md) |
| DevOps / CI/CD / boot scripts | [`agents/devops.md`](../agents/devops.md) |
| Adversarial review (Fase 5) | [`agents/adversarial-reviewer.md`](../agents/adversarial-reviewer.md) |
