---
name: blindar
description: |
  Audita, blinda, otimiza e prepara o projeto para produção. Detecta primeiro a
  natureza do trabalho — GREENFIELD (criar do zero), HARDEN (blindar existente),
  FEATURE (acrescentar capacidade sem estragar o resto), EVOLVE (já em produção,
  incremental e reversível), RECOVERY (quebrado, estabilizar antes) ou COLLAB
  (o repositório é o problema: git, CI, docs e revisão para a equipe) — e só então roda o pipeline: launcher (5 perguntas + menu
  de 19 módulos) → baseline → discovery → sec.html → rounds pequenos (1 PR cada)
  → adversarial review → production checklist → release gates → relatório.
  Mantém sec.html como dashboard vivo. Release decidida por 11 gates
  independentes com veredito GO / CONDITIONAL GO / NO-GO — dimensão sem check
  executado conta como NOT VERIFIED, nunca como aprovação. Modos de execução:
  AUTO, SUPERVISIONADO, ESCOLHIDOS. Cobre segurança, arquitetura, banco
  (inclusive provar que a migração SQLite→PostgreSQL chegou ao runtime),
  paridade de ambientes, resiliência, observabilidade, LGPD, a11y,
  responsividade, e elimina mocks/console.log/TODOs.

triggers:
  - "blindar"
  - "blinda este projeto"
  - "deixa pronto pra produção"
  - "production ready"
  - "harden this project"
  - "cria do zero já blindado"
  - "o projeto quebrou"
  - "migra pra postgres"
  - "implementa"
  - "adiciona"
  - "cria a tela de"
  - "organiza o git"
  - "preparar para a equipe"
---

# blindar — orquestrador

## EXECUÇÃO MANDATÓRIA — LEIA ANTES DE TUDO

Quando esta skill for invocada (`blindar`, `blinda este projeto`, etc.), você (Claude) DEVE executar EXATAMENTE esta sequência, sem pular, sem perguntar antes de cada passo, sem alternativas:

0. **Checagem de versão (1× por dia).** Rode
   `bash ~/.claude/skills/blindar/scripts/check-update.sh --quiet`
   (Windows sem bash: `scripts/check-update.ps1 -Quiet`).
   Ele tem cache de 24h, então na segunda invocação do mesmo dia sai na hora.
   - **Exit 10 = existe versão nova.** NÃO atualize sozinho: mostre a versão
     local, a nova, e **pergunte** se o operador quer atualizar agora, com o
     comando que o próprio script imprimiu — ele já detecta se a instalação é
     clone (`git pull`) ou artefato do sync (reinstalar), porque dizer o
     comando errado é pior que não dizer.
   - Exit 0 = seguir sem comentar.
   - Sem rede, o script sai 0 e você segue. Falha de checagem nunca vira
     bloqueio, e nunca vira "está atualizado" — só significa que não deu pra
     saber.
   - Desativar de vez: `BLINDAR_SKIP_UPDATE_CHECK=1`.
1. Registre a hora de início: `date -u +%Y-%m-%dT%H:%M:%SZ`
2. `bash ~/.claude/skills/blindar/scripts/blindar-run.sh --parallel auto` (ou `--fast` se usuário pediu rápido)
3. Aguardar conclusão (exit code 0-4)
4. Ler `.blindar/run-report.json` e **validar frescor**: `ran_at` DEVE ser ≥ hora
   registrada no passo 1. Se for mais antigo, o orquestrador morreu antes de
   escrever o report — trate como exit 4 (ERRORED), reporte e PARE. Nunca
   apresente um report de execução anterior como se fosse desta.
