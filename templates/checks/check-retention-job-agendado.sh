#!/usr/bin/env bash
# Materializa: retention-job-agendado — política de retenção sem job que a
# execute é retenção de mentira.
#
# O padrão é sempre o mesmo: alguém escreve RETENCAO_DIAS=90 no .env, a variável
# entra no README como "política de retenção", e nada nunca apaga nada. Passa em
# auditoria de papel e reprova em auditoria de banco: dado de 2019 vivo com
# política declarada de 90 dias é pior que não ter política — é declaração falsa.
#
# Este check só roda quando HÁ política declarada. Ausência de política é assunto
# do check-compliance-lgpd-br; aqui a pergunta é se o que foi declarado executa.
BLINDAR_AGENT="check-retention-job-agendado"
source "$(dirname "$0")/_lib.sh"
log_section "Check: job agendado que cumpre a política de retenção"

CONFIG=$(scan_src '(RETENTION|RETENCAO|RETEN[ÇC][AÃ]O|retention_?days|retencao_?dias|dias_?retencao|DATA_RETENTION|TTL_DAYS|EXPIRE_AFTER_DAYS|purge_?after)' \
  | grep -viE '(cache|redis|session|jwt|token)[_-]?ttl' | head -5)

if [ -z "$CONFIG" ]; then
  log_info "nenhuma política de retenção declarada — nada a cobrar aqui"
  log_info "(ausência de política é assunto do check-compliance-lgpd-br)"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

ARQ_CFG=$(printf '%s\n' "$CONFIG" | head -1 | cut -d: -f1)
LN_CFG=$(printf '%s\n' "$CONFIG" | head -1 | cut -d: -f2)
log_info "política de retenção declarada em $ARQ_CFG:$LN_CFG"

# ─── Existe agendamento? ───
# Vale qualquer agendador real: cron do sistema, cron do provedor, repeat de
# fila, scheduler do framework, timer do systemd, schedule do CI.
AGENDA=$(scan_src '(node-cron|@nestjs/schedule|@Cron\(|croniter|beat_schedule|APScheduler|BullMQ|repeatJobKey|pg_cron|CREATE[[:space:]]+EVENT|sidekiq-cron|OnCalendar=)' | head -5)

if [ -z "$AGENDA" ]; then
  for wf in .github/workflows/*.yml .github/workflows/*.yaml; do
    [ -f "$wf" ] || continue
    grep -qE '^[[:space:]]*schedule:' "$wf" 2>/dev/null && { AGENDA="$wf:1:schedule"; break; }
  done
fi

if [ -z "$AGENDA" ]; then
  for f in crontab deploy/crontab infra/crontab Dockerfile.cron; do
    [ -f "$f" ] && { AGENDA="$f:1:crontab"; break; }
  done
fi

# ─── O que roda purga de verdade? ───
PURGA=$(scan_src '(purge|prune|cleanup|clean_?old|deleteMany|delete_?expired|DELETE[[:space:]]+FROM|anonymiz|anonimiz)' | head -5)

if [ -z "$AGENDA" ]; then
  add_finding "med" \
    "Política de retenção declarada e NENHUM agendador no repositório (cron, @Cron, Celery beat, BullMQ repeat, schedule de CI, systemd timer). Config sem job é retenção de mentira: o prazo vence e o dado continua lá." \
    "$ARQ_CFG" "$LN_CFG"
elif [ -z "$PURGA" ]; then
  ARQ_AG=$(printf '%s\n' "$AGENDA" | head -1 | cut -d: -f1)
  add_finding "med" \
    "Há agendador ($ARQ_AG) e há política de retenção, mas nenhuma rotina que de fato apague ou anonimize o vencido (purge, prune, deleteMany, DELETE FROM, anonymize). O agendador existe para outra coisa — a retenção segue sem executor." \
    "$ARQ_CFG" "$LN_CFG"
else
  log_pass "retenção declarada, agendador presente e rotina de purga encontrada"
fi

if [ "${#FINDINGS[@]}" -gt 0 ]; then
  emit_result "$BLINDAR_AGENT" "failed" 0
  exit 0
fi
emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
