# Roadmap

Lista honesta do que ficou de fora da v0.5.0 e por quê. Ordem por impacto.

## Tier 1 — alta prioridade (fast-follow)

### Bash scripts para Linux/macOS
Equivalentes de `install.ps1`, `check-update.ps1`, `release.ps1`,
`preflight.ps1` em `.sh`. Bloqueia adoção fora de Windows.

**Por que não fiz agora**: priorizei contratos (schemas + state file) que
funcionam em qualquer OS. Scripts são mecânicos — fast-follow.

### Examples directory
`examples/` com 2-3 projetos pequenos blindar-ados — um Python+Flask, um
Node+Express, um SPA React. Antes/depois + sec.html final visível.

**Por que não fiz**: exigiria criar projetos reais funcionais. Trabalho
grande, valor depende de uso real. Vai depois de feedback de adoção.

### Minimal mode (`--minimal`)
Para projetos < 5k LOC, pular discovery completa e ir direto pra rounds
baseados em template de ATKs comuns por stack.

**Por que não fiz**: prematura otimização. Precisa observar qual é o
overhead real em projeto pequeno antes de simplificar.

## Tier 2 — média prioridade

### Dry-run mode
`blindar --dry-run` simula sem criar branches/PRs/commits. Confiança
antes do primeiro uso real.

**Por que não fiz**: o flag está no schema de config; falta implementação
no orquestrador (Claude Workflow). Vai junto com primeiro uso real.

### CI para validar PRs no próprio repo do skill
Markdown lint, validação de schemas, syntax check de `.ps1`, link checker.

**Status**: `lint.yml` simples adicionado na v0.5.0. Mais robustez fast-follow.

### sec.html schema versionado + migrator
Hoje schema do sec.html é estável mas informal. Se mudar entre versões
maiores, projetos com sec.html antigo quebram.

**Por que não fiz**: schema ainda não mudou. Quando mudar, vira urgência.

### Telemetria opt-in
Endpoint para entender qual stack/framework é mais usado, onde rounds
travam, qual fase mais demora. Estritamente opt-in, anônimo.

**Por que não fiz**: política — preferi não introduzir endpoint hoje.
Reabrir se demanda surgir.

## Tier 3 — futuro distante

### Multi-projeto / monorepo
Hoje skill assume 1 projeto = 1 ciclo. Monorepos com vários packages
exigem coordenação que ainda não modelei.

### "Skip rules" inferidas automaticamente
Hoje precisa setar `config.yml > skip_agents`. Skill devia inferir do
discovery (ex: zero endpoints → pular `network-security`).

### Schemas de output de cada agent
Cada agent.md devia ter schema de "saída de round" — diff aplicado +
testes + grep + sec.html update — pra automação de PR comments.

### Plugin de IDE
Extensão VSCode/JetBrains que renderiza sec.html no editor e mostra
gaps inline.

### Coverage report multi-framework simultâneo
Hoje config aceita 1 framework alvo. Empresas reais costumam perseguir
2-3 ao mesmo tempo (ISO + SOC2, por exemplo).

## Gaps não-técnicos

### Comunidade / divulgação
Sem blog post, sem changelog público, sem video demo. Adoção depende
disso eventualmente.

### Manutenção long-term
Quem mantém o skill após a v0.5.0? Sustentação precisa de plano —
mesmo que seja "responde issues quando aparecem, sem SLA".

### Versão em outros idiomas
Skill é PT-BR + EN misturado. Comunidade global precisaria EN-only ou
i18n estruturada.

## Como contribuir com algum desses

Abrir issue em
[github.com/pretinhuu1-boop/blindar/issues](https://github.com/pretinhuu1-boop/blindar/issues)
com:
- Qual item do roadmap
- Por que importa pro seu caso
- Disposição de submeter PR vs só sugerir

PRs bem-vindos, especialmente em Tier 1 e Tier 2. Veja
[`CONTRACT.md`](CONTRACT.md) pros contratos de extensão.
