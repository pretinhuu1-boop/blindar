# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/).
Versionamento [SemVer](https://semver.org/lang/pt-BR/).

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
