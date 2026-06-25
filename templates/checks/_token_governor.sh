#!/usr/bin/env bash
# blindar token governor — gestão inteligente de tokens
#
# Decide modelo, effort, cache e batch automaticamente baseado em:
#   - Tier do agente (security/analysis/triage/strategic)
#   - Override via env (BLINDAR_TIER_<AGENT> ou BLINDAR_BUDGET)
#   - Hard cap orçamento (BLINDAR_MAX_USD_PER_RUN)
#
# Source este arquivo APÓS _lib.sh em qualquer wrapper que use Claude API.
#
# Funções expostas:
#   blindar_resolve_tier <agent>          → ecoa tier (triage|analysis|security|strategic)
#   blindar_tier_to_model <tier>          → ecoa model ID
#   blindar_tier_to_effort <tier>         → ecoa effort (low|medium|high|xhigh)
#   blindar_tier_to_max_tokens <tier>     → ecoa max_tokens razoável pro tier
#   blindar_estimate_cost <model> <in> <out> → ecoa custo $USD estimado
#   blindar_log_cost <agent> <model> <in> <out>  → registra em .blindar/cost.log
#   blindar_check_budget                  → exit 1 se .blindar/cost.log soma > BLINDAR_MAX_USD_PER_RUN

# ─── Mapeamento tier → modelo ───
# Defaults pensados em custo/qualidade. Operador sobrescreve via env.
blindar_resolve_tier() {
  local agent="$1"
  # Override absoluto via env (ex: BLINDAR_TIER_PENTEST=strategic)
  local upper_agent=$(echo "$agent" | tr 'a-z-' 'A-Z_')
  local override_var="BLINDAR_TIER_${upper_agent}"
  local override="${!override_var:-}"
  [ -n "$override" ] && { echo "$override"; return; }

  # Mapeamento default por categoria
  case "$agent" in
    # STRATEGIC — só usar quando custo justifica (pentest profundo)
    pentest|check-pentest)
      echo "${BLINDAR_TIER_STRATEGIC_DEFAULT:-security}" ;;
    # SECURITY — Opus default (falso negativo vaza dado/multa)
    architect|check-architect|adversarial-reviewer|check-adversarial-reviewer)
      echo "${BLINDAR_TIER_SECURITY:-security}" ;;
    vector-db-security|fine-tune-data-leak|check-vector-db-security|check-fine-tune-data-leak)
      echo "${BLINDAR_TIER_SECURITY:-security}" ;;
    # ANALYSIS — Sonnet default (raciocínio multi-passo, latência tolerada)
    proactive-analysis|rag-quality|user-journey-simulator|feature-gap-analyzer|product-critic)
      echo "${BLINDAR_TIER_ANALYSIS:-analysis}" ;;
    check-proactive-analysis|check-rag-quality|check-user-journey-simulator|check-feature-gap-analyzer|check-product-critic)
      echo "${BLINDAR_TIER_ANALYSIS:-analysis}" ;;
    # TRIAGE — Haiku default (rápido, exploratório, humano filtra)
    *)
      echo "${BLINDAR_TIER_TRIAGE:-triage}" ;;
  esac
}

# ─── Rank de modelo (pra comparação de piso) ───
blindar_model_rank() {
  case "$1" in
    *haiku*)  echo 0 ;;
    *sonnet*) echo 1 ;;
    *opus*)   echo 2 ;;
    *fable*)  echo 3 ;;
    *)        echo 0 ;;
  esac
}

# ─── Mapeamento tier → model ID ───
blindar_tier_to_model() {
  local tier="$1"
  local model
  # Budget mode sobrescreve tudo (--budget=tight no launcher)
  case "${BLINDAR_BUDGET:-standard}" in
    tight)
      # Tudo Haiku, exceto strategic vira Sonnet
      [ "$tier" = "strategic" ] && model="claude-sonnet-4-6" || model="claude-haiku-4-5-20251001" ;;
    premium)
      # Tudo Opus, exceto triage vira Sonnet (não desperdiça Opus em coisa simples)
      [ "$tier" = "triage" ] && model="claude-sonnet-4-6" || model="claude-opus-4-8" ;;
    smart)
      # Preset inteligente (v0.43): qualidade onde dói, barato onde não.
      # Diferença vs standard: na DÚVIDA (tier desconhecido) sobe pra Sonnet,
      # nunca Haiku — não economiza quando o stake é incerto. Crítico = Opus.
      case "$tier" in
        triage)             model="claude-haiku-4-5-20251001" ;;  # trivial: barato OK
        analysis)           model="claude-sonnet-4-6" ;;
        security|strategic) model="claude-opus-4-8" ;;            # falso-negativo caro
        *)                  model="claude-sonnet-4-6" ;;          # incerto → seguro, não barato
      esac ;;
    *)
      # Standard mode (default): tier governa
      case "$tier" in
        triage)     model="claude-haiku-4-5-20251001" ;;
        analysis)   model="claude-sonnet-4-6" ;;
        security)   model="claude-opus-4-8" ;;
        strategic)  model="claude-opus-4-8" ;;  # Fable só se BLINDAR_ALLOW_FABLE=1
        *)          model="claude-haiku-4-5-20251001" ;;
      esac ;;
  esac
  # ─── Piso de modelo (v0.43) ───
  # BLINDAR_MIN_MODEL garante que NADA roda abaixo do piso — o "up" pra
  # sessão em modelo menor: o raciocínio pesado é delegado a um modelo forte
  # via sub-chamada governada, mesmo que o orquestrador esteja em Haiku.
  # Ex: BLINDAR_MIN_MODEL=claude-opus-4-8 → toda análise sobe pra Opus.
  if [ -n "${BLINDAR_MIN_MODEL:-}" ]; then
    local floor_rank cur_rank
    floor_rank="$(blindar_model_rank "$BLINDAR_MIN_MODEL")"
    cur_rank="$(blindar_model_rank "$model")"
    [ "$cur_rank" -lt "$floor_rank" ] && model="$BLINDAR_MIN_MODEL"
  fi
  echo "$model"
}

