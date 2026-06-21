#!/usr/bin/env bash
# Wrapper API: proactive-analysis — análise consultiva nas 8 dimensões.
# Roda automaticamente ao final de blindar-run.sh. Lê run-report e opina.
# Gera 2 outputs: result.json (padrão) + proactive-analysis.md (legível).
BLINDAR_AGENT="check-proactive-analysis"
source "$(dirname "$0")/_lib.sh"
source "$(dirname "$0")/_api_wrapper.sh"

log_section "Check: proactive-analysis (consultivo, 8 dimensões)"

RUN_REPORT_PATH="${BLINDAR_DIR:-.blindar}/run-report.json"
PROACTIVE_MD="${BLINDAR_DIR:-.blindar}/proactive-analysis.md"

# ─── Pré-condições ────────────────────────────────────────────────────
if [ ! -f "$RUN_REPORT_PATH" ]; then
  log_warn "run-report.json ausente em $RUN_REPORT_PATH — pulando análise proativa"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
  log_warn "ANTHROPIC_API_KEY ausente — análise proativa requer API"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

if ! command -v curl >/dev/null 2>&1; then
  log_warn "curl ausente — pulando"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

if ! command -v node >/dev/null 2>&1; then
  log_warn "node ausente — pulando"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

# ─── Coleta evidência ─────────────────────────────────────────────────
EVIDENCE=""

EVIDENCE+="=== run-report.json (findings agregados) ==="$'\n'
EVIDENCE+="$(head -c 20000 "$RUN_REPORT_PATH")"$'\n\n'

if [ -f "${BLINDAR_DIR:-.blindar}/scan.json" ]; then
  EVIDENCE+="=== scan.json (stack scan) ==="$'\n'
  EVIDENCE+="$(head -c 5000 "${BLINDAR_DIR:-.blindar}/scan.json")"$'\n\n'
fi

if [ -f "README.md" ]; then
  EVIDENCE+="=== README.md (contexto do produto) ==="$'\n'
  EVIDENCE+="$(head -c 3000 README.md)"$'\n\n'
fi

if [ -f "package.json" ]; then
  EVIDENCE+="=== package.json (deps) ==="$'\n'
  EVIDENCE+="$(head -c 3000 package.json)"$'\n\n'
fi

# Sumário: count findings por severity (executivo)
SUMMARY=$(node -e "
try {
  const r = JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));
  const out = {
    total_agents: r.total_agents || 0,
    passed: r.passed || 0,
    failed: r.failed || 0,
    skipped: r.skipped || 0,
    deferred: r.deferred || 0,
    coverage_pct: r.coverage_pct || 0
  };
  console.log(JSON.stringify(out, null, 2));
} catch(e) { console.log('{}'); }
" "$RUN_REPORT_PATH" 2>/dev/null)
EVIDENCE+="=== sumário executivo ==="$'\n'"$SUMMARY"$'\n\n'

# ─── SYSTEM prompt: forçar as 8 dimensões ────────────────────────────
SYSTEM="Você é o agente proactive-analysis do blindar — um CONSULTOR SÊNIOR.

Sua tarefa NÃO é achar bugs novos (outros agentes já fizeram isso).
Sua tarefa é dar uma visão CONSULTIVA do projeto, opinando sobre
riscos não-cobertos pelos checks atuais, oportunidades de melhoria,
trade-offs reais.

Você DEVE responder usando a ferramenta report_dimensions com as
8 DIMENSÕES OBRIGATÓRIAS (todas, mesmo que com lista vazia justificada):

1. security — riscos não-cobertos por checks, ataques possíveis dado o stack, controles ausentes
2. architecture — bounded contexts faltando, acoplamentos perigosos, módulos sugeridos
3. quality — cobertura real, tipos de teste faltantes (unit/integration/e2e/load/chaos), quality gates
4. performance — bottlenecks detectáveis, métricas p95/p99 sugeridas
5. compliance — LGPD/GDPR/HIPAA/PCI gaps específicos da stack
6. accessibility — WCAG/cognitive/keyboard (se UI; vazio se backend puro)
7. costs — cloud spend, LLM tokens, DB queries caras, oportunidades FinOps
8. dx_ops — onboarding dev, runbooks, automações possíveis, gargalos

Para cada dimensão, traga:
- riscos (com severity crit/high/med/low + description + mitigation)
- oportunidades (com roi alto/medio/baixo + description + tradeoffs explícitos + complexity S/M/L + decider CTO/PO/Eng/Compliance/Legal)

PRINCÍPIOS:
- CONCRETO, nunca genérico (cite arquivo/endpoint/dep quando possível)
- TRADE-OFFS explícitos (não só 'use X' — explique o custo real)
- CUSTO realista (S=horas, M=dias, L=semanas+)
- Para backend puro sem UI, accessibility pode ter risks/opportunities vazios"

