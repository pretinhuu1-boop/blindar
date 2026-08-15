# Plano EOS — Blindar de "auditor" para Engineering Operating System

> Base: v0.50.0 (dev e instalada em sync). Alvo: v0.58.
> Origem: proposta externa de reestruturação + auditoria do estado real do repo.
> Regra de ouro: **delta, não reescrita**. Nada que já funciona é destruído para reorganizar.

---

## 0. Diagnóstico — o que a proposta externa errou

A proposta assumiu lacunas que não existem. Confirmado por inspeção do repo:

| Item proposto | Já existe em v0.50 | Onde |
|---|---|---|
| Project Intelligence | Sim | `.blindar/intelligence.yml`, `schemas/intelligence.schema.json` |
| Dependency/architecture graph | Sim | `agents/graph-builder.md`, `scripts/graph-build.js` |
| Detecção → ativação de especialistas | Sim | `pipeline/MODULE-MAP.json` (`default_on_when`, `mandatory`) |
| Hooks determinísticos | Sim | `templates/checks/` (101), `scripts/install-deterministic-checks.sh` |
| Reality Check (mock/fake/hardcode) | Sim | `agents/mock-killer.md`, `check-mock-killer.sh`, `agents/smoke-runtime.md` |
| Runtime truth (app sobe de verdade) | Sim | `scripts/smoke-run.sh`, módulo 18 |
| Adversarial review | Sim | `pipeline/05-adversarial-review.md` |
| DAST / ataque | Parcial | `agents/attack-recon.md` (passivo), `agents/pentest-active.md` (ativo, requer autorização) |
| Relatórios multinível | Sim | `templates/sec.html`, `execution-report.html`, `client-report.html` |
| Estado do orquestrador | Sim | `.blindar/state.json` (resume) |
| Filas / DLQ / idempotência | Sim | `agents/queue-management.md`, `event-driven.md`, `process-resilience.md` |
| Backup / restore / rollback | Sim (como agente) | `agents/backup-recovery.md`, `check-backup-recovery.sh` |
| Governança de tokens | Sim | `templates/checks/_token_governor.sh` |

**Lacunas reais** (0 hits no grep do repo):

1. `greenfield` — não há modo de projeto do zero. Só existe o caminho "projeto existente".
2. `decision-log` — decisões arquiteturais não são registradas; nada impede o Claude desfazer uma decisão anterior em outra sessão.
3. `environment parity` — nenhum check compara DEV × TEST × PROD.
4. Migração SQLite → PostgreSQL — `sqlite` só aparece de passagem em 4 agentes; não há cadeia de migração nem prova de runtime.
5. `risk engine` / change impact — nenhuma classificação de risco antes de alterar.
6. Gates multidimensionais — termination é binária (`0 crit + ≤2 high`); um projeto pode passar com SQLite em produção e sem backup.
7. `ancorar` / `sentinela` — zero integração conceitual.
8. Hierarquia de agentes — 109 agentes chapados, sem domain leads; nenhuma autoridade arquitetural para arbitrar conflito entre especialistas.

---

## 1. O que NÃO vamos fazer (rejeitado da proposta externa)

| Proposta | Motivo da rejeição |
|---|---|
| Quebrar em "subskills" separadas | Claude Code carrega uma skill por diretório. Blindar já faz progressive disclosure via `agents/*.md` e `pipeline/*.md` referenciados por path. Fragmentar quebraria `MODULE-MAP.json` e o launcher sem ganho. |
| Reestruturar `.claude/{rules,skills,agents,hooks}` no repo do Blindar | Blindar atua **sobre projetos-alvo**. Rules/hooks já são instalados no alvo pelo `install-deterministic-checks.sh`. Criar essa árvore aqui duplicaria conceito. |
| Reescrever a hierarquia de 109 agentes | Churn alto, risco de quebrar `MODULE-MAP.json`, checks e fixtures. Vira **camada de metadata** (`lead:` por agente) na Fase 7, sem mover arquivo. |
| Adotar o master prompt como CLAUDE.md | É especificação, não runtime. Vira este plano + os deltas por fase. |
| Criar dezenas de agentes novos | Princípio 12 do SKILL.md: "nenhum agente novo sem bug real observado". Cada agente novo abaixo tem justificativa de dor concreta. |

