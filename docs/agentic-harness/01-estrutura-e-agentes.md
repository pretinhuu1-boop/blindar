## Estrutura de pastas obrigatória

```
~/.claude/skills/<NOME>/
├── SKILL.md                       # manifesto Anthropic (frontmatter ativa skill)
├── VERSION                        # semver puro: 0.1.0
├── CHANGELOG.md                   # Keep-a-Changelog format
├── README.md                      # 1 página: GETTING-STARTED
├── GETTING-STARTED.md             # uso rápido (30s, 1min, comandos essenciais, escopos)
├── docs/
│   ├── BASH-COMPAT.md             # política de compat bash 3.2/4+
│   └── V1.0-PATH.md               # roadmap LTS
├── pipeline/
│   ├── MODULE-MAP.json            # FONTE DA VERDADE: módulos → agentes → fases
│   ├── 00-launcher.md             # 5 perguntas + menu de módulos
│   └── 0N-<fase>.md               # fases sequenciais
├── agents/
│   └── <agente>.md                # PLAYBOOK markdown com frontmatter
├── schemas/
│   ├── check-result.schema.json   # valida .blindar/results/check-*.json
│   ├── run-report.schema.json     # valida .blindar/run-report.json
│   └── intelligence.schema.json   # valida .blindar/intelligence.yml
├── templates/checks/
│   ├── _lib.sh                    # logging + add_finding + emit_result + rg fallback
│   ├── _api_wrapper.sh            # função api_check (Claude API tool_use)
│   ├── check-<agente>.sh          # DETERMINÍSTICO (shell + grep, sem LLM)
│   ├── check-<agente>.api.sh      # API-WRAPPED (precisa de julgamento LLM)
│   └── check-<scanner>.sh         # WRAPPER de scanner externo (Semgrep/OSV/Trivy/Gitleaks)
├── scripts/
│   ├── <NOME>-run.sh              # ORQUESTRADOR ÚNICO (entrypoint mandatório)
│   ├── <NOME>-evolve.sh           # orquestrador secundário (módulo evolução, opt-in)
│   ├── <NOME>-fix.sh              # killer: LLM gera patch+teste+PR de findings
│   ├── sarif-converter.js         # converte result.json → SARIF 2.1.0
│   ├── validate-schemas.js        # valida outputs runtime (AJV opcional, fallback manual)
│   └── install.sh                 # instala scripts em projeto-alvo (opcional)
├── cli/
│   ├── bin/<NOME>.js              # CLI Node ZERO DEPS (parseArgs nativo + ANSI manual)
│   ├── lib/colors.js              # cores ANSI sem kleur/chalk
│   └── commands/*.js              # check, init, version, help, fix, etc.
├── tests/
│   ├── run-tests.sh               # roda fixtures contra checks
│   └── fixtures/<caso>/           # projetos golden (bom/ruim) por agente
├── action.yml                     # GitHub Action composta (opcional)
└── .gitignore                     # ignora outputs transientes (.<NOME>/)
```

---

## Por que cada tipo de arquivo

| Tipo | Por quê existe | Quando criar |
|---|---|---|
| **`.md` em `agents/`** | Playbook lido por Claude — instruções, exemplos, anti-padrões | Lógica que exige julgamento LLM real |
| **`.sh` em `templates/checks/`** | Roda sem LLM, grep + JSON, exit code claro | Validação possível via regex/AST/comando |
| **`.api.sh` em `templates/checks/`** | Shell coleta evidência → curl pra API com tool_use forçando JSON | Julgamento estruturado e auditável (caro mas garantido) |
| **`.sh` que WRAPS scanner externo** (Semgrep/OSV/Trivy/Gitleaks) | Integra ferramenta profissional, traduz output → padrão da skill | Quando existe scanner consagrado pro domínio |
| **`SKILL.md`** | Único arquivo que Claude Code lê pra ativar a skill | Sempre, com frontmatter `name`/`description`/`triggers` |
| **`MODULE-MAP.json`** | Fonte da verdade módulo→agente→fase | Consumido por orquestrador + launcher |
| **`scripts/<NOME>-run.sh`** | Entrypoint mandatório declarado no `SKILL.md` | Garante determinismo (não depende de Claude lembrar) |
| **`scripts/<NOME>-evolve.sh`** | Orquestrador SEPARADO pro módulo de evolução de produto | Escopo diferente do hardening — opt-in via launcher |
| **`scripts/<NOME>-fix.sh`** | Killer feature: LLM gera patch+teste+PR de finding | Após findings reportados, oferece auto-fix com revisão |
| **`scripts/sarif-converter.js`** | Converte output proprietário → SARIF 2.1.0 | Destrava GitHub Code Scanning, Sonar, Azure DevOps |
| **`scripts/validate-schemas.js`** | Validador runtime dos JSON schemas | Contrato estável: bump silencioso não quebra consumers |
| **`schemas/*.json`** | JSON Schema 2020-12 dos outputs | Fonte da verdade do contrato `<NS>/X@v1` |
| **`cli/bin/*.js`** | Roda fora do Claude Code (npm/CI/local sem Claude) | Zero deps obrigatório pra evitar `npm install` |
| **`action.yml`** | Composite action GitHub | Distribuição CI |
| **`tests/fixtures/`** | Projetos golden bom/ruim por check | Regression test do próprio toolkit |
| **`docs/BASH-COMPAT.md`** | Política de compat bash 3.2/4+ | macOS user precisa saber se vai dar problema |

