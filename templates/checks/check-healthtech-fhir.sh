#!/usr/bin/env bash
# Materializa: healthtech-fhir (FHIR R4/R5, CFM, LGPD art. 11)
BLINDAR_AGENT="check-healthtech-fhir"
source "$(dirname "$0")/_lib.sh"
log_section "Check: Healthtech FHIR (PEP, telemedicina, PHI)"

if ! command -v rg >/dev/null 2>&1; then emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0; fi

IGNORE=(-g '!node_modules' -g '!dist' -g '!build' -g '!.next' -g '!coverage' -g '!**/*.test.*' -g '!**/*.spec.*')

# ─── Gate: só roda se detectar stack FHIR/healthtech ───
FHIR_HITS=0
FHIR_HITS=$(( FHIR_HITS + $(rg -c "@medplum/core" --type ts --type js --type json "${IGNORE[@]}" 2>/dev/null | wc -l || echo 0) ))
FHIR_HITS=$(( FHIR_HITS + $(rg -c "fhir-kit-client" --type ts --type js --type json "${IGNORE[@]}" 2>/dev/null | wc -l || echo 0) ))
FHIR_HITS=$(( FHIR_HITS + $(rg -c "smart-on-fhir" --type ts --type js --type json "${IGNORE[@]}" 2>/dev/null | wc -l || echo 0) ))
FHIR_HITS=$(( FHIR_HITS + $(rg -c "fhir\\.js" --type ts --type js --type json "${IGNORE[@]}" 2>/dev/null | wc -l || echo 0) ))
FHIR_HITS=$(( FHIR_HITS + $(rg -c "hapi-fhir" --type ts --type js --type json "${IGNORE[@]}" 2>/dev/null | wc -l || echo 0) ))
FHIR_HITS=$(( FHIR_HITS + $(rg -c "resourceType" --type ts --type json "${IGNORE[@]}" 2>/dev/null | wc -l || echo 0) ))
FHIR_HITS=$(( FHIR_HITS + $(rg -c "(prontuario|telemedicina|teleconsulta|prescricao)" --type ts --type tsx "${IGNORE[@]}" 2>/dev/null | wc -l || echo 0) ))

if [ "$FHIR_HITS" -eq 0 ]; then
  log_warn "Nenhum indício de FHIR/healthtech detectado — pulando"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

log_info "Stack healthtech detectada ($FHIR_HITS sinais) — auditando"

# ─── 1. Patient SEM campo identifier (CRIT) ───
PATIENT_NO_ID=$(rg -nU "\"resourceType\"\\s*:\\s*\"Patient\"[\\s\\S]{0,400}" --type json --type ts "${IGNORE[@]}" 2>/dev/null \
  | rg -v "identifier" | wc -l || echo 0)
if [ "$PATIENT_NO_ID" -gt 0 ]; then
  add_finding "critical" "$PATIENT_NO_ID Patient resource(s) sem campo 'identifier' (CPF/CNS) — paciente fantasma, viola CFM 1821 e impede interoperabilidade" "" ""
fi

# ─── 2. Endpoint FHIR sem auth/scope check (CRIT) ───
FHIR_ROUTES_TMP=$(mktemp 2>/dev/null || echo "/tmp/blindar-fhir-routes.$$")
rg -n "(app|router|fastify)\\.(get|post|put|patch|delete)\\([\"'](/fhir|/api/fhir|/r4|/r5)" --type ts --type js "${IGNORE[@]}" 2>/dev/null > "$FHIR_ROUTES_TMP" || true
FHIR_ROUTES_TOTAL=$(wc -l < "$FHIR_ROUTES_TMP" 2>/dev/null || echo 0)
FHIR_ROUTES_NO_AUTH=0
if [ "$FHIR_ROUTES_TOTAL" -gt 0 ]; then
  FHIR_ROUTES_NO_AUTH=$(rg -v "(authenticate|requireAuth|verifyToken|smartAuth|checkScope|validateScope|passport|guard)" "$FHIR_ROUTES_TMP" 2>/dev/null | wc -l || echo 0)
