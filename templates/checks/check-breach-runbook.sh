#!/usr/bin/env bash
# Materializa: breach-runbook — quem faz o quê nas primeiras horas do vazamento.
#
# A LGPD dá prazo de 3 dias úteis para comunicar a ANPD e os titulares (Resolução
# CD/ANPD nº 15/2024); o GDPR dá 72 horas. Esse relógio começa a correr quando a
# organização toma conhecimento — no meio da madrugada, com o time ainda tentando
# entender o que aconteceu. Quem improvisa o comunicado nessas condições erra o
# escopo, erra o prazo, ou fala demais.
#
# Runbook não é burocracia: é a decisão já tomada para o momento em que não vai
# dar tempo de tomá-la.
BLINDAR_AGENT="check-breach-runbook"
source "$(dirname "$0")/_lib.sh"
log_section "Check: runbook de incidente/vazamento de dado pessoal"

if ! has_personal_data; then
  log_info "sem sinal de titular de dado — não se aplica"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

RB=$(grep -rIlEi 'vazamento de dados|data breach|incidente de seguran[cç]a com dados|notifica[cç][aã]o . ANPD|breach notification|comunicar a ANPD|supervisory authority' \
  --include='*.md' --include='*.mdx' --include='*.txt' --include='*.yml' --include='*.yaml' \
  --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=.blindar \
  . 2>/dev/null | head -3)

if [ -z "$RB" ]; then
  add_finding "med" \
    "Sem runbook de notificação de incidente/vazamento. LGPD: 3 dias úteis para comunicar ANPD e titulares (Res. CD/ANPD 15/2024); GDPR: 72h. O relógio começa quando alguém descobre — de madrugada, sem tempo de decidir quem assina, o que se diz e por qual canal. Escreva em runbooks/: quem declara o incidente, como se mede o escopo, o texto-base ao titular, o canal da autoridade." \
    "runbooks/" ""
else
  ARQ=$(printf '%s\n' "$RB" | head -1)
  log_pass "runbook encontrado: $ARQ"
  # Runbook existe mas não fixa prazo nem responsável — vira redação livre na
  # pior hora possível.
  grep -qEi '3 dias|tr[eê]s dias|72 ?h|72 horas|prazo' "$ARQ" 2>/dev/null || \
    add_finding "low" "Runbook de vazamento sem PRAZO explícito (3 dias úteis LGPD / 72h GDPR) — sob pressão, o prazo é a primeira coisa que se perde" "$ARQ" ""
  grep -qEi 'respons[aá]vel|encarregado|DPO|quem declara|quem comunica|quem assina' "$ARQ" 2>/dev/null || \
    add_finding "low" "Runbook de vazamento sem RESPONSÁVEL nomeado (encarregado/DPO) — sem dono, ninguém aciona" "$ARQ" ""
fi

if [ "${#FINDINGS[@]}" -gt 0 ]; then
  emit_result "$BLINDAR_AGENT" "failed" 0
  exit 0
fi
emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