---

## 2. Fases

Cada fase = 1 release (`chore(release): vX`), executada **primeiro neste repo dev**, e só depois propagada para `~/.claude/skills/blindar` via `bash scripts/sync-skill.sh`.

Ritual fixo de encerramento de fase:

```bash
bash tests/run-tests.sh && bash scripts/validate.sh && bash scripts/sync-skill.sh --check
```

Só depois: `bash scripts/sync-skill.sh` (aplica), commit, tag.

---

### Fase 1 — Modos de operação (v0.51)

**Dor**: hoje só existe o caminho "projeto existente". Projeto do zero e projeto quebrado entram no mesmo pipeline errado.

| Modo | Quando | Pipeline |
|---|---|---|
| `HARDEN` | Projeto existente (default, comportamento atual) | 00 → 09 como hoje |
| `GREENFIELD` | Diretório vazio ou só scaffold | Requisitos → arquitetura → stack → DB → back → front → infra → testes → obs → deploy → readiness |
| `EVOLVE` | Já em produção | Só mudanças incrementais, compatibilidade, migration reversível; proíbe troca de tecnologia sem ADR |
| `RECOVERY` | App não sobe / suite vermelha | Incident discovery → root cause → estabilizar → só então hardening |

**Arquivos**:
- Novo `pipeline/00-mode-select.md` — detecta modo automaticamente, confirma com operador (5ª pergunta do launcher).
- Novo `pipeline/GREENFIELD.md`, `pipeline/RECOVERY.md`.
- Editar `pipeline/00-launcher.md` (pergunta 5), `SKILL.md` (§Comportamento, §Pipeline), `pipeline/MODULE-MAP.json` (`modes: []` por módulo).
- Editar `schemas/` — config ganha `mode`.
- `agents/project-bootstrap.md` vira o agente-âncora do GREENFIELD.
- Editar `pipeline/01-baseline.md`: hoje ele **para** se a suite está vermelha; em `RECOVERY` isso é a condição de entrada, não motivo de parada.

**Aceite**: fixture `tests/fixtures/project-greenfield-empty/` roda GREENFIELD sem erro; `project-recovery-broken/` não é abortada por suite vermelha.

---

### Fase 2 — Database Migration Guardian + Environment Parity (v0.52)

**Dor #1 declarada pelo operador**: pedir SQLite → PostgreSQL em container e o resultado ficar "cheio de sujeira" (Postgres no compose mas o código ainda usando SQLite).

Cadeia em 4 etapas, não um agente único:

1. **Detect** — qual engine em cada ambiente e em cada camada (ORM, driver, connection string, compose, CI, seeds, testes).
2. **Plan** — se SQLite existe e o alvo é produção: gera plano de migração com impacto (schema, tipos, sequences, UUID, timezone, JSONB, FKs, pooling, isolation).
3. **Execute** — altera config, driver, ORM, migrations, seed, compose, CI, docs.
4. **Prove** — **runtime evidence**: a app conectada em Postgres responde `/health` e uma escrita real persiste. Postgres no compose não conta como prova.

**Arquivos**:
- Novo `agents/db-migration-guardian.md`.
- Novo `agents/environment-parity.md`.
- Novo `templates/checks/check-db-engine-consistency.sh` — falha se engines divergem entre DEV/TEST/PROD ou se `sqlite` aparece em runtime path com rigor=Produção.
- Novo `templates/checks/check-environment-parity.sh` — gera `ENVIRONMENT DRIFT REPORT`.
- Estender `scripts/smoke-run.sh`: além de subir, provar engine efetiva em runtime.
- Fixtures: `project-dbdrift-bad` (Postgres no compose, SQLite no código) / `project-dbdrift-good`.
- `MODULE-MAP.json`: entram no módulo 7.

