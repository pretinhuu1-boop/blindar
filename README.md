# blindar

Skill do [Claude Code](https://claude.com/claude-code) que **audita, blinda,
otimiza e prepara projetos para produção** — e também sabe criar projetos
novos do zero, gerar/refazer frontend lendo o backend, e entregar pacote
completo (DEPLOY/MANUAL/API/Postman/diagramas/SLA) ao final.

**v0.46 — 114 agentes em 19 módulos numerados, com camada determinística
(92 checks executáveis) que garante cobertura independente da diligência do LLM.**

Comportamento: **launcher curto** no início (4 perguntas + menu de
19 módulos, ≤30s) → roda autônomo até termination conforme modo escolhido:

- **AUTO** — vai do início ao fim sem pausar (default)
- **SUPERVISIONADO** — pausa entre rounds
- **ESCOLHIDOS** — roda só os módulos numerados selecionados

Pipeline interno: launcher → strategic-scan → baseline → discovery
(3 agentes paralelos) → bootstrap `sec.html` → rounds pequenos (1 PR cada,
≤80 LOC) → adversarial review a cada 10 rounds → production checklist →
relatório final + delivery bundle.

Mantém `sec.html`, `blindar-report.html` (técnico) e `client-report.html`
(benefício pro cliente) na raiz do projeto.

Termina quando: **0 crit + ≤2 high** após review adversarial (ou módulos
selecionados completos em modo ESCOLHIDOS).

## Recursos chave da v0.46

- **19 módulos numerados** — operador escolhe "tudo", "defaults", "1,3,5", "1-8" ou "tudo menos 13,14"
- **3 modos de execução** — AUTO / SUPERVISIONADO / ESCOLHIDOS
- **114 agentes especialistas** em segurança, frontend, banco, API, performance, compliance, AI, payments, etc.
- **Camada determinística** — 92 checks executáveis (`templates/checks/`) + gate `check-selftest` (60/60 pares fixture-verificados) que provam que cada check dispara no vulnerável e cala no limpo. Cobertura garantida mesmo em modo AUTO.
- **Grafo de conhecimento nativo** ([`scripts/graph-build.js`](scripts/graph-build.js)) — construído 1× na discovery, reusado por todos os agentes (mais cobertura, menos tokens)
- **Smoke / Runtime Truth** ([`scripts/smoke-run.sh`](scripts/smoke-run.sh)) — sobe o stack em homolog e prova que a app boota + responde `/health` antes de qualquer "verde"
- **Intelligence system** ([`schemas/intelligence.schema.json`](schemas/intelligence.schema.json)) — agentes consultam `.blindar/intelligence.yml` pra evitar falso positivo
- **Frontend generator com aprovação** — 3 portões (preview HTML + decisões + confirmação) antes de tocar em qualquer arquivo
- **Project bootstrap** — cria projeto novo do zero (Next.js 15 / NestJS / Postgres / Stripe / etc.)
- **Delivery bundle** — gera pasta `release/` com DEPLOY, MANUAL, API docs, Postman collection production-ready, diagramas Mermaid, SLA, checklist go-live
- **2 relatórios HTML cumulativos** — técnico (timeline + módulo + agente) e cliente (por categoria de benefício, linguagem amigável)

## Instalação

### Windows (PowerShell)

```powershell
# clone direto pra pasta de skills
git clone https://github.com/pretinhuu1-boop/blindar.git "$env:USERPROFILE\.claude\skills\blindar"
```

Ou com o script:

```powershell
iwr -useb https://raw.githubusercontent.com/pretinhuu1-boop/blindar/main/scripts/install.ps1 | iex
```

### Linux / macOS

```bash
git clone https://github.com/pretinhuu1-boop/blindar.git ~/.claude/skills/blindar
```

Depois de instalar, leia o [`CHECKLIST.md`](CHECKLIST.md) e marque os passos.

## Uso

Em qualquer projeto Git:

```
blindar
```

ou um dos triggers: `blinda este projeto`, `deixa pronto pra produção`,
`production ready`, `harden this project`.

O skill abre `sec.html` na raiz — abra no browser pra acompanhar em tempo real.

**Guia completo passo-a-passo: [`USAGE.md`](USAGE.md)** — inclui pré-requisitos,
o que esperar durante a execução, casos especiais (LGPD/PCI), como parar e
retomar, troubleshooting, e como rodar em outras AIs.

## Estrutura do repositório

```
blindar/
├── SKILL.md              ← orquestrador (security-first + multi-agente)
├── MULTI-AI.md           ← como rodar em qualquer AI (não só Claude Code)
├── VERSION               ← versão semântica
├── CHANGELOG.md          ← histórico de mudanças
├── CHECKLIST.md          ← validação pós-download
├── README.md             ← este arquivo
│
├── pipeline/             ← Fase 00 launcher + 10 fases (00-09) + MODULE-MAP.json
│   ├── 00-launcher.md           ← 4 perguntas + menu de 19 módulos
│   ├── 00-strategic-scan.md     ← pre-blindar scan + plano
│   ├── 01-baseline.md
│   ├── 02-discovery.md
│   ├── 03-bootstrap-sec-html.md
│   ├── 04-rounds-loop.md
│   ├── 05-adversarial-review.md
│   ├── 06-production-checklist.md
│   ├── 07-final-report.md
│   ├── 08-maintenance.md        (opcional)
│   ├── 09-drift-detection.md    (opcional)
│   └── MODULE-MAP.json          ⭐ fonte da verdade módulo→agentes (114 agentes em 19 módulos)
│
├── agents/               ← 114 especialistas em 19 módulos numerados
│   │                       Roster completo em SKILL.md ou MODULE-MAP.json.
│   │                       Categorias (frontmatter `category:`):
│   │                       security · frontend · ops · data · compliance ·
│   │                       performance · resilience · quality · cleanup ·
│   │                       dx · ai · payments · scaffolding · delivery · ...
│   └── (114 arquivos .md)
│
├── frameworks/           ← mapeamento controles ↔ agentes (referência)
│   ├── iso-27001.md      ← mais aceito globalmente
│   ├── nist-csf.md       ← operacional, 6 funções v2.0
│   ├── cis-controls.md   ← 18 controles pragmáticos
│   ├── owasp-asvs.md     ← régua de verificação L1/L2/L3
│   ├── pci-dss.md        ← condicional (cobertura pelo agente `compliance-pci-deep`)
│   ├── soc2.md           ← SaaS / B2B
│   └── cobit.md          ← ⚠ stub (governança corporativa)
│
├── runbooks/             ← templates do que NÃO cabe em código
│   ├── antimalware.md          ← #4 EDR/AV (infra de servidor)
│   ├── network-segmentation.md ← parte física da #8
│   ├── security-awareness.md   ← #9 treinamento de usuário
│   └── pentest-schedule.md     ← pentest humano (red team)
│
├── docs/                 ← documentação adicional
│   ├── trends-2026.md          ← curadoria semestral de tendências
│   └── specs/                  ← specs de itens do ROADMAP
│
├── templates/
│   ├── sec.html                 ← dashboard HTML single-file
│   ├── execution-report.html    ← relatório técnico cumulativo
│   ├── client-report.html       ← relatório por benefício (cliente final)
│   ├── frontend-preview.html    ← preview/aprovação do frontend-generator (v0.20)
│   ├── role-hierarchy.md        ← template Master/Admin/Gerencial/Operacional
│   ├── accept-risk.md
│   └── pr-message.md
│
├── stacks.md             ← adaptações por stack
│
├── schemas/              ← JSON schemas (saídas validáveis pra qualquer AI)
│   ├── inventory.schema.json
│   ├── threat.schema.json
│   ├── arch.schema.json
│   ├── findings.schema.json
│   ├── verdict.schema.json
│   ├── state.schema.json        ← .blindar/state.json no projeto-alvo
│   ├── config.schema.json       ← .blindar/config.yml no projeto-alvo
│   ├── plan.schema.json
│   └── intelligence.schema.json ← .blindar/intelligence.yml (whitelist/exceções por agente)
│
├── AI-ENTRYPOINT.md      ← AI lê primeiro (decision tree determinístico)
├── CONTRACT.md           ← estrutura `.blindar/` no projeto-alvo
├── ROADMAP.md            ← o que ficou de fora e por quê
│
├── .github/              ← issue templates, PR template, CI lint
│
└── scripts/
    ├── check-update.ps1  ← compara VERSION local vs remoto (TTL 24h)
    ├── install.ps1       ← instala em ~/.claude/skills/blindar
    ├── preflight.ps1     ← valida pré-reqs no projeto-alvo (1 comando)
    └── release.ps1       ← bump + tag + GH release (uso do dono)
```

## Cobertura

**10 técnicas clássicas de segurança de TI**: 7 cobertas por agente
(access, crypto, network, patch, backup, observability, pentest); 3 por
runbook organizacional (antivírus, segmentação física, conscientização).

**6 frameworks**: ISO 27001, NIST CSF, CIS Controls, PCI-DSS (condicional),
SOC 2, COBIT (stub) — mapeados como tabelas de referência, não código.

**Qualquer AI**: Claude Code roda paralelo nativo; ChatGPT/Gemini/Cursor
rodam sequencial multi-turno (ver [`MULTI-AI.md`](MULTI-AI.md)).

**Sempre multi-agente**: princípio do skill — mesmo em AI single-threaded,
nunca um prompt monolítico.

## Atualização

O próprio skill checa por updates na primeira fase de cada execução (lazy,
TTL 24h, não bloqueante). Se houver versão nova, aparece um aviso
`⚠ blindar v0.X disponível` apontando pro `CHANGELOG.md`.

Pra forçar checagem:

```powershell
& "$env:USERPROFILE\.claude\skills\blindar\scripts\check-update.ps1"
```

Pra atualizar manualmente (se clonou via git):

```powershell
git -C "$env:USERPROFILE\.claude\skills\blindar" pull --ff-only
```

## Para quem é

- Devs que querem **um projeto pronto pra produção sem revisar manualmente
  6 domínios** (segurança, performance, resilience, compliance, supply-chain,
  CI/CD).
- Projetos pós-MVP que precisam fechar gaps antes de escalar.
- Equipes que querem um **dashboard auditável** (sec.html) de tudo que foi
  blindado.

## Para quem NÃO é

- Projetos com suite vermelha (o skill se recusa a rodar).
- Projetos sem CI configurada (o skill se recusa e pede CI mínima primeiro).
- Quem quer pausar/perguntar a cada passo — use code review manual.

## Princípios não-negociáveis

Documentados em [`SKILL.md`](SKILL.md). Resumo: round pequeno + mergível,
`sec.html` é ledger vivo, defesa em código + grep estático, multi-agent
adversarial a cada 10 rounds, CI verde antes de merge.

## Contribuir

Esse skill foi extraído de execução real: 118 rounds, 68 ATKs fechados, 24
findings adversariais fixados. **Regras refletem bugs reais que já
aconteceram.** PRs novos precisam carregar a mesma carga — bug real
observado + teste que falha sem o fix.

## Licença

[MIT](LICENSE) © 2026 pretinhuu1-boop.

Permissiva — uso, modificação, distribuição e uso comercial liberados.
Mantenha o aviso de copyright + a licença em forks/cópias substanciais.
Sem garantia (`AS IS`).