5. **Se `deferred > 0`** — sua fila de trabalho, **não é opcional**.

   **Rode em SUBAGENTES PARALELOS, um por agente**, não em sequência no seu
   próprio contexto. Num projeto real isso foram **49 playbooks**: executá-los
   em fila enche a janela e os últimos recebem menos atenção que os primeiros —
   e ninguém percebe, porque o relatório sai igual. Contexto isolado por agente
   é o que mantém o quadragésimo nono tão cuidadoso quanto o primeiro.

   Dispare em lotes (6–8 por vez). Cada subagente recebe:

   ```
   Execute o playbook agents/<agent>.md contra o projeto em <caminho>.

   Leia o playbook inteiro e siga o procedimento dele. Depois grave
   .blindar/results/check-<agent>.json no schema blindar/check-result@v1:
     { "schema":"blindar/check-result@v1", "agent":"check-<agent>",
       "ran_at":"<ISO-8601 UTC>", "git_sha":"<sha curto ou unknown>",
       "status":"passed|failed|skipped", "exit_code":0,
       "duration_sec":0, "missing_tool":null,
       "findings_count":N, "findings":[{"severity":"crit|high|med|low",
       "message":"...","file":"...","line":"..."}] }

   Regras que não se negociam:
   - severity SÓ pode ser crit|high|med|low. "critical"/"medium" não são
     contados por ninguém e deixam o portão de release passar.
   - todo finding crit/high precisa de `file` preenchido — ou, se for achado
     de runtime, a medição na mensagem. Achado sem onde verificar não é
     acionável nem auditável.
   - não achou nada = "passed" com findings []. NÃO invente achado para
     parecer útil, e não use "skipped" para o que você examinou.
   - "skipped" é só para o que NÃO SE APLICA a este projeto, e a mensagem
     precisa dizer por quê.
   Responda só com o caminho do arquivo gravado.
   ```

   Ao final, confira que cada `deferred` virou arquivo. Agente que não gravou
   result **não foi executado** — trate como `errored`, nunca como aprovado.

   Exceção: o operador pediu explicitamente para pular.
6. Ler `.blindar/proactive-analysis.md` se existir (análise consultiva nas 8 dimensões)
7. Apresentar ao usuário:
   - Resumo numérico (passed/failed/skipped/deferred/cobertura%), incluindo os
     deferred que VOCÊ executou no passo 5
   - Top 5 findings críticos (severity crit/high)
   - Análise proativa resumida (se gerada)
   - Recomendação de próxima ação

**Você NÃO pode**:
- Rodar agentes individualmente **fora** do orquestrador (invocando o `.sh`
  direto). Para tarefa pontual existe o caminho sancionado abaixo — que passa
  pelo orquestrador e marca o resultado como parcial.
- Pular passos da sequência acima
- "Decidir" que algum agente não é necessário
- Apresentar findings sem antes rodar o orquestrador
- Apresentar resultado final com `deferred > 0` sem ter executado os playbooks (passo 5)
- Confiar num `run-report.json` sem validar `ran_at` (passo 4)
- Pular `proactive-analysis` se ANTHROPIC_API_KEY existe

**Se algo falhar**: reporte exit code + arquivo de log, NÃO tente "consertar" rodando outras coisas.

### Verificar o host (⭐ v0.66)

