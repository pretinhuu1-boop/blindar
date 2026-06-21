---
name: execution-report
category: reporting
module: 14
priority: P2
description: |
  Mantém `blindar-report.html` na raiz do projeto: relatório cumulativo
  de tudo que blindar fez, agrupado por timeline / módulo / agente.
  Auto-atualizado ao final de cada round e ao final de cada fase. HTML
  self-contained (offline-friendly), com filtros, busca, modo escuro,
  CSS print-friendly e botões pra imprimir/copiar markdown/baixar JSON/
  compartilhar por email. Nunca substitui — sempre apenda.
---

# Agent: execution-report

## Missão

`sec.html` é o **dashboard de segurança** (estado atual). Este agente
mantém um arquivo **separado e cumulativo** — `blindar-report.html` —
focado em **o que foi feito** ao longo do tempo. Operador imprime,
compartilha por email, mostra pra auditor sem ter que dar acesso ao repo.

## Quando rodar

- Módulo 14 selecionado
- Sempre criado na Fase 03 (bootstrap), se ainda não existir
- Atualizado:
  - Ao final de cada round (Fase 04)
  - Após cada adversarial review (Fase 05)
  - Ao final do production checklist (Fase 06)
  - Na geração do relatório final (Fase 07)
  - Em manutenção (Fase 08)

## A. Localização e arquivo

| Arquivo | Onde | Audience | Propósito |
|---|---|---|---|
| `blindar-report.html` | raiz do projeto-alvo | **técnico** (dev/auditor) | Timeline + módulos + agentes + severidades. Detalhado. |
| `client-report.html` | raiz do projeto-alvo | **cliente final / executivo** | Linguagem de benefício, por categoria, sem jargão. |
| `.blindar/report-data.json` | versionado | — | Fonte da verdade. Ambos HTMLs leem o mesmo JSON. |

Os 2 HTMLs leem **o mesmo arquivo de dados** mas renderizam visões
diferentes — um técnico, outro amigável ao cliente. Atualizar 1 atualiza os 2.

O HTML lê os dados do bloco `<script id="blindar-data" type="application/json">`
embutido nele mesmo. Quando atualiza, blindar re-grava o bloco a partir do
`.blindar/report-data.json` (que é apendado, nunca substituído).

## B. Schema do JSON cumulativo

```json
{
  "schema": "blindar/execution-report@v1",
  "project": "Salon Pro 3.0",
  "blindar_version": "0.15.0",
  "first_run": "2026-06-14T18:00:00Z",
  "last_updated": "2026-06-14T19:32:00Z",
  "total_runs": 3,
  "runs": [
    {
      "id": "run-01HX2K9...",
      "started_at": "2026-06-14T18:00:00Z",
      "ended_at": "2026-06-14T18:42:00Z",
      "mode": "auto",
      "modules_selected": [1, 2, 4, 7, 11, 12, 15],
      "rigor": "production",
      "terminated_at_phase": "07-final-report",
      "actions": [
        {
          "ts": "2026-06-14T18:05:23Z",
          "round": 1,
          "module": 2,
          "agent": "auth-premium",
          "severity": "crit",
          "title": "Hash de senha trocado de bcrypt → Argon2id",
          "description": "13 endpoints de auth migrados pra Argon2id. Senhas existentes serão re-hasheadas no próximo login.",
          "files": ["src/auth/hash.ts", "src/auth/migrate-hash.ts"],
          "pr_url": "https://github.com/owner/repo/pull/142",
          "resolved": true,
          "in_accept_risk": false,
          "notes": ""
        },
        {
          "ts": "2026-06-14T18:09:11Z",
          "round": 2,
          "module": 12,
          "agent": "mock-killer",
          "severity": "high",
          "title": "47 console.log removidos de produção",
          "files": ["src/api/*.ts", "src/components/Dashboard.tsx"],
          "resolved": true
        }
      ]
    }
  ]
}
```

### Campos por action

| Campo | Tipo | Obrigatório | Descrição |
|---|---|---|---|
| `ts` | ISO 8601 | sim | Timestamp da ação |
| `round` | int | não | Número do round (se aplicável) |
| `module` | int 1-15 | sim | Módulo do MODULE-MAP |
| `agent` | string | sim | Nome do agente que executou |
| `severity` | enum | sim | crit / high / med / low |
| `title` | string ≤ 80 chars | sim | Headline da ação |
| `description` | string | não | Detalhe expandido |
| `files` | string[] | não | Arquivos tocados |
| `pr_url` | URL | não | Link do PR |
| `resolved` | boolean | sim | Se foi resolvido ou só identificado |
| `in_accept_risk` | boolean | não | Se foi aceito em `.accept-risk.md` |
| `notes` | string | não | Observações livres |