---

## Frontmatter do `SKILL.md` (formato Anthropic obrigatório)

```yaml
---
name: <NOME>
description: |
  <Frase clara do que a skill faz. 2-3 linhas. Sem fluff.>
triggers:
  - "<NOME>"
  - "<frase natural 1 que ativa>"
  - "<frase natural 2>"
  - "<frase natural 3>"
---
```

Depois do frontmatter, **primeira seção** do SKILL.md deve ser (mandato imperativo — versão validada que IMPEDE Claude de pular passos):

```markdown
## EXECUÇÃO MANDATÓRIA — LEIA ANTES DE TUDO

Quando esta skill for invocada (`<NOME>`, ou triggers acima), você (Claude) DEVE executar EXATAMENTE esta sequência, sem pular, sem perguntar antes de cada passo, sem alternativas:

1. `bash ~/.claude/skills/<NOME>/scripts/<NOME>-run.sh --parallel auto` (ou `--fast` se usuário pediu rápido)
2. Aguardar conclusão (exit code 0-4)
3. Ler `.<NOME>/run-report.json` que foi gerado
4. Ler `.<NOME>/proactive-analysis.md` se existir (análise consultiva nas 8 dimensões)
5. Apresentar ao usuário:
   - Resumo numérico (passed/failed/skipped/deferred/cobertura%)
   - Top 5 findings críticos (severity crit/high)
   - Análise proativa resumida (se gerada)
   - Recomendação de próxima ação

**Você NÃO pode**:
- Rodar agentes individualmente sem o orquestrador
- Pular passos da sequência acima
- "Decidir" que algum agente não é necessário
- Apresentar findings sem antes rodar o orquestrador
- Pular `proactive-analysis` se ANTHROPIC_API_KEY existe

**Se algo falhar**: reporte exit code + arquivo de log, NÃO tente "consertar" rodando outras coisas.

Esta restrição existe porque a skill foi desenhada pra ser determinística e auditável. Pular passos quebra a garantia de cobertura.

Exit codes:
- 0 = PASS (release-ready)
- 1 = CONDITIONAL (deferred — Claude precisa rodar playbooks .md restantes)
- 2 = NO-GO (failed crit/high)
- 3 = STRICT-FAIL (deferred em modo strict)
- 4 = ERRORED (bug em script — reporte bug)

## Módulo evolução (opt-in, escopo separado)

Quando usuário pedir auditoria de produto (não hardening):

\`\`\`bash
bash scripts/<NOME>-evolve.sh
\`\`\`

NÃO entra no fluxo padrão. REQUER ANTHROPIC_API_KEY.
```

**Por que o mandato é imperativo**: versões anteriores diziam "PRIMEIRA AÇÃO é..." mas a redação permitia Claude interpretar livremente. Validação em uso real mostrou que Claude pulava passos ou inventava sequências. A versão atual ("você DEVE / você NÃO pode" + proibições explícitas) impede isso.

---

## Frontmatter dos agentes em `agents/<agente>.md`

```yaml
---
name: <agente>
category: <core|evolution|meta|vertical>
module: <id-no-MODULE-MAP>
priority: P0|P1|P2
description: |
  <Missão do agente em 2-3 linhas.>
---

# Agent: <agente>

## Missão
<Por que existe. Custo do problema se não rodar.>

## Procedimento
<Passos detalhados. Pode incluir comandos sugeridos.>

## Output esperado
<JSON estruturado via tool_use OU result.json no padrão da skill.>

## Anti-padrões
- ❌ <coisas a evitar>
```

---

## Padrão de `MODULE-MAP.json`

```json
{
  "$schema": "schemas/module-map.schema.json",
  "version": "0.1.0",
  "description": "Mapa estruturado dos módulos → agentes → fases",
  "modules": {
    "1": {
      "name": "<Nome do módulo>",
      "mandatory": true,
      "skip_token": "always-on",
      "agents": ["<agente-1>", "<agente-2>"],
      "phases": ["00-launcher", "01-discovery"]
    },
    "2": {
      "name": "<Outro módulo>",
      "mandatory": false,
      "default_on_when": ["ui_detected", "project_type:saas"],
      "agents": ["<agente-3>", "<scanner-wrapper>"],
      "phases": ["02-rounds-loop"]
    },
    "16": {
      "name": "Product Evolution (opt-in, escopo separado)",
      "mandatory": false,
      "default_on_when": [],
      "agents": ["<evolution-agent-1>", "<evolution-agent-2>"],
      "phases": ["07-evolution"],
      "entrypoint": "scripts/<NOME>-evolve.sh"
    }
  }
}
```

---

