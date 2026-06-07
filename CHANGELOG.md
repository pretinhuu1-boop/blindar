# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/).
Versionamento [SemVer](https://semver.org/lang/pt-BR/).

## [0.7.0] — 2026-06-07

### BREAKING — renumeração de fases

Adicionada **Fase 0: Strategic Scan & Planning** antes do Baseline.
Todas as fases existentes foram **renumeradas +1**:

| Antes (v0.6.x) | Agora (v0.7.0) |
|---|---|
| 00-baseline.md | 01-baseline.md |
| 01-discovery.md | 02-discovery.md |
| 02-bootstrap-sec-html.md | 03-bootstrap-sec-html.md |
| 03-rounds-loop.md | 04-rounds-loop.md |
| 04-adversarial-review.md | 05-adversarial-review.md |
| 05-production-checklist.md | 06-production-checklist.md |
| 06-final-report.md | 07-final-report.md |
| 07-maintenance.md | 08-maintenance.md |
| 08-drift-detection.md | 09-drift-detection.md |
| (nova) | **00-strategic-scan.md** |

**Migração**: nada a fazer no projeto-alvo. `.blindar/state.json`
mantém compatibilidade (`phase` field aceita os nomes textuais).

### Adicionou — Fase 0 Strategic Scan & Planning

- `pipeline/00-strategic-scan.md` — nova fase pré-baseline:
  - **Varredura arquitetural** (read-only) em 14 categorias:
    auth, autz, storage, secrets, frontend, API, testes, CI/CD,
    logging, deps, arquitetura, perf, resiliência, observability
  - **Findings numerados** por severidade (crit / high / med / info)
  - **Pergunta interativa** ao operador: "quais aplicar? [1-5, 10, 16-18]"
  - **Detecção de hardware** (cores, RAM)
  - **Plano de paralelismo** otimizado pra máquina atual
  - **Save** `.blindar/plan.json` + `.blindar/scan-report.md`

- `agents/strategic-scanner.md` — agente novo, **read-only**:
  - Não implementa nada, só observa e propõe
  - Detecta anti-patterns: senhas plaintext, .env commitado,
    JSON-as-DB, sem MFA, CORS *, innerHTML inseguro, etc.
  - Classifica esforço (Sm/Md/Lg/XL) e aponta agente que atacaria

- `templates/scan-report.md` — formato do relatório legível por
  humano. Findings agrupadas por severidade, com encontrado/sugerido/
  agente/esforço por finding.

- `schemas/plan.schema.json` — schema do `.blindar/plan.json` com
  hardware, findings selecionados, grupos paralelos, dependências.

### Adicionou — paralelismo inteligente

Cálculo automático na Fase 0:
- `max_parallel_agents = min(16, cpu_cores - 2)` — bate com cap da
  Workflow API
- **Grupos independentes** identificados:
  - Grupo A: access-control + crypto + observability (alta vazão)
  - Grupo B: frontend + network-security + supply-chain
  - Grupo C: resilience + business-logic (sequencial, dependências)

### Mudou — SKILL.md + AI-ENTRYPOINT.md

- Pipeline table reflete renumeração
- AI-ENTRYPOINT Passo 4: agora 8 fases (0-7) + 2 opcionais (8-9)
- Strategic Scanner adicionado ao roster de agentes

### Não mudou

- Conteúdo das fases existentes (só renomeação)
- Agentes existentes
- Schemas existentes (apenas adicionou `plan.schema.json`)
- Defaults do skill

### Filosofia

"Antes de blindar, **olhar**. Antes de olhar, **planejar**."

Sem Fase 0, blindar gastava rounds em coisas que o operador nem queria
fixar. Agora a Fase 0 produz contrato explícito sobre o que vai/não vai
ser atacado, com tempo estimado realista e plano de paralelismo
ajustado à máquina.

## [0.6.0] — 2026-06-07

Endereça 25/30 itens do brainstorm de melhorias (ver
[`ROADMAP.md`](ROADMAP.md)).

### Adicionou — 2 agentes novos (Tier 1 segurança)

- `agents/business-logic.md` (#1) — OWASP ASVS V11 completa:
  race em saldo/cupom/inventário, IDOR previsível, workflow abuse,
  input bounds (qty negativa, float-money), refund/reversal,
  account takeover via reset/email, resource exhaustion lógica.
- `agents/runtime-secrets.md` (#5) — vazamento em runtime:
  env leakage, token em URL, heap/memory dump, process listing,
  debugger em prod, backup com secret, crash reports.

### Adicionou — 2 fases de pipeline (Tier 5 continuidade)

- `pipeline/07-maintenance.md` (#19) — opt-in trimestral. Pipeline
  reduzido: drift + CVE + stale check. Sem rounds extensivos.
- `pipeline/08-drift-detection.md` (#21) — detecta defesas
  removidas em PRs posteriores (grep guard sumido, teste
  deletado, header dropped, audit chain quebrada).

### Adicionou — 7 specs em `docs/specs/`

Cada spec define forma, implementação proposta e razão de ainda
não estar implementado:

- `evidence-package.md` (#15)
- `atk-sbom.md` (#17)
- `reproducibility.md` (#16)
- `load-test-harness.md` (#6)
- `notifications.md` (#24)
- `api-contract.md` (#3)
- `race-fuzzing.md` (#4)

### Adicionou — scripts bash + validator (Tier 3 atrito)

- `scripts/preflight.sh`, `install.sh`, `check-update.sh` — Linux/macOS
  agora têm paridade com Windows.
- `scripts/validate.ps1` + `scripts/validate.sh` (#12) — wrapper
  básico que valida JSON contra `schemas/*.json` sem dep externa.

### Mudou — schemas/config.schema.json

- `target_framework` agora aceita **string OR array** (#18 multi-target):
  ```yaml
  target_framework: [iso27001, soc2]   # múltiplos coverage reports
  ```
- Novos flags: `dry_run` (#10), `minimal_mode` (#11),
  `maintenance_mode` (#19), `load_test`, `notifications`.

### Mudou — agentes existentes com seções v0.6.0

- `access-control.md` (#2): auth edges — reset enumeration, session
  fixation, mudança de email com reconfirmação, step-up auth,
  recovery code hashing.
- `patch-management.md` (#20): CVE feed subscription
  (GitHub Advisory, OSV.dev, NVD) + SLA por severity.
- `observability.md` (#8): RUM contínuo pós-launch + drift detection
  de Web Vitals.
- `scalability.md` (#9): benchmark obrigatório antes/depois pra DB,
  cache, pool, stampede.
- `devops.md` (#7): IaC fixes como PRs separados (branch `iac/*`).

### Mudou — AI-ENTRYPOINT.md

Novo Passo 0 — identificação de modo: FULL / DRY-RUN / MINIMAL /
MAINTENANCE. Decision tree determinístico por modo.

### Deferred com razão explícita

7 itens (#13 MULTI-AI ref impl, #23 web dashboard, #25 IDE plugin,
#26 CLI standalone, #27 examples, #28 catálogo comunitário,
#29 stack starters, #30 compat matrix) requerem trabalho fora do
escopo de um chat session — projetos full, infra comunitária,
extensões IDE. Documentados em ROADMAP.md com razão.

### % projetada com v0.6.0

- Segurança: 85-90% → **89-92%** (business-logic + runtime-secrets +
  auth edges)
- Escalabilidade: 70-80% → **80-85%** (benchmarking + IaC + maintenance)
- Fluidez: 75-85% → **82-87%** (RUM + drift detection)

### Não mudou

- Pipeline original (Fases 0-6).
- Agentes pre-existentes (mesmo comportamento, só ganharam seções v0.6).
- Schemas existentes (só `config.schema.json` evoluiu).
- Defaults.

## [0.5.0] — 2026-06-07

Foco: **facilitar a vida da AI** + **ponta-a-ponta determinístico** +
**termination clara**.

### Adicionou — contratos formais

- `schemas/` — 7 JSON schemas (draft-07) pra saídas validáveis:
  - `inventory.schema.json`, `threat.schema.json`, `arch.schema.json`
    — discovery (Fase 1)
  - `findings.schema.json`, `verdict.schema.json` — adversarial (Fase 4)
  - `state.schema.json`, `config.schema.json` — `.blindar/` no projeto-alvo
- `CONTRACT.md` — define a estrutura `.blindar/` que o skill mantém no
  projeto-alvo: `state.json` (resumability determinística),
  `config.yml` (overrides), `accept-risk.md`, `discovery/`, `checkpoints/`
- `.gitignore` recomendado pro projeto-alvo documentado

### Adicionou — entrypoint pra AI

- `AI-ENTRYPOINT.md` — UMA página que a AI lê primeiro com decision tree
  determinístico:
  - Identificação de modo (nativo Workflow vs manual)
  - Pre-flight check
  - Resume vs fresh start
  - Pipeline step-by-step
  - Termination check
  - Regras invioláveis
- Toda decisão tem regra explícita — sem "criatividade" necessária pra
  completar o ciclo

### Adicionou — preflight automatizado

- `scripts/preflight.ps1` — 1 comando que valida todos os 8 pré-reqs no
  projeto-alvo: repo git, branch viva, working tree limpo, CI, stack,
  gh autenticado, `.blindar/` dir, migração de accept-risk.md
- Flag `-Fix` corrige o que dá pra automatizar (criar `.blindar/`, migrar
  accept-risk.md da raiz)

### Adicionou — repo health

- `.github/workflows/lint.yml` — CI que valida:
  - JSON schemas são draft-07 válidos
  - VERSION é semver
  - Links markdown internos não quebram
  - `.ps1` files têm sintaxe válida
- `.github/ISSUE_TEMPLATE/bug.md` e `feature.md`
- `.github/PULL_REQUEST_TEMPLATE.md` reforça princípios do skill
  ("pago em PR vermelho mergeado")

### Adicionou — honestidade documentada

- `ROADMAP.md` — lista clara do que ficou de fora da v0.5.0 e por quê
  (bash scripts, examples, minimal mode, dry-run, monorepo, etc.)
- SKILL.md e README.md atualizados com seções "Para AIs" e estrutura
  do repo refletindo schemas/ + entrypoint + contract

### Migração de versões anteriores

Projetos com `accept-risk.md` na raiz: rode `scripts/preflight.ps1 -Fix`
na pasta do projeto-alvo. Move pra `.blindar/accept-risk.md`. Sem perda
de dados.

### Não mudou

- Pipeline de 6 fases.
- Agentes (17, mesmo conteúdo).
- Frameworks mapeados.
- Templates.
- Defaults do skill.

## [0.4.2] — 2026-06-07

### Adicionou
- `USAGE.md` — guia completo passo-a-passo de uso:
  - Instalação por OS
  - Pré-requisitos no projeto-alvo
  - Primeiro uso (passo a passo)
  - O que esperar durante execução + cronograma típico
  - Como acompanhar via `sec.html`
  - Parar / pausar / retomar
  - Critério de termination
  - Casos especiais (LGPD, PCI, framework alvo, stack obscura, pentest)
  - Modo multi-AI (referência ao MULTI-AI.md)
  - Atualização do skill
  - Troubleshooting (8 cenários comuns)
  - Comandos úteis
  - Resumo de 1 página

### Mudou
- `README.md` — adicionado link destacado para `USAGE.md` na seção de uso.

## [0.4.1] — 2026-06-07

### Adicionou
- `LICENSE` — MIT (copyright atribuído ao mantenedor)
- README.md atualizado com seção de licença

### Por quê MIT
Permissiva, amplamente compreendida, default sensato para skills. Não
restringe uso comercial. Forks precisam manter aviso de copyright.

## [0.4.0] — 2026-06-07

### Adicionou — frente "fluidez" (frontend performance)

`agents/frontend-performance.md` — Core Web Vitals based:
- **LCP** ≤ 2.5s, **INP** ≤ 200ms (substituiu FID em 2024), **CLS** ≤ 0.1
- Budget de bundle (170kb mobile / 350kb desktop, gzipped)
- Hidratação, animation jank, layout vs composite
- Adaptações por stack: React/RSC/Vue/Svelte/Astro/SPA vanilla
- RUM > Lab como princípio (sem RUM, não há prova de fluidez real)
- Ferramentas: Lighthouse CI, web-vitals lib, profilers

Origem dos thresholds: Google Web Vitals (web.dev/vitals), baseados
em Chrome UX Report — bilhões de pageviews reais. Não fabricado.

### Mudou — escalabilidade saiu de stub

`agents/scalability.md` agora tem conteúdo completo:
- Statelessness (12-factor) como pré-requisito
- Idempotência (Idempotency-Key, dedup em queue)
- Cache + proteção de stampede (SWR, lock distribuído)
- Queue + backpressure (DLQ, concurrency limit)
- DB scale (pool, PgBouncer/Proxy, replicas, migrations zero-downtime)
- Hot keys / fan-out / thundering herd
- Horizontal scaling readiness (/live vs /ready, graceful shutdown)
- Adaptações por stack: Node/Python(GIL/async)/Go/JVM/PG/Mongo

Princípio explícito: scale ≠ performance. Otimizar de 50→30ms não
ajuda se cair em 100 usuários simultâneos.

### Mudou — SKILL.md roster

- "Performance" agora explícito como "backend / gargalo medido"
- "Fluidez frontend" adicionada como categoria própria
- "Escalabilidade" sem marca de stub

### Não mudou

- Pipeline de 6 fases
- Outros agentes
- Defaults

## [0.3.1] — 2026-06-07

### Adicionou — OWASP ASVS como framework

- `frameworks/owasp-asvs.md` — mapeamento V1-V14 ↔ agents. Régua de
  verificação de aplicação (L1/L2/L3). Maior aderência prática entre
  os frameworks por ser baseado em requisitos verificáveis.
- Discovery passa a detectar nível ASVS alvo (default L2; L3 sob flag).

### Adicionou — metodologias de pentest em `agents/pentest.md`

Seção "Metodologias de referência" agora cobre:
- **PTES** (Penetration Testing Execution Standard)
- **OWASP WSTG** (Web Security Testing Guide)
- **NIST SP 800-115** (guia técnico)
- **OSSTMM** (subset operacional — físico/humano fora de escopo)
- **CREST** (conduta profissional — pra firma externa)

Cada uma documentada com **escopo e quando aplica**, não como agente
ativo — são estruturas de teste, não código a implementar.

### Adicionou — integração opcional HexStrike AI

`agents/pentest.md` documenta [HexStrike AI](https://github.com/0x4m4/hexstrike-ai)
como **opção avançada** para pentest interno autorizado:
- Pré-requisitos não negociáveis (autorização escrita, ambiente isolado,
  operador humano on-call)
- Quando NUNCA usar (sem autz, contra prod, contra terceiros)
- Aviso legal explícito (Lei 12.737 / Art. 154-A no BR)
- **Não é default do skill** — uso é decisão e risco do operador

### Adicionou — referências NIST SP 800

`frameworks/nist-csf.md` agora mapeia a família SP 800:
- SP 800-53 (catálogo controles), SP 800-61 (IR), SP 800-115 (pentest),
- SP 800-37 (RMF), SP 800-63 (auth), SP 800-88 (sanitização de mídia)

### Não adicionou (decisão explícita)

- **OSINT** — disciplina ofensiva de reconhecimento. Sai do escopo
  defensivo do blindar. Recomendação: ferramenta separada.
- **SANS, ANSI** — organização de treinamento e órgão de coordenação
  respectivamente, não frameworks. Mencionados em referências.

### Não mudou

- Comportamento do skill é o mesmo.
- Pipeline, agentes, defaults inalterados.
- Sem novos agentes — só novo framework + atualizações de docs.

## [0.3.0] — 2026-06-07

### Adicionou — security-first

- Princípio explícito **SECURITY-FIRST** no `SKILL.md`: em empate de
  severidade, segurança vence performance/scalability/UX.
- Novo quality gate: PR não-security não pode degradar defesa existente.
- Roster de agentes reordenado — agentes de segurança listados primeiro,
  carregados primeiro.

### Adicionou — 7 agentes de segurança especializados

Cobre as 10 técnicas clássicas de segurança de TI:

- `agents/access-control.md` (técnica #1) — auth/MFA/RBAC/least-privilege
- `agents/cryptography.md` (técnica #2) — TLS/at-rest/secrets/key-mgmt
- `agents/network-security.md` (técnicas #3, #8) — WAF/rate-limit/IaC SG
- `agents/patch-management.md` (técnica #5) — OS/runtime + Renovate
- `agents/backup-recovery.md` (técnica #6) — backup cifrado + restore testado
- `agents/observability.md` (técnica #7) — logs estruturados + métricas + audit
- `agents/pentest.md` (técnica #10) — SAST/DAST/SCA/fuzz automatizados

### Adicionou — frameworks/

Mapeamento de controles ↔ agentes (referência, não agentes ativos):

- `frameworks/iso-27001.md` — mais aceito internacionalmente
- `frameworks/nist-csf.md` — operacional/estratégico (6 funções v2.0)
- `frameworks/cis-controls.md` — 18 controles pragmáticos
- `frameworks/pci-dss.md` — **condicional** (só se processa cartão)
- `frameworks/soc2.md` — SaaS / cloud / B2B
- `frameworks/cobit.md` — **stub** (governança, baixa aplicabilidade em código)

### Adicionou — runbooks/

Templates para o que NÃO cabe em código:

- `runbooks/antimalware.md` (técnica #4)
- `runbooks/network-segmentation.md` (parte física da técnica #8)
- `runbooks/security-awareness.md` (técnica #9)
- `runbooks/pentest-schedule.md` (complemento à #10)

### Adicionou — multi-AI

- `MULTI-AI.md` — princípio "sempre multi-agente" + receita pra rodar em
  ChatGPT/Gemini/Cursor via role-play sequencial isolado.
- SKILL.md inclui princípio explícito **SEMPRE MULTI-AGENTE** (mesmo em
  AIs single-threaded).

### Mudou

- `SKILL.md` cresceu de 145 para ~200 linhas — princípios + roster expandido.
- Roster de agentes agora separa "segurança" (sempre primeiro) de
  "outros" (sob demanda).
- README.md e checklist atualizados refletindo nova estrutura.

### Não mudou

- Pipeline de 6 fases.
- Template `sec.html`.
- Defaults do skill (round size, cadência adversarial).
- Agentes pré-existentes preservam comportamento.

## [0.2.0] — 2026-06-07

### Mudou
- **Reestruturado em módulos**. O `SKILL.md` monolítico (553 linhas) virou
  orquestrador curto que referencia `pipeline/`, `agents/`, `templates/`.
- Template `sec.html` extraído para `templates/sec.html`.
- Roster de agentes (10 especialistas) extraído para `agents/*.md`.
- Pipeline de 6 fases extraído para `pipeline/00..06`.

### Adicionou
- `README.md` para apresentação no GitHub.
- `CHECKLIST.md` para validação pós-download.
- `VERSION` + `CHANGELOG.md` para versionamento.
- `scripts/check-update.ps1` — checa versão remota com TTL de 24h.
- `scripts/install.ps1` — clona/copia o skill para `~/.claude/skills/blindar`.
- `scripts/release.ps1` — bump de versão + tag + GitHub release (dono).
- `agents/scalability.md` — **stub TODO**, conteúdo a ser pago em PR real.

### Não mudou
- Comportamento do skill é idêntico. Mesma pipeline, mesmos prompts.
- Defaults inalterados.

## [0.1.0] — 2026-06-07

### Adicionou
- Versão monolítica inicial do `SKILL.md` (preservada em `SKILL.md.backup-v0`).
- 6 fases, 10 agentes, template `sec.html` inline.
- Extraída de execução real: 118 rounds, 68 ATKs fechados, 24 findings
  adversariais.