# ─── Tool definition customizada (schema novo, não o padrão) ──────────
TOOL_DEF='{
  "name": "report_dimensions",
  "description": "Reporta análise consultiva nas 8 dimensões obrigatórias",
  "input_schema": {
    "type": "object",
    "required": ["dimensions"],
    "properties": {
      "dimensions": {
        "type": "array",
        "items": {
          "type": "object",
          "required": ["name", "risks", "opportunities"],
          "properties": {
            "name": {"type": "string", "enum": ["security","architecture","quality","performance","compliance","accessibility","costs","dx_ops"]},
            "risks": {
              "type": "array",
              "items": {
                "type": "object",
                "required": ["severity","description","mitigation"],
                "properties": {
                  "severity": {"type":"string","enum":["crit","high","med","low"]},
                  "description": {"type":"string"},
                  "mitigation": {"type":"string"}
                }
              }
            },
            "opportunities": {
              "type": "array",
              "items": {
                "type": "object",
                "required": ["roi","description","tradeoffs","complexity","decider"],
                "properties": {
                  "roi": {"type":"string","enum":["alto","medio","baixo"]},
                  "description": {"type":"string"},
                  "tradeoffs": {"type":"string"},
                  "complexity": {"type":"string","enum":["S","M","L"]},
                  "decider": {"type":"string","enum":["CTO","PO","Eng","Compliance","Legal"]}
                }
              }
            }
          }
        }
      }
    }
  }
}'

# Truncate evidência (50k chars max)
TRUNCATED=$(echo "$EVIDENCE" | head -c 50000)

MODEL="${BLINDAR_PROACTIVE_MODEL:-claude-haiku-4-5-20251001}"