O blindar cobre o **código**. Firewall ativo, certificado válido, backup fresco,
DNS apontando certo e vizinho de container saudável só se veem **no servidor** —
e isso é da skill irmã [`ancorar`](https://github.com/pretinhuu1-boop/ancorar).

```bash
bash scripts/ancorar-bridge.sh --host meu.servidor.com
```

A ponte invoca só as fases de **leitura** do ancorar (0, 1, 3, 7, 8, 10). As que
mutam o host — provisionar, migrar, cutover, decommission — são **recusadas** com
o comando certo no lugar: automatizá-las daqui trocaria o *supervisionado +
dry-run* do ancorar pelo *auto* daqui.

O resultado entra no gate `DEPLOYMENT`: ancorar reprovando o host vira
**BLOCKED**, e host nunca verificado vira warning. Host não verificado não é
host aprovado.

### Execução avulsa (⭐ v0.63) — tarefa pontual

Quando o operador quer **uma coisa só** ("roda só o anti-mock aqui", "checa só a
paridade de ambientes"), não faz sentido esperar o orquestrador inteiro:

```bash
bash scripts/blindar-run.sh --only mock-killer,environment-parity
```

Roda em segundos em vez de minutos, e continua passando pelo orquestrador — o
result é gravado no formato normal e o schema é validado.

**A trava que faz isso ser seguro**: o run parcial nunca pode ser confundido com
cobertura completa. O `coverage_pct` continua medido contra o total
**disponível**, não contra a lista filtrada — rodar 1 agente de 130 mostra
**0%**, não 100%. E o `run-report.json` carrega `partial: true`, `only_agents`
e `not_run_by_filter`.

Um resultado parcial **não é veredito de release**. Para isso, run completo.

### Precedência: sequência mandatória × launcher

A sequência acima roda em **TODA invocação**, sem perguntas. O launcher
(5 perguntas + menu, seção "Comportamento" abaixo) só entra quando o usuário
pedir o **engajamento completo de hardening** (rounds/PRs/sec.html) ou modo
supervisionado — e mesmo nesse caso, o primeiro passo continua sendo o
orquestrador determinístico. Em caso de dúvida sobre qual fluxo o usuário quer:
a sequência mandatória é o default; o pipeline completo é opt-in.

Esta restrição existe porque blindar foi desenhado pra ser determinístico e auditável. Pular passos quebra a garantia de cobertura.

Exit codes:
- 0 = PASS (release-ready)
- 1 = CONDITIONAL (deferred — Claude precisa rodar playbooks .md restantes)
- 2 = NO-GO (failed crit/high)
- 3 = STRICT-FAIL (deferred em modo strict)
- 4 = ERRORED (bug em script blindar — reporte bug)

## Módulo 16 — Product Evolution (opt-in, escopo separado)

Quando o usuário pedir **auditoria de produto/evolução** (não hardening),
rode o orquestrador dedicado:

```bash
bash scripts/blindar-evolve.sh
```

Cobre: APIs sem front-end, funcionalidades parciais, jornadas por perfil,
oportunidades de crescimento por ROI, críticas adversariais de produto.
Gera `.blindar/evolution-report.md` consolidado.

**REQUER `ANTHROPIC_API_KEY`** (todos 5 agentes são API-wrapped).

NÃO entra no fluxo padrão de hardening. NÃO confunda com `blindar-run.sh`.
São escopos diferentes: hardening = "seguro pra produção"; evolution = "o que falta de produto".

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

## O hub (⭐ v0.69)

Um comando resolve. O `blindar` roteia o pedido antes de agir:

```
                    ┌─ servidor?      → ancorar-bridge.sh (skill irmã, fases de leitura)
  blindar  ─────────┼─ criar skill?   → skill-builder (docs/agentic-harness/)
                    └─ este projeto?  → os 6 modos abaixo
```

Você chama `blindar` e ele **audita, constrói, acrescenta, evolui, conserta,
organiza o repositório, verifica o servidor e cria a próxima skill**. Nada de
lembrar qual ferramenta chamar.

Dois repositórios no total: este e o
[`ancorar`](https://github.com/pretinhuu1-boop/ancorar), que fica separado
porque tem código próprio (16 checks de host, SSH, 10 fases) e um contrato de
supervisão diferente — absorvê-lo seria duplicar. O `install.sh` oferece clonar
os dois.

O molde para criar skills vive **aqui dentro**, em
[`docs/agentic-harness/`](docs/agentic-harness/): é markdown puro, sem código,
e separá-lo custava um repositório sem entregar nada.

## Modos de operação (⭐ v0.51)

Antes do launcher, a Fase [`00-mode-select`](pipeline/00-mode-select.md)
detecta **a natureza do trabalho** e confirma com o operador. O modo altera
gates, tamanho de round e o que é permitido alterar — não é rótulo de
relatório.

| Modo | Quando | Pipeline | Trava principal |
|---|---|---|---|
| `greenfield` | não há o que blindar | [`GREENFIELD.md`](pipeline/GREENFIELD.md) | constrói já dentro das regras; termina entregando ao `harden` |
| `harden` | projeto existente e saudável (**default**) | 00 → 09 | comportamento clássico |
| `feature` ⭐ v0.62 | pedido é **acrescentar capacidade** | [`FEATURE.md`](pipeline/FEATURE.md) | nasce dentro das regras; checks no fim rodam sobre o **diff** (`--since`), não sobre o projeto inteiro |
| `evolve` | já está em produção | 00 → 09 | `supervised` forçado, round ≤40 LOC, migration destrutiva proibida |
| `recovery` | sistema quebrado | [`RECOVERY.md`](pipeline/RECOVERY.md) | suite vermelha é a **entrada**, não o abort; uma correção por vez |
| `collab` ⭐ v0.63 | o **repositório** é o problema | [`COLLAB.md`](pipeline/COLLAB.md) | git, CI, docs e revisão para a equipe; `.gitignore` antes do primeiro commit |

Precedência da detecção: `recovery` > `greenfield` > `evolve`/`feature` >
`harden`. Não se blinda escombro, não se audita o vazio, não se experimenta em
produção.

`feature` é o único detectado pelo **pedido**, não pelo estado do repositório —
um projeto saudável que vai receber uma feature é indistinguível, no disco, de
um que vai ser auditado. E em produção ele **compõe** com o `evolve` em vez de
substituí-lo: disciplina de construção mais as travas de quem tem usuários.

Configurado em `operation_mode` (ortogonal a `mode`, que é auto/supervised/chosen).

## Comportamento

Invocado → detecta **modo de operação** → roda **launcher curto** (5 perguntas
+ menu) → depois executa o que foi escolhido conforme o modo:

- **AUTO** → vai do início ao fim sem pedir confirmação (default sugerido)
- **SUPERVISIONADO** → pausa entre módulos pra revisar
- **ESCOLHIDOS** → roda só os módulos numerados que o operador selecionou

Após o launcher, não há mais perguntas (a não ser em modo supervisionado).
Operador acompanha em tempo real abrindo `sec.html` no browser.

### Launcher (Fase 00)

Ver [`pipeline/00-launcher.md`](pipeline/00-launcher.md). Faz 5 perguntas
objetivas:

1. **Tipo de projeto** (SaaS / MVP / LP / E-com / API / Mobile / CLI)
2. **Sensibilidade de dados** (Alta / Média / Baixa — define peso do módulo LGPD)
3. **Modo de execução** (Auto / Supervisionado / Escolhidos)
4. **Rigor** (Produção / Compliance / MVP)

E exibe o menu numerado de **19 módulos** (próxima seção). Aceita "tudo",
"defaults", "1,3,5,7", "1-8", "tudo menos 13,14".

Grava `.blindar/config.yml` com as escolhas. Pula automaticamente em
`--resume` ou `--headless` (CI/cron).

## Menu de módulos (19 numerados)

| # | Módulo | Quando default ON | Agentes |
|---|---|---|---|
| 1 | Baseline & Discovery | sempre | [`strategic-scanner`](agents/strategic-scanner.md) |
| 2 | Segurança aplicacional core + AI/LLM + Tenant isolation + File uploads + MLOps | sempre | [`access-control`](agents/access-control.md), [`cryptography`](agents/cryptography.md), [`business-logic`](agents/business-logic.md), [`runtime-secrets`](agents/runtime-secrets.md), [`security`](agents/security.md), [`auth-premium`](agents/auth-premium.md), [`ai-llm-safety`](agents/ai-llm-safety.md), [`tenant-isolation-tests`](agents/tenant-isolation-tests.md), [`file-uploads`](agents/file-uploads.md), [`mlops`](agents/mlops.md) |
| 3 | Frontend hardening (CSP/XSS/SRI/Trusted Types) | se UI detectada | [`frontend`](agents/frontend.md) |
| 4 | Rede & API + Payments + Realtime + API Gateway + GraphQL + gRPC | tipo ∈ SaaS/E-com/API | [`network-security`](agents/network-security.md), [`api-design`](agents/api-design.md), [`payments`](agents/payments.md), [`realtime`](agents/realtime.md), [`api-gateway`](agents/api-gateway.md), [`graphql`](agents/graphql.md), [`grpc-internal`](agents/grpc-internal.md) |
| 5 | Supply chain & patch + SBOM/SLSA (compliance 2026) | sempre | [`supply-chain`](agents/supply-chain.md), [`patch-management`](agents/patch-management.md), [`sbom-slsa`](agents/sbom-slsa.md) |
| 6 | Observabilidade & audit + Log lifecycle/retenção + Cost monitoring | tipo ∈ SaaS/E-com/API | [`observability`](agents/observability.md), [`log-ops-retention`](agents/log-ops-retention.md), [`cost-observability`](agents/cost-observability.md) |
| 7 | Banco de dados + Backup & DR + **Migração de engine** + **Paridade de ambientes** + Multi-region + Data Warehouse/ETL | se DB detectado | [`backup-recovery`](agents/backup-recovery.md), [`db-architect`](agents/db-architect.md), [`db-migration-guardian`](agents/db-migration-guardian.md) ⭐, [`environment-parity`](agents/environment-parity.md) ⭐, [`multi-region`](agents/multi-region.md), [`data-warehouse-etl`](agents/data-warehouse-etl.md) |
| 8 | Compliance: LGPD + GDPR + HIPAA + PCI-DSS + frameworks | sensibilidade ≠ Baixa OU compliance | [`compliance-lgpd-br`](agents/compliance-lgpd-br.md), [`compliance`](agents/compliance.md), [`compliance-gdpr`](agents/compliance-gdpr.md), [`compliance-hipaa`](agents/compliance-hipaa.md), [`compliance-pci-deep`](agents/compliance-pci-deep.md) |
| 9 | Performance backend + Query + CDN strategy | tipo ∈ SaaS/E-com/API | [`performance`](agents/performance.md), [`db-architect`](agents/db-architect.md), [`cdn-strategy`](agents/cdn-strategy.md) |
| 10 | Fluidez completa + SEO + Frontend gen + Search + Push + Mobile native + Analytics + Audio + Video | se UI detectada | [`frontend-performance`](agents/frontend-performance.md), [`responsive-a11y`](agents/responsive-a11y.md), [`pwa-installable`](agents/pwa-installable.md), [`i18n-tz`](agents/i18n-tz.md), [`state-cache-data`](agents/state-cache-data.md), [`onboarding-ux`](agents/onboarding-ux.md), [`seo-marketing-meta`](agents/seo-marketing-meta.md), [`frontend-generator`](agents/frontend-generator.md), [`search-quality`](agents/search-quality.md), [`push-notifications`](agents/push-notifications.md), [`mobile-native`](agents/mobile-native.md), [`embedded-analytics`](agents/embedded-analytics.md), [`audio-voice`](agents/audio-voice.md), [`video-streaming`](agents/video-streaming.md) |
| 11 | Funcional E2E + Testing strategy + Visual regression | sempre | [`functional-e2e`](agents/functional-e2e.md), [`testing-strategy`](agents/testing-strategy.md), [`visual-regression`](agents/visual-regression.md) |
| 12 | Anti-mock + Externalização + Content quality (gramática/tom/glossário) | sempre | [`mock-killer`](agents/mock-killer.md), [`config-externalization`](agents/config-externalization.md), [`content-quality`](agents/content-quality.md) |
| 13 | Resiliência + escalabilidade + Process + Scheduled jobs + Chaos + Event-driven | rigor ≠ MVP | [`resilience`](agents/resilience.md), [`scalability`](agents/scalability.md), [`process-resilience`](agents/process-resilience.md), [`scheduled-jobs`](agents/scheduled-jobs.md), [`chaos-engineering`](agents/chaos-engineering.md), [`event-driven`](agents/event-driven.md) |
| 14 | DX + Flags + Backoffice + Email + Docs + Reports + Architect + Delivery + Project bootstrap + **Governança de mudança** | sempre | [`devops`](agents/devops.md), [`feature-flags`](agents/feature-flags.md), [`backoffice-admin`](agents/backoffice-admin.md), [`email-deliverability`](agents/email-deliverability.md), [`documentation-live`](agents/documentation-live.md), [`execution-report`](agents/execution-report.md), [`architect`](agents/architect.md), [`delivery-bundle`](agents/delivery-bundle.md), [`project-bootstrap`](agents/project-bootstrap.md), [`risk-engine`](agents/risk-engine.md) ⭐, [`change-impact`](agents/change-impact.md) ⭐, [`decision-log`](agents/decision-log.md) ⭐ |
| 15 | Pentest + adversarial review + **Runtime adversarial** | sempre | [`pentest`](agents/pentest.md), [`adversarial-reviewer`](agents/adversarial-reviewer.md), [`runtime-adversarial`](agents/runtime-adversarial.md) ⭐ |
| 16 | Product Evolution (opt-in, escopo separado — requer `ANTHROPIC_API_KEY`) | só se pedido | [`api-frontend-coverage`](agents/api-frontend-coverage.md), [`user-journey-simulator`](agents/user-journey-simulator.md), [`feature-gap-analyzer`](agents/feature-gap-analyzer.md), [`growth-opportunities`](agents/growth-opportunities.md), [`product-critic`](agents/product-critic.md) |
| 17 | Ataque — recon passivo externo (requer URL alvo) | se URL fornecida | [`attack-recon`](agents/attack-recon.md) |
| 18 | Smoke / Runtime Truth + checks de infra (prova que a app SOBE) | sempre (self-skip sem docker/URL) | [`smoke-runtime`](agents/smoke-runtime.md) + 9 checks de infra/runtime |
| 19 | Pentest ATIVO — payloads reais (requer `.blindar/.accept-authorization`) | só com autorização | [`pentest-active`](agents/pentest-active.md) |

> **Total**: 117 agentes em 19 módulos (90 checks determinísticos + 14 API-wrapped = 104 `check-*.sh`, + playbooks).
> Contagem verificada por `ls agents/*.md` e `ls templates/checks/check-*.sh` em v0.58 —
> os números anteriores (118/81) tinham derivado do real.
> Fonte da verdade: [`pipeline/MODULE-MAP.json`](pipeline/MODULE-MAP.json).

**Módulos não-negociáveis** (sempre rodam, mesmo em "MVP"): **1, 2, 11, 12, 15** (+ 18, que self-skipa quando não há runtime pra subir).

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
| **00 — Mode select** ⭐ v0.51 | [`pipeline/00-mode-select.md`](pipeline/00-mode-select.md) | 20s–1min |
| **00 — Launcher** ⭐ v0.8 | [`pipeline/00-launcher.md`](pipeline/00-launcher.md) | 30s–2min |
| 0 — Strategic Scan & Planning | [`pipeline/00-strategic-scan.md`](pipeline/00-strategic-scan.md) | ~3 min |
| 1 — Baseline | [`pipeline/01-baseline.md`](pipeline/01-baseline.md) | ~2 min |
| 2 — Discovery | [`pipeline/02-discovery.md`](pipeline/02-discovery.md) | ~3 min |
| 3 — Bootstrap sec.html | [`pipeline/03-bootstrap-sec-html.md`](pipeline/03-bootstrap-sec-html.md) | ~1 min |
| 4 — Loop de rounds | [`pipeline/04-rounds-loop.md`](pipeline/04-rounds-loop.md) | até termination |
| 5 — Adversarial review | [`pipeline/05-adversarial-review.md`](pipeline/05-adversarial-review.md) | ~10 min (a cada 10 rounds) |
| 6 — Production checklist | [`pipeline/06-production-checklist.md`](pipeline/06-production-checklist.md) | ~3 min |
| **6b — Release gates** ⭐ v0.53 | [`pipeline/06b-release-gates.md`](pipeline/06b-release-gates.md) | ~1 min |
| **10 — Alvo de deploy** ⭐ v0.56 | [`pipeline/10-deployment-target.md`](pipeline/10-deployment-target.md) | ~2 min |
| 7 — Relatório final | [`pipeline/07-final-report.md`](pipeline/07-final-report.md) | ~2 min |
| 8 — **Maintenance** (opt-in, trimestral) | [`pipeline/08-maintenance.md`](pipeline/08-maintenance.md) | ~5 min |
| 9 — **Drift detection** (subfase de 8) | [`pipeline/09-drift-detection.md`](pipeline/09-drift-detection.md) | ~3 min |

Pipelines alternativos (não numerados — substituem o fluxo acima conforme o
`operation_mode`):

| Pipeline | Arquivo | Entra por |
|---|---|---|
| **GREENFIELD** ⭐ v0.51 | [`pipeline/GREENFIELD.md`](pipeline/GREENFIELD.md) | `operation_mode: greenfield` |
| **FEATURE** ⭐ v0.62 | [`pipeline/FEATURE.md`](pipeline/FEATURE.md) | `operation_mode: feature` |
| **COLLAB** ⭐ v0.63 | [`pipeline/COLLAB.md`](pipeline/COLLAB.md) | `operation_mode: collab` |
| **RECOVERY** ⭐ v0.51 | [`pipeline/RECOVERY.md`](pipeline/RECOVERY.md) | `operation_mode: recovery` |

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

[`chief-architect`](agents/chief-architect.md) arbitra entre os leads, por
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

Validado por [`tests/agents-registry.test.mjs`](tests/agents-registry.test.mjs)
nos dois sentidos: toda entrada do `MODULE-MAP` resolve para playbook ou check,
e todo playbook é ativado por algum módulo. Metadata que ninguém valida
apodrece em silêncio — o teste nasceu achando 2 agentes sem frontmatter e 2
playbooks que nenhum módulo executava.

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
| Observabilidade / audit / logs (conteúdo) | [`agents/observability.md`](agents/observability.md) |
| Log em disco: rotação / retenção / guardas (continente) | [`agents/log-ops-retention.md`](agents/log-ops-retention.md) |
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

## Deterministic Layer (⭐ v0.22)

Camada de scripts shell que **materializa agentes em checks executáveis**
+ CI workflow que bloqueia merge. Resolve "blindar não garante 100% no
modo AUTO" — agora roda **independente da diligência do LLM**.

Templates em [`templates/checks/`](templates/checks/). Instalador:

```bash
cd seu-projeto
bash ~/.claude/skills/blindar/scripts/install-deterministic-checks.sh
```

Resultado no projeto-alvo:
- `scripts/blindar/*.sh` — 8 checks executáveis (secrets, mock-killer,
  config-ext, deps audit, prisma schema, payments, file-uploads, tenant-isolation)
- `.github/workflows/blindar.yml` — CI obrigatório
- `.husky/pre-commit + pre-push` — gates locais
- `.blindar/results/*.json` — output auditável + agregado
- `scripts/blindar/check-termination.sh` — decisão matemática de release

Doc completa: [`docs/deterministic-layer.md`](docs/deterministic-layer.md).

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

Duas condições, ambas necessárias. A contagem é **necessária, não suficiente**.

### 1. Contagem (`check-termination.sh`)

- [ ] 0 confirmed crit no último adversarial
- [ ] ≤ 2 confirmed high (em `.accept-risk.md`)
- [ ] Categorias críticas ≥ 80% covered+partial
- [ ] 3 runbooks gerados em `docs/`: incident-response, key-rotation, supply-chain
- [ ] CI verde por 3 PRs consecutivos
- [ ] Production checklist Fase 6 ✓
- [ ] Coverage report do framework alvo (se declarado) gerado

### 2. Release gates (⭐ v0.53 — [`check-release-gates.sh`](templates/checks/check-release-gates.sh))

11 dimensões independentes, veredito **GO / CONDITIONAL GO / NO-GO**. Ver
[`pipeline/06b-release-gates.md`](pipeline/06b-release-gates.md).

`SECURITY` · `ARCHITECTURE` · `DATABASE` · `RUNTIME` · `RESILIENCE` ·
`OBSERVABILITY` · `PRIVACY` · `QUALITY` · `DEPLOYMENT` · `BACKUP_RECOVERY` ·
`DOCUMENTATION`

Por que a contagem sozinha não bastava: um projeto com **0 crit e 0 high** pode
rodar SQLite enquanto a infra declara PostgreSQL, não ter backup que alguém já
tenha restaurado, e não ter rollback. Severidade agregada mede o que os checks
**acharam** — não o que ficou por verificar.

Três regras que decorrem disso:

- Gate sem check executado é `NOT VERIFIED`, **não** `PASS`. Conta como warning
  e só é dispensado por aceite assinado.
- `BACKUP_RECOVERY` exige evidência de **restore**, não de backup.
  `DEPLOYMENT` exige **rollback**.
- Zero checks com resultado ⇒ `NO-GO`. Sem medição não há aprovação.

A primeira pergunta é "achamos problema demais?". A segunda, "deixamos de olhar
para alguma coisa?".

## Princípio de evidência (⭐ v0.57)

Toda afirmação precisa de onde ser verificada. Não "PostgreSQL está
configurado", mas "PostgreSQL em `docker-compose.yml:3`, usado por
`src/db.ts:1`, migration `002`, conexão confirmada em `pg_stat_activity`".

Verificável na fonte por
[`check-evidence.sh`](templates/checks/check-evidence.sh), antes de virar
prosa: achado `crit`/`high` precisa de `file`; gate precisa de `evidence`.
Achado de runtime é a exceção — a prova dele é a **medição**, não a
localização.

O relatório final (Fase 07) passa a exigir também: modo de operação usado com
a evidência que o produziu, os 11 gates com evidência, gates pulados por modo
nomeados, decisões arquiteturais do ciclo, e **o que não foi alterado e por
quê** — sem essa última, "não aparece no relatório" se confunde com "não
existe".

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

## Sincronização dev ↔ instalada

Se você desenvolve o blindar num repo separado (ex: `Documents/Axial/Blidar`),
a cópia instalada em `~/.claude/skills/blindar` é um **artefato** — nunca edite
lá. Após qualquer mudança no dev:

```bash
bash scripts/sync-skill.sh          # aplica (copia tracked + remove órfãos + verifica)
bash scripts/sync-skill.sh --check  # só reporta drift (exit 1 se divergiu)
```

O script usa o file-set tracked do git como fonte da verdade e preserva o
estado de runtime da instalada (`.git/`, `.blindar/`, `.last-check`).

## Auto-update

**Passo 0 da sequência mandatória**, uma vez por dia (cache de 24h em
`.last-check`). Roda `scripts/check-update.sh --quiet` — ou `check-update.ps1
-Quiet` no PowerShell.

**Pergunta, não atualiza sozinho.** Exit 10 significa versão nova: mostre local
× nova e deixe o operador decidir. Atualizar sem perguntar troca o código sob os
pés de quem está no meio de um trabalho.

O comando de atualização sai do próprio script, porque depende de como a skill
foi instalada: clone → `git pull --ff-only`; artefato do `sync-skill.sh` (sem
`.git`) → reinstalar pelo `install.sh`. Dizer o comando errado é pior que não
dizer, porque o operador tenta e acha que quebrou.

Sem rede: sai 0 e segue. Falha de checagem **nunca** vira bloqueio nem vira
"está atualizado" — significa apenas que não deu para saber.

Desativar: `BLINDAR_SKIP_UPDATE_CHECK=1`. Forçar: `--force` / `-Force`.

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
