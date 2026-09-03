#!/usr/bin/env bash
# Materializa: llm-latency-observability — a chamada mais lenta do sistema é a
# única sem relógio.
#
# Uma chamada a provedor de LLM leva de 800ms a 40 segundos, varia com o
# tamanho do prompt, com a fila do provedor e com a hora do dia, e é o gargalo de
# quase toda aplicação que a usa. Sem medir duração por chamada, o p95 do produto
# é invisível: o time discute "o bot está lento" com base em impressão, e a
# regressão que dobrou a latência entra num deploy qualquer sem deixar rastro.
#
# Instrumentar é barato: marcar o tempo antes e depois, e emitir a duração com o
# modelo e o resultado. O que não dá para fazer é descobrir depois — telemetria
# não tem retroativo.
BLINDAR_AGENT="check-llm-latency-observability"
source "$(dirname "$0")/_lib.sh"
log_section "Check: latência das chamadas de LLM instrumentada"

PROVIDER='openai|anthropic|@anthropic-ai|@google/genai|@google/generative-ai|google\.generativeai|groq|mistralai|cohere|ollama|bedrock-runtime|azure-openai|langchain|llamaindex|litellm'
if ! scan_hit "$PROVIDER"; then
  log_info "projeto não usa LLM — não se aplica"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

# Onde a chamada é feita de fato (não o import).
CHAMADAS=$(scan_src '(messages\.create|chat\.completions\.create|responses\.create|generateContent|\.invoke\(|\.complete\(|createChatCompletion|generate_content|acompletion\()' | head -20)
if [ -z "$CHAMADAS" ]; then
  log_info "SDK de LLM declarado, mas nenhuma chamada localizada no código — nada a instrumentar aqui"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

ARQUIVOS=$(printf '%s\n' "$CHAMADAS" | cut -d: -f1 | sort -u)
SEM=""
COM=0
TOTAL=0
while IFS= read -r f; do
  [ -z "$f" ] && continue
  [ -f "$f" ] || continue
  printf '%s' "$f" | grep -qEi '(test|spec|mock|fixture|example)' && continue
  TOTAL=$(( TOTAL + 1 ))
  # Instrumentação vale em qualquer forma: relógio manual, histograma de
  # métrica, span de tracing, decorator de timing.
  if grep -qE '(Date\.now\(\)|performance\.now\(\)|process\.hrtime|perf_counter|time\.time\(\)|startTimer|\.observe\(|Histogram|histogram|duration_?ms|latenc|elapsed|startSpan|start_as_current_span|withSpan|@timed|tracer\.)' "$f" 2>/dev/null; then
    COM=$(( COM + 1 ))
  else
    SEM="$SEM $f"
  fi
done <<EOT
$ARQUIVOS
EOT

if [ "$TOTAL" -eq 0 ]; then
  log_info "chamadas de LLM só em teste/exemplo — não se aplica"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

if [ "$COM" -eq 0 ]; then
  PRIM=$(printf '%s' "$SEM" | tr ' ' '\n' | grep -v '^$' | head -1)
  LN=$(printf '%s\n' "$CHAMADAS" | grep -F "$PRIM:" | head -1 | cut -d: -f2)
  add_finding "med" \
    "Nenhuma das $TOTAL chamadas ao provedor de LLM registra duração (relógio, histograma, span). A chamada mais lenta e mais variável do sistema é a única sem medida: o p95 do produto é invisível e a regressão que dobrou a latência entra sem deixar rastro. Marque o tempo antes/depois e emita duração + modelo + resultado." \
    "$PRIM" "${LN:-}"
elif [ -n "$SEM" ]; then
  for f in $SEM; do
    add_finding "low" "Chamada de LLM sem medição de duração neste arquivo (outros no projeto medem — a cobertura está desigual e o p95 agregado fica enviesado)" "$f" ""
  done
  log_pass "$COM de $TOTAL arquivo(s) com chamada de LLM instrumentados"
else
  log_pass "todas as $TOTAL chamadas de LLM registram duração"
fi

if [ "${#FINDINGS[@]}" -gt 0 ]; then
  emit_result "$BLINDAR_AGENT" "failed" 0
  exit 0
fi
emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