# ─── Monta payload ────────────────────────────────────────────────────
PAYLOAD=$(node -e "
  const p = {
    model: process.argv[1],
    max_tokens: 8192,
    system: process.argv[2],
    tools: [JSON.parse(process.argv[3])],
    tool_choice: {type: 'tool', name: 'report_dimensions'},
    messages: [{role: 'user', content: process.argv[4]}]
  };
  console.log(JSON.stringify(p));
" "$MODEL" "$SYSTEM" "$TOOL_DEF" "$TRUNCATED" 2>/dev/null)

if [ -z "$PAYLOAD" ]; then
  log_warn "Falha ao montar payload"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

# ─── Chama API ────────────────────────────────────────────────────────
RESPONSE=$(curl -sS --max-time 120 https://api.anthropic.com/v1/messages \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d "$PAYLOAD" 2>/dev/null)

if [ -z "$RESPONSE" ]; then
  log_warn "API call falhou (sem resposta)"
  add_finding "low" "API call não retornou — verifique conexão e API key" "" ""
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

if echo "$RESPONSE" | grep -q '"type":"error"'; then
  ERR_MSG=$(echo "$RESPONSE" | grep -oE '"message":"[^"]*"' | head -1 | sed 's/.*"message":"//;s/"$//')
  log_warn "API error: $ERR_MSG"
  add_finding "low" "API error: $ERR_MSG" "" ""
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

# ─── Extrai tool_use input ────────────────────────────────────────────
RESULT_JSON=$(node -e "
  try {
    const r = JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
    const toolUse = (r.content || []).find(c => c.type === 'tool_use');
    if (!toolUse) { process.exit(0); }
    console.log(JSON.stringify(toolUse.input));
  } catch(e) { process.exit(0); }
" <<< "$RESPONSE" 2>/dev/null)

if [ -z "$RESULT_JSON" ]; then
  log_warn "API não retornou tool_use estruturado"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

# ─── Salva resultado bruto pra inspeção ───────────────────────────────
RAW_OUT="${BLINDAR_DIR:-.blindar}/proactive-analysis-raw.json"
echo "$RESULT_JSON" > "$RAW_OUT"

# ─── Mapeia riscos crit/high → findings (entra na contagem global) ────
N_DIMS=$(node -e "
  try {
    const r = JSON.parse(process.argv[1]);
    console.log((r.dimensions || []).length);
  } catch(e) { console.log(0); }
" "$RESULT_JSON" 2>/dev/null)

i=0
HAS_CRIT_OR_HIGH=0
while [ "$i" -lt "$N_DIMS" ]; do
  DIM_NAME=$(node -e "console.log(JSON.parse(process.argv[1]).dimensions[$i].name || '')" "$RESULT_JSON" 2>/dev/null)
  N_RISKS=$(node -e "console.log((JSON.parse(process.argv[1]).dimensions[$i].risks || []).length)" "$RESULT_JSON" 2>/dev/null)

  j=0
  while [ "$j" -lt "$N_RISKS" ]; do
    SEV=$(node -e "console.log(JSON.parse(process.argv[1]).dimensions[$i].risks[$j].severity || 'low')" "$RESULT_JSON" 2>/dev/null)
    DESC=$(node -e "console.log(JSON.parse(process.argv[1]).dimensions[$i].risks[$j].description || '')" "$RESULT_JSON" 2>/dev/null)
    MIT=$(node -e "console.log(JSON.parse(process.argv[1]).dimensions[$i].risks[$j].mitigation || '')" "$RESULT_JSON" 2>/dev/null)
    if [ "$SEV" = "crit" ] || [ "$SEV" = "high" ]; then
      add_finding "$SEV" "[proactive/$DIM_NAME] $DESC | mitigação: $MIT" "" ""
      HAS_CRIT_OR_HIGH=1
    fi
    j=$((j+1))
  done
  i=$((i+1))
done

# ─── Gera markdown legível com tabelas por dimensão ───────────────────
node -e "
try {
  const r = JSON.parse(process.argv[1]);
  const outFile = process.argv[2];
  const fs = require('fs');
  const dims = r.dimensions || [];

  const dimLabels = {
    security: 'Segurança',
    architecture: 'Arquitetura',
    quality: 'Qualidade & Testes',
    performance: 'Performance',
    compliance: 'Compliance',
    accessibility: 'Acessibilidade',
    costs: 'Custos & FinOps',
    dx_ops: 'DX & Operação'
  };
  const order = ['security','architecture','quality','performance','compliance','accessibility','costs','dx_ops'];

  let md = '# Análise Proativa — blindar\n\n';
  md += 'Gerado em ' + new Date().toISOString() + '\n\n';
  md += 'Relatório consultivo nas 8 dimensões. Não substitui findings — complementa.\n\n';
  md += '---\n\n';

  // Sumário no topo
  md += '## Sumário\n\n';
  md += '| Dimensão | Riscos | Oportunidades | Crit/High |\n';
  md += '|---|---:|---:|---:|\n';
  for (const key of order) {
    const d = dims.find(x => x.name === key);
    if (!d) { md += '| ' + dimLabels[key] + ' | — | — | — |\n'; continue; }
    const ch = (d.risks || []).filter(r => r.severity === 'crit' || r.severity === 'high').length;
    md += '| ' + dimLabels[key] + ' | ' + (d.risks || []).length + ' | ' + (d.opportunities || []).length + ' | ' + ch + ' |\n';
  }
  md += '\n---\n\n';

  // Cada dimensão
  for (const key of order) {
    const d = dims.find(x => x.name === key);
    md += '## ' + dimLabels[key] + '\n\n';
    if (!d) { md += '_(não retornado pelo modelo)_\n\n'; continue; }

    const risks = d.risks || [];
    const opps = d.opportunities || [];

    md += '### Riscos\n\n';
    if (risks.length === 0) {
      md += '_Nenhum risco adicional levantado nesta dimensão._\n\n';
    } else {
      md += '| Severity | Descrição | Mitigação |\n';
      md += '|---|---|---|\n';
      for (const r of risks) {
        const esc = s => String(s || '').replace(/\|/g, '\\\\|').replace(/\n/g, ' ');
        md += '| ' + (r.severity || '') + ' | ' + esc(r.description) + ' | ' + esc(r.mitigation) + ' |\n';
      }
      md += '\n';
    }

    md += '### Oportunidades\n\n';
    if (opps.length === 0) {
      md += '_Nenhuma oportunidade adicional sugerida nesta dimensão._\n\n';
    } else {
      md += '| ROI | Descrição | Trade-offs | Complexity | Decider |\n';
      md += '|---|---|---|---|---|\n';
      for (const o of opps) {
        const esc = s => String(s || '').replace(/\|/g, '\\\\|').replace(/\n/g, ' ');
        md += '| ' + (o.roi || '') + ' | ' + esc(o.description) + ' | ' + esc(o.tradeoffs) + ' | ' + (o.complexity || '') + ' | ' + (o.decider || '') + ' |\n';
      }
      md += '\n';
    }
    md += '\n';
  }

  md += '---\n\n';
  md += '_Gerado pelo agente proactive-analysis (módulo 15). Para regenerar: rode blindar-run.sh novamente._\n';

  fs.writeFileSync(outFile, md, 'utf8');
} catch(e) {
  console.error('Erro ao gerar markdown:', e.message);
  process.exit(1);
}
" "$RESULT_JSON" "$PROACTIVE_MD" 2>/dev/null

if [ -f "$PROACTIVE_MD" ]; then
  log_pass "Relatório consultivo gerado: $PROACTIVE_MD"
else
  log_warn "Falha ao gerar markdown"
fi

# ─── Emit result final ────────────────────────────────────────────────
# Não falha o run global mesmo com crit/high — é consultivo.
# Mas registra status: failed se houve crit/high (pra visibility), passed se não.
if [ "$HAS_CRIT_OR_HIGH" -eq 1 ]; then
  emit_result "$BLINDAR_AGENT" "failed" 0
else
  emit_result "$BLINDAR_AGENT" "passed" 0
fi
