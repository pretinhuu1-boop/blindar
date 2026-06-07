# blindar

Skill do [Claude Code](https://claude.com/claude-code) que **audita, blinda,
otimiza e prepara projetos para produção** sem pedir confirmação a cada passo.

Roda autônomo: baseline → discovery (3 agentes paralelos) → bootstrap
`sec.html` → rounds pequenos (1 PR cada, ≤80 LOC) → adversarial review a cada
10 rounds → production checklist → relatório final.

Mantém `sec.html` na raiz do projeto como dashboard vivo.

Termina quando: **0 crit + ≤2 high** após review adversarial.

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
├── pipeline/             ← as 8 fases (00 a 07) + 2 opcionais (08-09)
│   └── 00-strategic-scan.md  ⭐ NOVA em v0.7.0 — pre-blindar scan + plano
│
├── agents/               ← especialistas (segurança primeiro, sempre)
│   │ ──── SEGURANÇA (10 técnicas clássicas de TI) ────
│   ├── access-control.md       ← #1 auth, MFA, RBAC, least-privilege
│   ├── cryptography.md         ← #2 TLS, at-rest, secrets, key mgmt
│   ├── security.md             ← genérico (ATKs do catálogo)
│   ├── frontend.md             ← CSP, XSS, Trusted Types
│   ├── network-security.md     ← #3, #8 WAF, rate-limit, IaC SG
│   ├── observability.md        ← #7 logs estruturados, métricas, audit
│   ├── backup-recovery.md      ← #6 backup cifrado + restore testado
│   ├── patch-management.md     ← #5 OS/runtime + Renovate/Dependabot
│   ├── supply-chain.md         ← lockfiles, SHA-pin, gitleaks
│   ├── pentest.md              ← #10 SAST, DAST, SCA, fuzz
│   │
│   │ ──── NÃO-SEGURANÇA (sob demanda) ────
│   ├── performance.md
│   ├── resilience.md           ← threads que não travam / breakers
│   ├── scalability.md          ← ⚠ stub
│   ├── compliance.md           ← audit chain genérico
│   ├── compliance-lgpd-br.md   ← Brasil / ANPD
│   ├── devops.md               ← CI/CD, boot scripts
│   └── adversarial-reviewer.md ← Fase 4
│
├── frameworks/           ← mapeamento controles ↔ agentes (referência)
│   ├── iso-27001.md      ← mais aceito globalmente
│   ├── nist-csf.md       ← operacional, 6 funções v2.0
│   ├── cis-controls.md   ← 18 controles pragmáticos
│   ├── pci-dss.md        ← ⚠ condicional (só se processa cartão)
│   ├── soc2.md           ← SaaS / B2B
│   └── cobit.md          ← ⚠ stub (governança corporativa)
│
├── runbooks/             ← templates do que NÃO cabe em código
│   ├── antimalware.md          ← #4 EDR/AV (infra de servidor)
│   ├── network-segmentation.md ← parte física da #8
│   ├── security-awareness.md   ← #9 treinamento de usuário
│   └── pentest-schedule.md     ← pentest humano (red team)
│
├── templates/
│   ├── sec.html          ← dashboard HTML single-file
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
│   ├── state.schema.json   ← .blindar/state.json no projeto-alvo
│   └── config.schema.json  ← .blindar/config.yml no projeto-alvo
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
