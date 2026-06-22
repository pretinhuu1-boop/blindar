#!/usr/bin/env bash
# blindar API wrapper — biblioteca pra check-X.api.sh
#
# Auto-aplica gestão de tokens via _token_governor.sh:
#   - Tier por agente → modelo + effort + max_tokens
#   - Prompt caching em system prompts > 1024 tokens (90% off em prefixes)
#   - Hard cap orçamento (BLINDAR_MAX_USD_PER_RUN)
#   - Telemetria em .blindar/cost.log
#   - Refusal fallback chain
#
# Usage:
#   source "$(dirname "$0")/_lib.sh"
#   source "$(dirname "$0")/_api_wrapper.sh"
#   blindar_api_check "agent-name" "system prompt" "user content"

# Carrega governor (relativo a este arquivo)
_API_WRAPPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_API_WRAPPER_DIR/_token_governor.sh"

# ───────────────────────────────────────────────────────────────
# blindar_api_check AGENT_NAME SYSTEM_PROMPT USER_CONTENT [FORCED_MODEL]
# Quarto arg é OVERRIDE opcional — normalmente deixe vazio pra governor decidir.
# ───────────────────────────────────────────────────────────────
blindar_api_check() {
  local agent="$1"
  local system="$2"
  local content="$3"
  local forced_model="${4:-}"

  # 1. Pre-flight: tem API key?
  if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
    log_warn "ANTHROPIC_API_KEY ausente — agente $agent skipped"
    add_finding "low" "API check skipped: ANTHROPIC_API_KEY ausente" "" ""
    emit_result "$agent" "skipped" 0
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1; then
    log_warn "curl ausente — skipped"
    emit_result "$agent" "skipped" 0
    return 0
  fi

  # 2. Pre-flight: orçamento ainda OK?
  if ! blindar_check_budget; then
    log_warn "$agent skipped — budget excedido"
    add_finding "low" "Skipped: BLINDAR_MAX_USD_PER_RUN excedido" "" ""
    emit_result "$agent" "skipped" 0
    return 0
  fi

  # 3. Governor resolve tier → modelo + effort + max_tokens
  local tier model effort max_tokens
  tier=$(blindar_resolve_tier "$agent")
  if [ -n "$forced_model" ]; then
    model="$forced_model"
  else
    model=$(blindar_tier_to_model "$tier")
  fi
  effort=$(blindar_tier_to_effort "$tier")
  max_tokens=$(blindar_tier_to_max_tokens "$tier")

  log_info "$agent → tier=$tier model=$model effort=$effort"

  # 4. Truncate content (max 50k chars pra controlar tokens)
  local truncated_content
  truncated_content=$(echo "$content" | head -c 50000)

  # 5. Estima tokens (rough: 4 chars ≈ 1 token)
  local system_chars=${#system}
  local content_chars=${#truncated_content}
  local in_tokens=$(( (system_chars + content_chars) / 4 ))

  # 6. Decide se ativar cache (system prompt > ~1024 tokens)
  local use_cache=0
  [ "$system_chars" -gt 4096 ] && use_cache=1

  # 7. Monta tool definition
  local tool_def='{
    "name": "report_findings",
    "description": "Reporta findings deste agente em formato estruturado",
    "input_schema": {
      "type": "object",
      "required": ["overall_severity", "findings"],
      "properties": {
        "overall_severity": {"type": "string", "enum": ["none","low","med","high","crit"]},
        "findings": {
          "type": "array",
          "items": {
            "type": "object",
            "required": ["severity","message"],
            "properties": {
              "severity": {"type":"string","enum":["low","med","high","crit"]},
              "message": {"type":"string"},
              "file": {"type":"string"},
              "line": {"type":"integer"},
              "fix": {"type":"string"}
            }
          }
        }
      }
    }
  }'

  # 8. Monta payload (com cache_control se aplicável)
  local payload
  payload=$(node -e "
    const useCache = ${use_cache};
    const sys = useCache
      ? [{type: 'text', text: process.argv[1], cache_control: {type: 'ephemeral'}}]
      : process.argv[1];
    const p = {
      model: '$model',
      max_tokens: ${max_tokens},
      system: sys,
      tools: [JSON.parse(process.argv[2])],
      tool_choice: {type: 'tool', name: 'report_findings'},
      messages: [{role: 'user', content: process.argv[3]}],
      output_config: {effort: '${effort}'}
    };
    console.log(JSON.stringify(p));
  " "$system" "$tool_def" "$truncated_content" 2>/dev/null)

  if [ -z "$payload" ]; then
    log_warn "Falha ao montar payload"
    emit_result "$agent" "skipped" 0
    return 0
  fi

  # 9. Chama API
  local response
  response=$(curl -sS --max-time 120 https://api.anthropic.com/v1/messages \
    -H "x-api-key: $ANTHROPIC_API_KEY" \
    -H "anthropic-version: 2023-06-01" \
    -H "content-type: application/json" \
    -d "$payload" 2>/dev/null)

  if [ -z "$response" ]; then
    log_warn "API call falhou (sem resposta)"
    add_finding "low" "API call não retornou — verifique conexão e API key" "" ""
    emit_result "$agent" "skipped" 0
    return 0
  fi

  # 10. Detecta refusal (security classifier)
  local stop_reason
  stop_reason=$(echo "$response" | node -e "
    try { const r=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')); console.log(r.stop_reason||''); } catch(e){}" 2>/dev/null)

  if [ "$stop_reason" = "refusal" ]; then
    log_warn "$agent → refusal pelo classifier de segurança"
    # Fallback: tenta Opus 4.8 se não foi quem refusou
    if [ "$model" != "claude-opus-4-8" ] && [ -z "$forced_model" ]; then
      log_info "Tentando fallback claude-opus-4-8..."
      blindar_api_check "$agent" "$system" "$content" "claude-opus-4-8"
      return $?
    fi
    add_finding "low" "Refusal pelo classifier após tentativa com Opus — agente pulado" "" ""
    emit_result "$agent" "skipped" 0
    return 0
  fi

  # 11. Detecta erro da API
  if echo "$response" | grep -q '"type":"error"'; then
    local err_msg
    err_msg=$(echo "$response" | grep -oE '"message":"[^"]*"' | head -1 | sed 's/.*"message":"//;s/"$//')
    log_warn "API error: $err_msg"
    add_finding "low" "API error: $err_msg" "" ""
    emit_result "$agent" "skipped" 0
    return 0
  fi

  # 12. Extrai usage tokens pra telemetria
  local in_tok_actual out_tok_actual
  in_tok_actual=$(echo "$response" | node -e "
    try { const r=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')); console.log(r.usage?.input_tokens||0); } catch(e){console.log(0);}" 2>/dev/null)
  out_tok_actual=$(echo "$response" | node -e "
    try { const r=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')); console.log(r.usage?.output_tokens||0); } catch(e){console.log(0);}" 2>/dev/null)

  # Log telemetria
  blindar_log_cost "$agent" "$model" "${in_tok_actual:-0}" "${out_tok_actual:-0}"

  # 13. Extrai tool_use input (estruturado)
  local result_json
  result_json=$(node -e "
    try {
      const r = JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
      const toolUse = (r.content || []).find(c => c.type === 'tool_use');
      if (!toolUse) { process.exit(0); }
      console.log(JSON.stringify(toolUse.input));
    } catch(e) { process.exit(0); }
  " <<< "$response" 2>/dev/null)

  if [ -z "$result_json" ]; then
    log_warn "API não retornou tool_use estruturado"
    emit_result "$agent" "skipped" 0
    return 0
  fi

  # 14. Parse findings e adiciona via add_finding (1× node call, não N×)
  local findings_csv
  findings_csv=$(node -e "
    try {
      const r = JSON.parse(process.argv[1]);
      (r.findings || []).forEach(f => {
        const sev = (f.severity || 'low').replace(/[,\n]/g, ' ');
        const msg = (f.message || '').replace(/[,\n]/g, ' ');
        const file = (f.file || '').replace(/[,\n]/g, ' ');
        const line = String(f.line || '').replace(/[,\n]/g, ' ');
        console.log([sev, msg, file, line].join('||'));
      });
    } catch(e) {}
  " "$result_json" 2>/dev/null)

  local has_crit_or_high=0
  while IFS='||' read -r sev msg file line; do
    [ -z "$sev" ] && continue
    add_finding "$sev" "[AI] $msg" "$file" "$line"
    [ "$sev" = "crit" ] || [ "$sev" = "high" ] && has_crit_or_high=1
  done <<< "$findings_csv"

  if [ "$has_crit_or_high" -eq 1 ]; then
    emit_result "$agent" "failed" 1
    return 0
  fi

  emit_result "$agent" "passed" 0
}

# Helper: lê arquivos relevantes pra um agente (limita tokens)
blindar_collect_evidence() {
  local agent="$1"
  shift
  local files=("$@")
  local out=""
  for f in "${files[@]}"; do
    if [ -f "$f" ]; then
      out+=$'\n\n=== '"$f"' ===\n'
      out+=$(head -c 5000 "$f" 2>/dev/null)
    fi
  done
  echo "$out"
}