## C. Workflow do agente

### C.1 Primeira execução em projeto novo

```
1. Verifica se templates/execution-report.html existe no skill
2. Copia pra <projeto>/blindar-report.html
3. Copia templates/client-report.html pra <projeto>/client-report.html
4. Cria .blindar/report-data.json com:
   - schema, project (de package.json), blindar_version (de VERSION)
   - first_run = now, last_updated = now, total_runs = 0, runs = []
5. Substitui o bloco <script id="blindar-data"> em AMBOS os HTMLs
6. Commita junto com o sec.html bootstrap (Fase 03)
```

### C.2 Ao final de cada round (Fase 04)

```
1. Lê .blindar/report-data.json
2. Encontra ou cria o run atual em runs[]
3. Apenda action com ts=now, round, module, agent, severity, title, files, pr_url
4. Atualiza last_updated = now
5. Re-grava JSON
6. Re-grava bloco <script id="blindar-data"> em AMBOS os HTMLs
   (blindar-report.html + client-report.html)
7. Commita junto com o PR do round (mesmo commit)
```

### C.3 Ao final da execução (Fase 07)

```
1. Marca run.ended_at = now, run.terminated_at_phase
2. Incrementa total_runs
3. Atualiza last_updated
4. Re-grava
```

### C.4 Cleanup periódico

- Mantém **TODOS** os runs (cumulativo, nunca apaga)
- Se runs[] passar de 1000 entries, agrupa runs antigos (>1 ano) em
  `runs_archive[]` com sumário apenas
- Limite total do JSON: 5MB — acima disso, divide em
  `report-data.json` + `report-data-archive-<ano>.json`

## D. Como blindar ATUALIZA o bloco JSON nos HTMLs

```ts
function updateReportHtmls(projectDir: string, data: ReportData) {
  const newJson = JSON.stringify(data, null, 2);
  const targets = [
    `${projectDir}/blindar-report.html`,
    `${projectDir}/client-report.html`
  ];
  for (const target of targets) {
    if (!fs.existsSync(target)) continue;
    const html = fs.readFileSync(target, 'utf8');
    const updated = html.replace(
      /<script id="blindar-data" type="application\/json">[\s\S]*?<\/script>/,
      `<script id="blindar-data" type="application/json">\n${newJson}\n</script>`
    );
    fs.writeFileSync(target, updated);
  }
}
```

A regex pega exatamente o bloco entre `<script id="blindar-data">` e
`</script>`. Resto do HTML (CSS, JS de render, layout) nunca é tocado.
Operador pode customizar layout de qualquer um dos HTMLs sem perder
dados — e a customização sobrevive aos updates do blindar.

O `client-report.html` tem **um segundo bloco** `<script id="benefit-map">`
que NÃO é atualizado pelo blindar — é a tabela de tradução
"agente técnico → benefício pro cliente". Operador pode editar pra
ajustar a linguagem do produto dele.

## E. Funcionalidades do HTML pro operador

### E.1 Visualizar

- Timeline (mais recente primeiro)
- Agrupado por módulo (1-15)
- Agrupado por agente
- 6 cards de estatística no topo (módulos, agentes, rounds, resolvidos, crits, highs)

### E.2 Filtrar

- Busca livre (em qualquer campo, case-insensitive)
- Por módulo (1-15)
- Por agente
- Por severidade (CRIT / HIGH / MED / LOW / Resolvidos)
- Por período (24h / 7d / 30d / tudo)

Todos os filtros são **client-side** (JS no HTML) — funciona offline,
sem servidor.

### E.3 Exportar / compartilhar

| Botão | O que faz |
|---|---|
| 🖨️ Imprimir / PDF | `window.print()` — abre dialog, salva como PDF, CSS print-friendly esconde controles, expande todos os details |
| 📋 Copiar resumo | Gera Markdown estruturado e copia pra clipboard (cola em email, Slack, doc) |
| 💾 Baixar dados | Download do JSON cru pra backup ou análise externa |
| ✉️ Compartilhar | Abre `mailto:` com subject/body preenchido. Operador anexa o HTML manualmente |

### E.4 Print-friendly (CSS @media print)