fi
rm -f "$FHIR_ROUTES_TMP"
if [ "$FHIR_ROUTES_NO_AUTH" -gt 0 ]; then
  add_finding "critical" "$FHIR_ROUTES_NO_AUTH endpoint(s) FHIR sem auth/scope check — viola SMART on FHIR e expõe PHI" "" ""
fi

# ─── 3. PHI em log/console (CRIT — LGPD art. 11) ───
PHI_LOG_TMP=$(mktemp 2>/dev/null || echo "/tmp/blindar-phi-log.$$")
rg -nU "(console\\.(log|error|warn|debug|info)|logger\\.(info|debug|warn|error|trace))" --type ts --type tsx --type js "${IGNORE[@]}" -A 2 2>/dev/null > "$PHI_LOG_TMP" || true
PHI_IN_LOG=0
if [ -s "$PHI_LOG_TMP" ]; then
  PHI_IN_LOG=$(rg -ic "(diagnosis|cid-?10|prescription|prescricao|patient_?name|nome_?paciente|cpf|cns|mrn|prontuario|laudo|exame|medication)" "$PHI_LOG_TMP" 2>/dev/null || echo 0)
fi
rm -f "$PHI_LOG_TMP"
if [ "$PHI_IN_LOG" -gt 0 ]; then
  add_finding "critical" "$PHI_IN_LOG referência(s) a PHI em log/console — viola LGPD art. 11 (dado sensível de saúde)" "" ""
fi

# ─── 4. Consent resource ausente em fluxo de compartilhamento (HIGH) ───
SHARE_HITS=$(rg -c "(share|export|send|fhirClient\\.(post|put)|forwardTo|encaminhar)" --type ts --type js "${IGNORE[@]}" 2>/dev/null | wc -l || echo 0)
CONSENT_HITS=$(rg -c "(Consent|consent|consentimento)" --type ts --type js "${IGNORE[@]}" 2>/dev/null | wc -l || echo 0)
if [ "$SHARE_HITS" -gt 5 ] && [ "$CONSENT_HITS" -eq 0 ]; then
  add_finding "high" "Detectados $SHARE_HITS fluxos de compartilhamento de dados mas 0 referência a Consent resource — viola LGPD + boas práticas FHIR" "" ""
fi

# ─── 5. Sem audit trail (Provenance) em mudanças de prontuário (HIGH) ───
MUTATION_HITS=$(rg -c "(update|patch|create).*?(Observation|Condition|Medication|DiagnosticReport|Patient)" --type ts --type js "${IGNORE[@]}" 2>/dev/null | wc -l || echo 0)
PROVENANCE_HITS=$(rg -c "Provenance" --type ts --type js --type json "${IGNORE[@]}" 2>/dev/null | wc -l || echo 0)
if [ "$MUTATION_HITS" -gt 5 ] && [ "$PROVENANCE_HITS" -eq 0 ]; then
  add_finding "high" "Detectadas $MUTATION_HITS mutações em resources clínicos sem Provenance — viola CFM 1821 (trilha de auditoria)" "" ""
fi

# ─── 6. Telemedicina sem registro CFM completo (CRIT) ───
TELE_HITS=$(rg -c "(telemedicina|teleconsulta|telehealth|telemedicine)" --type ts --type tsx --type js "${IGNORE[@]}" 2>/dev/null | wc -l || echo 0)
if [ "$TELE_HITS" -gt 0 ]; then
  TELE_TMP=$(mktemp 2>/dev/null || echo "/tmp/blindar-tele.$$")
  rg -nU "(telemedicina|teleconsulta|telehealth|telemedicine)" --type ts --type tsx --type js "${IGNORE[@]}" -A 30 2>/dev/null > "$TELE_TMP" || true
  TELE_NO_CONSENT=$(rg -vc "(consent|consentimento|recording|gravacao)" "$TELE_TMP" 2>/dev/null || echo 0)
  TELE_NO_CRM=$(rg -vc "(crm|practitioner|medico)" "$TELE_TMP" 2>/dev/null || echo 0)
  rm -f "$TELE_TMP"
  if [ "$TELE_NO_CONSENT" -gt 0 ] || [ "$TELE_NO_CRM" -gt 0 ]; then
    add_finding "critical" "Telemedicina detectada sem registro completo (CRM médico + consentimento gravado) — viola CFM 2299/2021" "" ""
  fi
