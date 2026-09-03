#!/usr/bin/env bash
# Materializa: metered-external-cost-guard — bomba de custo.
#
# Serviço externo cobrado por uso (LLM, síntese de voz, transcrição, SMS, e-mail
# transacional, OCR) tem uma propriedade que serviço próprio não tem: cada
# requisição sai do seu bolso, e o teto é o limite do cartão. Sem cota POR
# ORIGEM — por tenant, por chave, por conta — basta um cliente em laço, um bot
# raspando, ou um bug de retry para consumir o orçamento do mês em uma tarde.
#
# Rate limit global não resolve o problema certo: ele protege o SEU servidor de
# sobrecarga. A cota por origem é o que impede uma origem de gastar o dinheiro de
# todas as outras. São controles diferentes, com finalidades diferentes.
#
# O check é genérico de propósito: a classe do serviço importa, o fornecedor não.
BLINDAR_AGENT="check-metered-external-cost-guard"
source "$(dirname "$0")/_lib.sh"
log_section "Check: cota por origem em serviço externo cobrado por uso"

# ─── Serviço cobrado por uso ───
# roster revisar trimestralmente — últ. revisão: 2026-09
# Fornecedor fora da lista não vira "aprovado": vira não classificado. A lista
# serve para reduzir falso-negativo, não para definir o universo.
METERED='openai|anthropic|@anthropic-ai|@google/genai|generativeai|generativelanguage|gemini|vertexai|groq|mistralai|cohere|bedrock-runtime|azure-openai|litellm|elevenlabs|playht|deepgram|assemblyai|whisper|twilio|vonage|nexmo|zenvia|sendgrid|mailgun|postmark|resend|ses[_-]?client|textract|rekognition|vision\.googleapis|maps\.googleapis|algolia'

CHAMADAS=$(scan_src "$METERED" | grep -viE '(test|spec|mock|fixture|\.lock|package-lock)' | head -10)
if [ -z "$CHAMADAS" ]; then
  log_info "nenhum serviço externo cobrado por uso detectado — não se aplica"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi
SERVICOS=$(printf '%s\n' "$CHAMADAS" | grep -ohEi "$METERED" | tr 'A-Z' 'a-z' | sort -u | tr '\n' ' ' | sed 's/ *$//')
ARQ=$(printf '%s\n' "$CHAMADAS" | head -1 | cut -d: -f1)
LN=$(printf '%s\n' "$CHAMADAS" | head -1 | cut -d: -f2)
log_info "serviço(s) cobrado(s) por uso: $SERVICOS"

# ─── Existe cota POR ORIGEM? ───
# O que conta: contador/limite ligado a uma identidade (tenant, loja, conta,
# chave), não um teto global do processo.
#
# O termo precisa aparecer em FORMA DE CÓDIGO — acesso a propriedade, comparação
# ou atribuição. A versão ingênua procurava a palavra solta e num projeto real
# casou com três comentários e uma string de ajuda ("você ver quem está queimando
# cota antes de a loja reclamar"). Prosa sobre cota virava cota implementada, e o
# check aprovava justamente o projeto cuja cota por loja ainda era um TODO.
COTA_T='quota|cota|credit(s|os)?_?(restante|remaining|balance|usados?)|usage_?limit|limite_?(de_)?uso|monthly_?limit|budget_?(limit|cap)|spend_?limit|tokens_?(restantes|remaining)|max_?requests_?per_?(tenant|user|account|key)|consumo_?(mensal|diario)'
COTA=$(scan_src "([.\\[][\"']?($COTA_T)|($COTA_T)[A-Za-z_]*[[:space:]]*(>=|<=|>|<|===|==|!==|!=|\\+=|-=)|($COTA_T)[A-Za-z_]*[[:space:]]*[:=][^=])" \
  | grep -viE '(test|spec|mock|fixture)' \
  | grep -vE ':[0-9]+:[[:space:]]*(//|\*|#|--)' | head -5)
POR_ORIGEM=""
if [ -n "$COTA" ]; then
  POR_ORIGEM=$(printf '%s\n' "$COTA" | grep -iE '(tenant|loja|account|conta|user|usuario|customer|cliente|org|workspace|api_?key|key_?id)' | head -1)
fi
# Rate limit chaveado por identidade também é cota por origem.
if [ -z "$POR_ORIGEM" ]; then
  POR_ORIGEM=$(scan_src '(keyGenerator|key_?func|rate.?limit[^;]*(tenant|user|account|apiKey|api_key|loja|org)|limiter\.(consume|check)\([^)]*(tenant|user|account|loja))' \
    | grep -viE '(test|spec|mock)' | head -1)
fi

if [ -n "$POR_ORIGEM" ]; then
  log_pass "cota por origem encontrada: $(printf '%s' "$POR_ORIGEM" | cut -d: -f1)"
elif [ -n "$COTA" ]; then
  A=$(printf '%s\n' "$COTA" | head -1 | cut -d: -f1)
  L=$(printf '%s\n' "$COTA" | head -1 | cut -d: -f2)
  add_finding "med" \
    "Há noção de cota/limite, mas não chaveada por origem (tenant, conta, loja, chave) — um teto global protege o servidor de sobrecarga e não impede uma única origem de consumir o orçamento de todas. Serviço(s) cobrado(s) por uso em jogo: $SERVICOS." \
    "$A" "$L"
else
  add_finding "med" \
    "Chamada a serviço cobrado por uso ($SERVICOS) sem NENHUMA cota por tenant/conta/chave. Cada requisição sai do seu bolso e o teto é o limite do cartão: um cliente em laço, um bot raspando ou um retry mal configurado esvazia o orçamento do mês em uma tarde, e a conta chega no fim do ciclo." \
    "$ARQ" "$LN"
fi

if [ "${#FINDINGS[@]}" -gt 0 ]; then
  emit_result "$BLINDAR_AGENT" "failed" 0
  exit 0
fi
emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
