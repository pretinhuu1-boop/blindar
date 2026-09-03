#!/usr/bin/env bash
# Materializa: backup-restore-tested — backup nunca restaurado é backup de
# Schrödinger.
#
# O dump roda todo dia, o arquivo aparece no bucket, o painel fica verde. Nada
# disso é informação sobre a capacidade de voltar. O que se descobre só na hora
# do desastre: o dump está truncado porque o disco encheu no meio; o `pg_dump`
# rodou contra a réplica atrasada; a versão do servidor mudou e o formato não
# carrega mais; a chave de criptografia está no mesmo servidor que pegou fogo;
# ninguém sabe o comando exato e são 4h da manhã.
#
# O único fato que importa sobre backup é o tempo entre "vou restaurar" e
# "aplicação de pé com dado bom". Esse número só existe se alguém tiver medido.
BLINDAR_AGENT="check-backup-restore-tested"
source "$(dirname "$0")/_lib.sh"
log_section "Check: restore exercitado (não só backup agendado)"

# ─── Existe rotina de backup? ───
BACKUP=$(scan_src 'pg_dump|mysqldump|mongodump|sqlite3 .* \.backup|restic|borgbackup|borg create|wal-g|barman|pgbackrest|litestream|BACKUP_|backup_?(job|cron|script|schedule)|aws s3 (cp|sync) .*(dump|backup)' | head -5)
if [ -z "$BACKUP" ]; then
  for f in scripts/backup.sh backup.sh ops/backup.sh deploy/backup.sh Makefile; do
    [ -f "$f" ] || continue
    grep -qiE 'backup' "$f" 2>/dev/null && { BACKUP="$f:1:backup"; break; }
  done
fi

if [ -z "$BACKUP" ]; then
  log_info "nenhuma rotina de backup no repositório — a ausência de backup é assunto do check-backup-recovery"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

ARQ_BK=$(printf '%s\n' "$BACKUP" | head -1 | cut -d: -f1)
LN_BK=$(printf '%s\n' "$BACKUP" | head -1 | cut -d: -f2)
log_info "rotina de backup encontrada em $ARQ_BK:$LN_BK"

# ─── Existe evidência de RESTORE exercitado? ───
# Vale qualquer uma das quatro: script de restore, teste automatizado que
# restaura, job de CI de restore, runbook com passo de VERIFICAÇÃO.
RESTORE=""
for f in scripts/restore.sh restore.sh ops/restore.sh deploy/restore.sh \
         scripts/restore-drill.sh scripts/db-restore.sh; do
  [ -f "$f" ] && { RESTORE="$f"; break; }
done
[ -z "$RESTORE" ] && RESTORE=$(scan_src 'pg_restore|mysql[[:space:]]*<[[:space:]]*.*dump|mongorestore|restic restore|borg extract|wal-g backup-fetch|litestream restore|restore_?(test|drill|job)|restaura(r|cao|ção) (do )?backup' | head -1 | cut -d: -f1)

if [ -z "$RESTORE" ]; then
  for wf in .github/workflows/*.yml .github/workflows/*.yaml; do
    [ -f "$wf" ] || continue
    grep -qiE 'restore' "$wf" 2>/dev/null && { RESTORE="$wf"; break; }
  done
fi

if [ -z "$RESTORE" ]; then
  add_finding "high" \
    "Há rotina de BACKUP ($ARQ_BK) e nenhuma evidência de RESTORE exercitado — nem script de restore, nem teste, nem job de CI, nem runbook com verificação. Backup nunca restaurado é backup de Schrödinger: o estado só é conhecido no dia em que já não dá para escolher. Meça o tempo do restore ao menos uma vez e registre o número." \
    "$ARQ_BK" "$LN_BK"
else
  log_pass "evidência de restore encontrada: $RESTORE"
  # Restore existe, mas alguém já rodou? Data do último drill é o que separa
  # "procedimento escrito" de "capacidade comprovada".
  DRILL=$(grep -rIlEi 'drill|exercitad|restore testado|[uú]ltimo restore|RTO|tempo de restaura' \
    --include='*.md' --include='*.txt' --include='*.sh' --include='*.yml' \
    --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=.blindar . 2>/dev/null | head -1)
  [ -z "$DRILL" ] && add_finding "med" \
    "Existe caminho de restore, mas nenhum registro de que ele já foi EXERCITADO (data do último drill, tempo medido, RTO comprovado). Procedimento escrito não é capacidade comprovada — a primeira execução real não pode ser durante o desastre." \
    "$RESTORE" ""
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
