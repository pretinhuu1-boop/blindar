---
name: blindar
description: |
  Audita, blinda, otimiza e prepara o projeto para produção. Roda autônomo:
  baseline → discovery (3 agentes paralelos) → bootstrap sec.html → rounds
  pequenos (cada um = 1 PR mergeado) → adversarial review a cada 10 rounds
  → production checklist → relatório. Mantém sec.html como dashboard vivo.
  Termina quando: 0 crit + ≤2 high após review adversarial. Sem perguntar
  nada, sem pausar, sem pedir confirmação.

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
- **Adversarial review** (Fase 4) tem lens `security` obrigatório, mesmo
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

Invocado → executa do início ao fim sozinho. Não pede confirmação. Não pausa
entre fases. Reporta status só ao terminar (ou ao bater gate bloqueante).

Operador acompanha em tempo real abrindo `sec.html` no browser.

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

## Pipeline (sequencial, sem perguntar)

| Fase | Arquivo | Duração |
|---|---|---|
| 0 — Baseline | [`pipeline/00-baseline.md`](pipeline/00-baseline.md) | ~2 min |
| 1 — Discovery | [`pipeline/01-discovery.md`](pipeline/01-discovery.md) | ~3 min |
| 2 — Bootstrap sec.html | [`pipeline/02-bootstrap-sec-html.md`](pipeline/02-bootstrap-sec-html.md) | ~1 min |
| 3 — Loop de rounds | [`pipeline/03-rounds-loop.md`](pipeline/03-rounds-loop.md) | até termination |
| 4 — Adversarial review | [`pipeline/04-adversarial-review.md`](pipeline/04-adversarial-review.md) | ~10 min (a cada 10 rounds) |
| 5 — Production checklist | [`pipeline/05-production-checklist.md`](pipeline/05-production-checklist.md) | ~3 min |
| 6 — Relatório final | [`pipeline/06-final-report.md`](pipeline/06-final-report.md) | ~2 min |
| 7 — **Maintenance** (opt-in, trimestral) | [`pipeline/07-maintenance.md`](pipeline/07-maintenance.md) | ~5 min |
| 8 — **Drift detection** (subfase de 7) | [`pipeline/08-drift-detection.md`](pipeline/08-drift-detection.md) | ~3 min |

## Roster de agentes

Agentes de **segurança** (sempre carregados primeiro):

| Categoria | Agente |
|---|---|
| Controle de acesso (auth/MFA/RBAC) | [`agents/access-control.md`](agents/access-control.md) |
| Criptografia (TLS / at-rest / secrets) | [`agents/cryptography.md`](agents/cryptography.md) |
| Segurança aplicacional geral | [`agents/security.md`](agents/security.md) |
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
| Resiliência (threads/breakers/pools) | [`agents/resilience.md`](agents/resilience.md) |
| Escalabilidade (10x carga) | [`agents/scalability.md`](agents/scalability.md) |
| Compliance genérico | [`agents/compliance.md`](agents/compliance.md) |
| LGPD / ANPD (Brasil) | [`agents/compliance-lgpd-br.md`](agents/compliance-lgpd-br.md) |
| DevOps / CI/CD / boot scripts | [`agents/devops.md`](agents/devops.md) |
| Adversarial review (Fase 4) | [`agents/adversarial-reviewer.md`](agents/adversarial-reviewer.md) |

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

Discovery (Fase 1) detecta se projeto declara um framework alvo
(`.compliance-target`, `README`, `package.json`) e gera coverage report
no relatório final (Fase 6).

## Templates

- [`templates/sec.html`](templates/sec.html) — dashboard single-file
- [`templates/accept-risk.md`](templates/accept-risk.md) — riscos aceitos
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
- [ ] Production checklist Fase 5 ✓
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