**Aceite**: `project-dbdrift-bad` reprova; `-good` passa. Sem esse par de fixtures a fase não fecha.

---

### Fase 3 — Release Gates + decisão GO / CONDITIONAL GO / NO-GO (v0.53)

**Dor**: termination hoje é `0 crit + ≤2 high`. Um projeto com zero vulnerabilidade e sem backup, sem rollback, com SQLite e com mock passa.

11 gates independentes, cada um com `PASS | PASS WITH WARNINGS | BLOCKED | N/A` + **evidência obrigatória**:

`SECURITY` · `ARCHITECTURE` · `DATABASE` · `RUNTIME` · `RESILIENCE` · `OBSERVABILITY` · `PRIVACY` · `QUALITY` · `DEPLOYMENT` · `BACKUP/RECOVERY` · `DOCUMENTATION`

Decisão final:
- **GO** — nenhum gate BLOCKED.
- **CONDITIONAL GO** — nenhum BLOCKED, ≥1 WARNING, riscos assinados em `.accept-risk.md`.
- **NO-GO** — ≥1 BLOCKED, qualquer que seja a contagem de crit/high.

**Arquivos**:
- Novo `pipeline/06b-release-gates.md`.
- Novo `templates/checks/check-release-gates.sh` — agrega `.blindar/results/*.json` e emite `.blindar/gates.json`.
- Editar `templates/checks/check-termination.sh`: termination passa a exigir gates, não só severidade.
- Editar `SKILL.md` §Termination e §Quality gates.
- Editar `templates/sec.html` + `client-report.html`: bloco de gates no topo.

**Regra dura**: `BACKUP/RECOVERY` só vai a PASS com **restore testado**, não com backup existente. Idem `DEPLOYMENT` — exige rollback provado.

**Aceite**: projeto sintético com 0 crit + SQLite em prod resulta em NO-GO.

---

### Fase 4 — Decision Log + Change Impact + Risk Engine (v0.54)

**Dor**: Claude desfaz em outra sessão uma decisão arquitetural tomada antes. E altera coisa cara sem medir impacto.

- **Decision Log** — `.blindar/decisions.md` (append-only, hash chain como o audit). Formato ADR: problema, alternativas, decisão, motivo, consequências. Toda escolha de engine, fila, provider de IA, estratégia de tenancy e deploy entra.
- **Change Impact Analysis** — antes de round que toque schema, auth, fila, infra ou tenancy: lista arquivos, módulos, migrations, testes, docs e deploy afetados.
- **Risk Engine** — classifica o round em `LOW | MEDIUM | HIGH | CRITICAL` por (dados afetados × reversibilidade × ambiente × downtime). `HIGH`/`CRITICAL` **pausam e pedem autorização mesmo em modo AUTO**.

**Arquivos**:
- Novo `agents/decision-log.md`, `agents/change-impact.md`.
- Novo `templates/checks/check-decision-log.sh` — falha se decisão arquitetural detectada no diff não tem ADR correspondente.
- Editar `pipeline/04-rounds-loop.md` — risk gate antes de aplicar round.
- Editar `SKILL.md` §Modos: documentar que AUTO ≠ irrestrito.

**Aceite**: round que dropa coluna em modo AUTO pausa.

---

### Fase 5 — Camada Runtime/DAST nativa (v0.55)

**Dor**: "o código diz que está protegido" ≠ "a aplicação em execução está protegida". Hoje há recon passivo e pentest ativo, mas não há crawling autenticado nem confronto código × runtime.

Incorpora conceitos do Sentinela — **conceito, não cópia de código**:

- Crawling + descoberta de rotas/endpoints reais.
- Sessão autenticada e não-autenticada, lado a lado.
- Testes vivos: SQLi, XSS, command injection, headers, CORS, cookies, `localStorage`/`sessionStorage`, exposição de config.
- **Confronto**: para cada defesa que o SAST afirmou existir, o runtime confirma ou derruba. Divergência vira finding de severidade elevada — mentira do código é pior que ausência de defesa.