# ─── Mapeamento tier → effort ───
# Adaptive thinking é default — effort controla profundidade.
blindar_tier_to_effort() {
  case "$1" in
    triage)     echo "low" ;;
    analysis)   echo "medium" ;;
    security)   echo "high" ;;
    strategic)  echo "high" ;;
    *)          echo "low" ;;
  esac
}

# ─── Mapeamento tier → max_tokens ───
blindar_tier_to_max_tokens() {
  case "$1" in
    triage)     echo "2048" ;;
    analysis)   echo "4096" ;;
    security)   echo "8192" ;;
    strategic)  echo "16384" ;;
    *)          echo "2048" ;;
  esac
}

# ─── Estimador de custo (rough) ───
# Args: model, input_tokens, output_tokens
# Pricing per MTok (jun/2026): in/out
#   claude-haiku-4-5         : $1 / $5
#   claude-sonnet-4-6        : $3 / $15
#   claude-opus-4-8          : $5 / $25
#   claude-fable-5           : $10 / $50
blindar_estimate_cost() {
  local model="$1"; local in_tok="${2:-0}"; local out_tok="${3:-0}"
  local in_price out_price
  case "$model" in
    claude-haiku-4-5*) in_price=1;  out_price=5 ;;
    claude-sonnet-4-6*) in_price=3; out_price=15 ;;
    claude-opus-4-8*) in_price=5;   out_price=25 ;;
    claude-fable-5*) in_price=10;   out_price=50 ;;
    *) in_price=3; out_price=15 ;;
  esac
  # Calcula em centavos pra evitar floats em bash
  # cost_cents = (in × in_price + out × out_price) / 10000  (porque preço é per MTok)
  local cost_micro=$(( (in_tok * in_price + out_tok * out_price) ))
  # Output em USD com 4 casas
  awk -v c="$cost_micro" 'BEGIN { printf "%.4f", c / 1000000 }'
}

# ─── Logger de custo ───
# Append a .blindar/cost.log: ts,agent,model,in_tok,out_tok,cost_usd
blindar_log_cost() {
  local agent="$1"; local model="$2"; local in_tok="${3:-0}"; local out_tok="${4:-0}"
  local cost; cost=$(blindar_estimate_cost "$model" "$in_tok" "$out_tok")
  local log_dir="${BLINDAR_DIR:-.blindar}"
  mkdir -p "$log_dir"
  local log_file="$log_dir/cost.log"
  # Header se arquivo novo
  if [ ! -f "$log_file" ]; then
    echo "timestamp,agent,model,input_tokens,output_tokens,cost_usd" > "$log_file"
  fi
  printf '%s,%s,%s,%s,%s,%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$agent" "$model" "$in_tok" "$out_tok" "$cost" >> "$log_file"
}

# ─── Hard cap orçamento ───
# Soma cost.log; aborta se > BLINDAR_MAX_USD_PER_RUN (default $2.00).
blindar_check_budget() {
  local max="${BLINDAR_MAX_USD_PER_RUN:-2.00}"
  local log_file="${BLINDAR_DIR:-.blindar}/cost.log"
  [ ! -f "$log_file" ] && return 0
  local total
  total=$(awk -F, 'NR>1 {sum+=$6} END {printf "%.4f", sum+0}' "$log_file")
  awk -v t="$total" -v m="$max" 'BEGIN { exit (t > m ? 1 : 0) }'
  if [ $? -ne 0 ]; then
    log_fail "BUDGET EXCEEDED: \$${total} > \$${max} (BLINDAR_MAX_USD_PER_RUN)"
    log_fail "Próximos agentes serão skipped. Aumente o cap ou rode --budget=tight"
    return 1
  fi
  return 0
}

# ─── Resumo de custo (chamado no fim do run) ───
blindar_cost_summary() {
  local log_file="${BLINDAR_DIR:-.blindar}/cost.log"
  [ ! -f "$log_file" ] && return 0
  awk -F, 'NR>1 {sum+=$6; n++} END {
    if (n > 0) printf "💰 Custo total: $%.4f USD em %d calls\n", sum, n
  }' "$log_file"
}
