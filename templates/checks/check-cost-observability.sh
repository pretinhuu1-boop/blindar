#!/usr/bin/env bash
# Materializa: cost-observability — LLM cost tracking, slow query alerts, S3 lifecycle
BLINDAR_AGENT="check-cost-observability"
source "$(dirname "$0")/_lib.sh"
log_section "Check: cost-observability (LLM + DB + storage cost)"

if ! command -v rg >/dev/null 2>&1; then emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0; fi

IGNORE=(-g '!node_modules' -g '!dist' -g '!**/*.test.*')

# 1. LLM call sem tabela de tracking
HAS_LLM=$(grep -qE "\"(openai|anthropic|@google/genai)\":" package.json 2>/dev/null && echo "yes")
if [ "$HAS_LLM" = "yes" ]; then
  HAS_TRACK=$(rg -l "(llm_usage|llmUsage|tokens_used|costUsd)" --type ts --type prisma 2>/dev/null | head -1)
  [ -z "$HAS_TRACK" ] && add_finding "high" "LLM usado mas sem tabela llm_usage — custo invisível" "" ""
fi

# 2. S3/R2 sem lifecycle policy
HAS_S3=$(grep -qE "\"@aws-sdk/client-s3\"|\"@aws-sdk\":" package.json 2>/dev/null && echo "yes")
if [ "$HAS_S3" = "yes" ]; then
  HAS_LIFECYCLE=$(grep -rlE "LifecycleConfiguration|lifecycle.rules" terraform/ k8s/ 2>/dev/null | head -1)
  [ -z "$HAS_LIFECYCLE" ] && add_finding "med" "S3 sem lifecycle policy — temp/ cresce eterno" "" ""
fi

# 3. Sem budget/cost alerts no CI
HAS_BUDGET=$(grep -rlE "(aws-budgets|cost-anomaly|billing-alert)" .github/workflows/ terraform/ 2>/dev/null | head -1)
[ -z "$HAS_BUDGET" ] && add_finding "low" "Sem budget alert — fatura cresce sem aviso" "" ""

# 4. Cron de slow query alert
if is_prisma; then
  HAS_SLOW_QUERY=$(rg -l "(pg_stat_statements|slow_query|query_duration_alert)" --type ts --type sql 2>/dev/null | head -1)
  [ -z "$HAS_SLOW_QUERY" ] && add_finding "low" "Sem monitoramento de slow query — DB cresce CPU silencioso" "" ""
fi

# 5. Per-feature cost attribution
HAS_FEATURE_COST=$(rg -l "(feature_costs|feature.*cost)" --type ts --type prisma 2>/dev/null | head -1)
if [ "$HAS_LLM" = "yes" ] && [ -z "$HAS_FEATURE_COST" ]; then
  add_finding "low" "Sem per-feature cost attribution — não sabe qual feature pesa no orçamento" "" ""
fi

CRITS=$(printf '%s\n' "${FINDINGS[@]}" | grep -c '"severity":"crit"')
HIGHS=$(printf '%s\n' "${FINDINGS[@]}" | grep -c '"severity":"high"')
if [ "$CRITS" -gt 0 ] || [ "$HIGHS" -gt 0 ]; then
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi
emit_result "$BLINDAR_AGENT" "passed" 0