**Arquivos**:
- Novo `agents/runtime-adversarial.md`.
- Estender `scripts/pentest-active.sh` com crawl autenticado (mantém o gate `.blindar/.accept-authorization`).
- Novo `templates/checks/check-static-runtime-divergence.sh`.
- `MODULE-MAP.json`: reforça módulos 18/19.

**Trava**: nada disso roda contra host que não seja localhost/staging sem autorização explícita em arquivo. Mantém a política atual do módulo 19.

---

### Fase 6 — Deployment target e handoff para o Ancorar (v0.56)

**Dor**: preparar para VPS hoje é implícito.

**Correção sobre a proposta externa** (item 26 do ChatGPT): ele propôs "Blindar define o estado desejado, Ancorar executa", tratando o Ancorar como provider consumido pelo Blindar. Isso **inverte a seta** e viola o contrato de isolamento que o próprio Ancorar declara inegociável (`ancorar/SKILL.md` §Contrato de isolamento, v0.2.0):

> Escreve **só** em `.ancorar/`. Nunca em `.blindar/`. **Não edita** um byte de `~/.claude/skills/blindar/**`. O único código do blindar que invoca é `scripts/smoke-run.sh` (via `--url`), read-only.

O Ancorar já é **skill irmã**, não submódulo, e já tem pipeline próprio de 10 fases (inventário → design → backup → baseline → provisionar → migrar → cutover → runtime truth → co-inquilinos → decommission → ops contínua), 16 checks server-side via SSH, schema próprio (`ancorar/check-result@v1`) e default SUPERVISIONADO + dry-run — oposto ao AUTO do Blindar.

**Divisão de responsabilidade que já está certa e não se mexe**:

| | blindar | ancorar |
|---|---|---|
| Pergunta | "esse código pode ir pro ar?" | "o que está no ar está rodando, seguro e reversível?" |
| Escopo | código | operação/host |
| Default | AUTO | SUPERVISIONADO + dry-run |
| Escreve em | `.blindar/` | `.ancorar/` |
| Costura | expõe `scripts/smoke-run.sh` | consome `smoke-run.sh --url` (Fase 7) |

**O que a Fase 6 faz, então** — só o lado do Blindar, sem tocar no Ancorar:

- Novo `pipeline/10-deployment-target.md` — abstração `target: vps | docker-compose | k8s | cloud`, define **estado desejado** e para aí.
- Novo `agents/deployment-readiness.md` — emite `.blindar/deployment-plan.json` (artefatos, env, volumes, migrations, healthcheck, restart policy, rollback, backup, TLS, reverse proxy, firewall) como **artefato de handoff passivo**.
- Novo `templates/checks/check-vps-readiness.sh` — alimenta o gate `DEPLOYMENT` da Fase 3.
- **Não** criar adaptador que invoque o Ancorar. O Blindar publica o artefato; quem decide lê é o Ancorar, se e quando quiser. Direção da dependência permanece ancorar → blindar.
- Manter `scripts/smoke-run.sh` com contrato estável: é API pública consumida por outra skill. Qualquer mudança de assinatura vira breaking change e entra no Decision Log (Fase 4).

**Não-objetivos explícitos**: não duplicar os 16 checks de host do Ancorar dentro do Blindar; não escrever em `.ancorar/`; não fundir as skills.

**Observação lateral**: `ancorar/VERSION` diz `0.2.0` mas o frontmatter de `ancorar/SKILL.md` diz `version: 0.1.0`. Divergência no repo do Ancorar — reportar lá, não corrigir daqui.

---

### Fase 7 — Hierarquia de agentes e consolidação (v0.57)

**Dor**: 109 agentes chapados; quando `performance` quer Redis e `security` exige TLS+auth+rede isolada e `db-architect` diz que o cache não deve existir, ninguém arbitra.