- Esconde: botões, filtros, busca
- Expande: todos `<details>` ficam abertos
- Quebra de página: `break-inside: avoid` em cards e details
- Cores: preto e branco amigável, links sublinhados
- Margens: `@page { margin: 1.5cm }`

### E.5 Modo escuro automático

`@media (prefers-color-scheme: dark)` no CSS — segue o sistema do user
sem precisar de toggle.

## F. Integração com outros agentes

Cada agente que executa deve **chamar este agente** ao final do round
passando os campos da action. Pseudo-código:

```ts
// No final de qualquer agente, ao concluir um round
await executionReport.append({
  round: state.current_round,
  module: agent.module,
  agent: agent.name,
  severity: round.findings_severity,
  title: round.summary,
  files: round.changed_files,
  pr_url: round.pr_url,
  resolved: round.merged === true
});
```

`execution-report.md` é **passivo** — não roda lógica própria. Outros
agentes apendam ações conforme acontecem.

## G. Greps obrigatórios (no projeto-alvo)

```bash
# Confirma que HTML existe e tem o bloco
test -f blindar-report.html && grep -q "blindar-data" blindar-report.html

# Confirma que JSON em disco bate com bloco do HTML
diff <(jq . .blindar/report-data.json) \
     <(grep -oP '(?<=<script id="blindar-data" type="application/json">).*?(?=</script>)' blindar-report.html | jq .)

# Validar schema do JSON
node -e "
  const d = require('./.blindar/report-data.json');
  if (d.schema !== 'blindar/execution-report@v1') throw 'schema_mismatch';
  if (!Array.isArray(d.runs)) throw 'runs_not_array';
  d.runs.forEach(r => { if (!r.id || !r.started_at) throw 'run_missing_fields'; });
  console.log('OK');
"
```

## H. Output esperado em sec.html (sumário)

```
┌─ Execution Report (Módulo 14) ───────────────────────────┐
│ blindar-report.html criado    : ✅                         │
│ .blindar/report-data.json     : ✅ válido                  │
│ Total de runs gravados        : 3                          │
│ Total de actions              : 47                         │
│ Resolvidos (cumulativo)       : 41 ✅                      │
│ Open crits                    : 0 ✅                       │
│ Tamanho do HTML               : 24 KB                      │
│ Tamanho do JSON               : 8.2 KB                     │
│ Última atualização            : há 12s                     │
│ Status                        : ✅ ACTIVE                  │
└───────────────────────────────────────────────────────────┘
```

## I. Como o operador usa

### Abrir
```
file:///<projeto>/blindar-report.html
```
ou duplo-clique no arquivo no Explorador.

### Imprimir
Cmd/Ctrl+P → "Salvar como PDF" ou imprimir direto. CSS auto-adapta.

### Compartilhar por email
- Botão "✉️ Compartilhar" → abre cliente de email com subject/body
- Anexa o HTML manualmente (arquivo único, ~25 KB)
- Destinatário abre em qualquer browser, funciona offline

### Comparar entre execuções
Tudo cumulativo na timeline. Filtrar por período mostra evolução.

## J. Anti-padrões

- ❌ Substituir o JSON inteiro (perde histórico)
- ❌ Apagar runs antigos sem arquivar
- ❌ Tocar no HTML que não seja o bloco `<script id="blindar-data">`
- ❌ Não commitar `blindar-report.html` (vira inconsistente entre devs)
- ❌ Putar URLs com tokens/secrets em `pr_url` (cuidar com fork URLs)
- ❌ Permitir XSS via `description` (HTML escape obrigatório — já feito em `esc()` do template)
- ❌ Salvar mais de 1MB no JSON sem particionar (lentidão de render)
- ❌ Servir o HTML em rota pública do app (vaza estrutura interna)
- ❌ Tocar `last_updated` sem incrementar ou apendar nada (mente sobre execução)

## K. Arquivos relacionados

- [`templates/execution-report.html`](../templates/execution-report.html) — template
- [`schemas/state.schema.json`](../schemas/state.schema.json) — referencia
  `blindar-report.html` como saída esperada no projeto-alvo
- [`pipeline/03-bootstrap-sec-html.md`](../pipeline/03-bootstrap-sec-html.md) — cria HTML inicial
- [`pipeline/04-rounds-loop.md`](../pipeline/04-rounds-loop.md) — apenda action por round
- [`pipeline/07-final-report.md`](../pipeline/07-final-report.md) — fecha run no final