fi

# ─── 7. Patient.address sem masking em response não-clínica (MED) ───
ADDR_EXPOSURE=$(rg -nU "(serialize|toJSON|response).*?Patient" --type ts "${IGNORE[@]}" -A 5 2>/dev/null \
  | rg -i "address" | rg -v "(mask|redact|omit|exclude)" | wc -l || echo 0)
if [ "$ADDR_EXPOSURE" -gt 0 ]; then
  add_finding "medium" "$ADDR_EXPOSURE serialização(ões) de Patient.address sem masking — minimum necessary (LGPD art. 6, III)" "" ""
fi

# ─── 8. DiagnosticReport.result sem versioning (HIGH) ───
DIAG_HITS=$(rg -c "DiagnosticReport" --type ts --type js --type json "${IGNORE[@]}" 2>/dev/null | wc -l || echo 0)
HISTORY_HITS=$(rg -c "(_history|versionId|history-instance|meta\\.versionId)" --type ts --type js --type json "${IGNORE[@]}" 2>/dev/null | wc -l || echo 0)
if [ "$DIAG_HITS" -gt 3 ] && [ "$HISTORY_HITS" -eq 0 ]; then
  add_finding "high" "DiagnosticReport sem versioning (_history/versionId) — laudo alterado sem histórico viola CFM e configura adulteração" "" ""
fi

# ─── 9. Encounter.period sem timezone (MED) ───
PERIOD_NO_TZ_TMP=$(mktemp 2>/dev/null || echo "/tmp/blindar-period.$$")
rg -nU "\"period\"\\s*:\\s*\\{[\\s\\S]{0,200}\\}" --type json --type ts "${IGNORE[@]}" 2>/dev/null > "$PERIOD_NO_TZ_TMP" || true
PERIOD_NO_TZ=0
if [ -s "$PERIOD_NO_TZ_TMP" ]; then
  PERIOD_NO_TZ=$(rg -vc "(-03:00|-02:00|Z\"|[+\\-][0-9]{2}:[0-9]{2})" "$PERIOD_NO_TZ_TMP" 2>/dev/null || echo 0)
fi
rm -f "$PERIOD_NO_TZ_TMP"
if [ "$PERIOD_NO_TZ" -gt 0 ]; then
  add_finding "medium" "$PERIOD_NO_TZ Encounter.period sem timezone — viola ISO 8601 + ePING + dificulta auditoria temporal" "" ""
fi

# ─── 10. OAuth implicit em vez de PKCE (HIGH) ───
IMPLICIT_FLOW=$(rg -c "response_type.*token" --type ts --type js "${IGNORE[@]}" 2>/dev/null | wc -l || echo 0)
PKCE_USED=$(rg -c "(code_verifier|code_challenge|pkce)" --type ts --type js "${IGNORE[@]}" 2>/dev/null | wc -l || echo 0)
if [ "$IMPLICIT_FLOW" -gt 0 ] && [ "$PKCE_USED" -eq 0 ]; then
  add_finding "high" "OAuth implicit flow detectado sem PKCE — SMART on FHIR exige Authorization Code + PKCE" "" ""
fi

# ─── Resultado ───
CRIT_COUNT=$(printf '%s\n' "${FINDINGS[@]:-}" | grep -c '"severity":"critical"' 2>/dev/null || echo 0)
HIGH_COUNT=$(printf '%s\n' "${FINDINGS[@]:-}" | grep -c '"severity":"high"' 2>/dev/null || echo 0)

if [ "${#FINDINGS[@]}" -eq 0 ]; then
  emit_result "$BLINDAR_AGENT" "passed" 0
  exit 0
fi

if [ "$CRIT_COUNT" -gt 0 ] || [ "$HIGH_COUNT" -gt 2 ]; then
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi

emit_result "$BLINDAR_AGENT" "passed" 0