**Camada de metadata, sem mover arquivo** — cada `agents/*.md` ganha frontmatter `lead:` e `authority:`:

| Lead | Cobre |
|---|---|
| `chief-architect` | Arbitra conflito entre leads, define target architecture, aprova ADR |
| `security-lead` | access-control, cryptography, security, supply-chain, secrets |
| `data-lead` | db-architect, backup-recovery, db-migration-guardian, multi-region |
| `platform-lead` | devops, infra-runtime, deployment-provider |
| `sre-lead` | observability, resilience, scalability, chaos |
| `runtime-lead` | pentest, attack-recon, runtime-adversarial, smoke-runtime |
| `privacy-lead` | compliance-* , log-ops-retention |
| `ai-lead` | ai-llm-safety, rag-quality, vector-db-security, prompt-injection, fine-tune-leak |
| `qa-lead` | functional-e2e, testing-strategy, visual-regression |
| `release-lead` | release gates, delivery-bundle, execution-report |

Só `chief-architect` é agente novo. Os demais são papéis atribuídos a agentes existentes.

**Consolidação**: auditar os 109 e classificar `KEEP | MERGE | REFACTOR | REMOVE`. Toda remoção exige justificativa no Decision Log. Meta realista: reduzir 10–15% por fusão de sobreposição, não corte cego.

**Também**: níveis de permissão por agente — `read-only`, `plan`, `implement`, `validate`, `adversary`, `gate`. `gate` bloqueia entrega mas não edita.

---

### Fase 8 — Relatórios, evidência e fechamento (v0.58)

- **Princípio de evidência** vira regra dura em todos os relatórios: proibido "PostgreSQL configurado"; obrigatório "PostgreSQL detectado em X, usado por Y, migration Z, runtime validado por W".
- Novo `templates/checks/check-evidence-claims.sh` — falha se relatório afirma sem citar arquivo/linha/comando.
- `execution-report.html` ganha: modo usado, gates, decisões (ADR), impacto, riscos remanescentes, o que **não** foi alterado e por quê.
- Atualizar `README.md`, `SKILL.md`, `ROADMAP.md`, `CHANGELOG.md`, `docs/V1.0-PATH.md`.

---

## 3. Ordem, custo e risco

| Fase | Versão | Dor que resolve | Risco de regressão | Depende de | Status |
|---|---|---|---|---|---|
| 1 Modos | v0.51 | Projeto do zero / quebrado | Médio (mexe no launcher) | — | ✅ entregue em v0.53.0 |
| 2 DB Guardian + Parity | v0.52 | **Dor #1 do operador** | Baixo (aditivo) | 1 | ✅ entregue em v0.53.0 |
| 3 Release Gates | v0.53 | "Pronto" sem estar pronto | Médio (muda termination) | 2 | ✅ entregue em v0.53.0 |
| 4 Decision Log + Risk | v0.54 | Decisão desfeita / mudança cega | Baixo | 3 | pendente |
| 5 Runtime/DAST | v0.55 | Código mente sobre defesa | Médio (falso positivo) | 3 | pendente |
| 6 Deployment/Ancorar | v0.56 | VPS implícita | Baixo | 3 | pendente |
| 7 Hierarquia | v0.57 | Conflito sem árbitro | **Alto** (toca 111 arquivos) | 4 | pendente |
| 8 Evidência/relatórios | v0.58 | Afirmação sem prova | Baixo | todas | pendente |

As Fases 1–3 saíram numa única release (v0.53.0) por serem interdependentes: os
gates da Fase 3 consomem os checks da Fase 2, que mudam de comportamento
conforme o modo da Fase 1.

**Achado durante a Fase 3, registrado por ser contraintuitivo**: a primeira
versão do `check-release-gates.sh` emitia `GO` com as 11 dimensões vazias —
"nenhum check rodou" era lido como "nenhum problema encontrado". Foi corrigido
com o estado `NOT VERIFIED` (conta como warning) e com a regra de que zero
resultados é `NO-GO`. Vale como lição geral do plano: **toda agregação precisa
distinguir "medi e estava bom" de "não medi"**, e o default do desconhecido
nunca pode ser o valor bom.

