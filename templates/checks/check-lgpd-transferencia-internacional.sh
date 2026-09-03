#!/usr/bin/env bash
# Materializa: lgpd-transferencia-internacional — dado pessoal saindo do país
# sem base legal escrita.
#
# LGPD art. 33 e GDPR art. 44–49 dizem a mesma coisa por caminhos diferentes:
# mandar dado pessoal para fora da jurisdição só é lícito com base legal — país
# adequado, cláusulas contratuais padrão (SCC), regras corporativas globais ou
# consentimento específico. Quase nenhum projeto decide isso; ele simplesmente
# instala o SDK e o dado começa a viajar no primeiro deploy.
#
# Este check NÃO decide juridicamente nada. Ele responde uma pergunta factual:
# "há dado pessoal, há provedor estrangeiro, e existe documento?" As três coisas
# são verificáveis no repositório. A decisão e o documento são do operador.
BLINDAR_AGENT="check-lgpd-transferencia-internacional"
source "$(dirname "$0")/_lib.sh"
log_section "Check: transferência internacional de dado pessoal (LGPD art. 33 / GDPR cap. V)"

if ! has_personal_data; then
  log_info "sem sinal de titular de dado (schema/modelo sem campo de pessoa) — não se aplica"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

# ─── Roster de provedores com processamento fora do BR por padrão ───
# revisar trimestralmente — últ. revisão: 2026-09
# Lista DATADA de propósito: provedor abre região local, muda subprocessador e
# sai daqui sem avisar. Nome fora desta lista NÃO vira "aprovado" — vira
# "não classificado", reportado abaixo para conferência manual.
ROSTER='stripe|paddle|braintree|openai|anthropic|cohere|mistral|groq|perplexity|gemini|generativelanguage|vertexai|elevenlabs|playht|deepgram|assemblyai|twilio|vonage|sendgrid|mailgun|postmark|resend|mailchimp|segment|mixpanel|amplitude|posthog|datadog|newrelic|sentry|algolia|pinecone|weaviate|qdrant|supabase|planetscale|neon|upstash|cloudinary|auth0|clerk|okta|firebase|vercel|netlify|hubspot|intercom|zendesk|shopify|contentful'

# Onde o provedor aparece: dependência declarada, domínio chamado no código,
# chave no .env de exemplo.
ALVOS=""
for f in package.json requirements.txt pyproject.toml Pipfile go.mod Gemfile composer.json \
         .env.example .env.sample env.example; do
  [ -f "$f" ] && ALVOS="$ALVOS $f"
done

ENCONTRADOS=""
if [ -n "$ALVOS" ]; then
  while IFS=: read -r file line _rest; do
    [ -z "${file:-}" ] && continue
    ENCONTRADOS="$ENCONTRADOS $file:$line"
  done <<EOT
$(grep -InEi "($ROSTER)" $ALVOS 2>/dev/null | head -40)
EOT
fi
# Domínio chamado direto no código (SDK não é obrigatório para transferir dado).
DOMINIOS=$(scan_src "https?://[a-z0-9.-]*($ROSTER)\.(com|io|ai|co|dev|net)" 2>/dev/null | head -20)

NOMES=$(printf '%s\n' "$ENCONTRADOS" $DOMINIOS 2>/dev/null \
  | grep -oEi "($ROSTER)" | tr 'A-Z' 'a-z' | sort -u | tr '\n' ' ' | sed 's/ *$//')

if [ -z "$NOMES" ]; then
  log_pass "nenhum provedor estrangeiro do roster em uso — nada a documentar"
  log_info "roster revisado em 2026-09; provedor fora dele não é 'aprovado', é não classificado"
  emit_result "$BLINDAR_AGENT" "passed" 0
  exit 0
fi

log_info "provedores estrangeiros detectados: $NOMES"

# ─── Existe base legal escrita? ───
# Aceitamos qualquer forma de registro: política de privacidade que cite a
# transferência, DPA assinado listado, ADR, contrato anexado, seção no README.
BASE=""
BASE=$(grep -rIlEi 'cl[aá]usulas?[- ]contratuais[- ]padr[aã]o|standard contractual clause|\bSCC\b|transfer[eê]ncia internacional|international (data )?transfer|data processing (agreement|addendum)|\bDPA\b|binding corporate rules|decis[aã]o de adequa[cç][aã]o|adequacy decision' \
  --include='*.md' --include='*.mdx' --include='*.txt' --include='*.html' --include='*.pdf.txt' \
  --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=.blindar \
  . 2>/dev/null | head -3 | tr '\n' ' ')

if [ -n "$BASE" ]; then
  log_pass "base legal para transferência internacional documentada em: $BASE"
else
  ONDE="package.json"
  [ -f "package.json" ] || ONDE=""
  add_finding "high" \
    "Dado pessoal + provedor estrangeiro ($NOMES) e NENHUM documento de base legal para a transferência (SCC/cláusulas-padrão, DPA, decisão de adequação ou consentimento específico). LGPD art. 33 / GDPR art. 44–49: a transferência sem base legal é ilícita mesmo quando o serviço funciona. Registre o instrumento em docs/ e cite o subprocessador." \
    "$ONDE" ""
fi

# ─── Provedor fora do roster não é aprovação ───
# Endpoint externo que não bate com a lista datada acima. Pode ser nacional,
# pode ser estrangeiro novo. O check não sabe — e diz que não sabe.
NAOCLASS=$(scan_src "https?://[a-z0-9.-]+\.(com|io|ai|co|dev|net)/" 2>/dev/null \
  | grep -ohEi "https?://[a-z0-9.-]+" | sed 's|https\?://||' | tr 'A-Z' 'a-z' \
  | grep -vEi "($ROSTER)" | grep -vEi '^(localhost|127\.|example\.|schema\.org|www\.w3\.org|github\.com|registry\.npmjs\.org|fonts\.googleapis\.com|fonts\.gstatic\.com)' \
  | sort -u | head -5 | tr '\n' ' ')
if [ -n "$NAOCLASS" ]; then
  add_finding "low" \
    "Endpoints externos NÃO classificados pelo roster datado deste check (últ. revisão 2026-09): $NAOCLASS — não classificado não é aprovado; confira manualmente se algum processa dado pessoal fora da jurisdição" "" ""
fi

if [ "${#FINDINGS[@]}" -gt 0 ]; then
  case "${FINDINGS[*]}" in
    *'"severity":"high"'*|*'"severity":"crit"'*) emit_result "$BLINDAR_AGENT" "failed" 1; exit 1 ;;
  esac
  emit_result "$BLINDAR_AGENT" "failed" 0
  exit 0
fi

emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