Fase 7 é a de maior risco e vem tarde de propósito. Se o tempo apertar, as Fases 1–4 já entregam a maior parte do valor.

---

## 4. Propagação dev → instalada

Não há passo manual. `scripts/sync-skill.sh` já é a ponte, com file-set = arquivos tracked pelo git, remoção de órfãos e preservação de `.git/`, `.blindar/`, `.last-check` no destino.

Por fase, na ordem:

1. Implementar e commitar **neste repo** (`C:\Users\Acer\Documents\Axial\Blidar`).
2. `bash tests/run-tests.sh` — fixtures good/bad da fase precisam passar.
3. `bash scripts/validate.sh` — schemas e MODULE-MAP coerentes.
4. `bash scripts/sync-skill.sh` — propaga para `~/.claude/skills/blindar`.
5. `bash scripts/sync-skill.sh --check` — confirma drift zero.
6. Bump `VERSION` + `CHANGELOG.md` + tag.

**Atenção Windows**: `Edit` reescreve CRLF nos `.sh`; conferir `.gitattributes` após editar check novo.
**Atenção push**: `git push` neste repo exige HTTP/1.1 (`git config http.version HTTP/1.1`). GitHub está em v0.46 — há push pendente acumulado antes de começar a Fase 1.

---

## 5. Pré-requisitos — resolvidos

1. ~~Gap GitHub × local~~ — **não existia**. `origin/main` sempre esteve em `5df48fb` = v0.50.0. O que faltava eram as **tags**: última numérica era `v0.42.0`. Tag `v0.50.0` criada e enviada. As releases v0.43–v0.48 não têm commit `chore(release)` correspondente no histórico, então não são taguáveis retroativamente sem escolher commit à mão — fica como decisão do operador se vale a pena.
2. ~~Ler o Ancorar~~ — **lido** (repo privado, acessível via `gh`). Contrato incorporado na Fase 6, que foi reescrita: a proposta externa invertia a direção da dependência.
3. `modelo_agente_tarefa_cloude.md` — identificado: é o **blueprint do padrão agentic-harness**, 1633 linhas, um meta-documento que ensina a construir uma skill Claude Code no molde do próprio Blindar (playbooks + checks determinísticos + wrappers de API + wrapper de scanner + orquestrador + gate + schema + SARIF + CLI). Não é conteúdo de runtime do Blindar — é o Blindar generalizado em template. Ver §6.

---

## 6. Destino do `modelo_agente_tarefa_cloude.md`

**O que é**: blueprint reutilizável para criar qualquer skill no padrão agentic-harness. Faz 5 perguntas ao operador (nome, propósito, triggers, agentes iniciais, categorização por tipo de check) e gera a estrutura completa. Documenta os padrões canônicos: frontmatter de agente, `MODULE-MAP.json`, check determinístico, wrapper `.api.sh`, wrapper de scanner externo, `_lib.sh`.

**Por que não pertence ao repo do Blindar**: o Blindar é *uma instância* desse padrão. Manter o molde dentro da peça moldada inverte a relação e infla a skill — 63KB que são carregados/sincronizados sem nunca serem usados em runtime pelo pipeline.

| Opção | Avaliação |
|---|---|
| Virar skill própria `~/.claude/skills/agentic-harness/` | **Recomendada.** É exatamente o caso de uso: você invoca quando quer criar a próxima skill. Sobrepõe parcialmente com `anthropic-skills:skill-creator`, mas o seu é opinado no padrão que você já validou. |
| Mover para `docs/` do Blindar | Aceitável, mas continua sendo sincronizado para a skill instalada sem propósito de runtime. |
| Deletar | Não. É o destilado de ~50 versões de aprendizado. |

**Ação proposta**: extrair para skill própria antes da Fase 1, e remover da raiz do Blindar. Fora do escopo das 8 fases — é limpeza de pré-requisito.
