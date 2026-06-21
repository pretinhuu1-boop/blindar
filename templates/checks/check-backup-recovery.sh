#!/usr/bin/env bash
# Materializa: backup-recovery — PITR config, restore drill, cifrado at-rest
BLINDAR_AGENT="check-backup-recovery"
source "$(dirname "$0")/_lib.sh"
log_section "Check: backup-recovery (PITR + restore drill + encryption)"

if ! is_prisma && ! is_python; then emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0; fi

# 1. Runbook docs/runbooks/backup-restore.md
[ ! -f "docs/runbooks/backup-restore.md" ] && [ ! -f "docs/backup-restore.md" ] && \
  add_finding "med" "Sem docs/runbooks/backup-restore.md — DR não documentado" "" ""

# 2. CI test ou cron de drill
HAS_DRILL=$(grep -rlE "backup.*restore|restore.*drill|pg_dump.*test" .github/workflows/ scripts/ 2>/dev/null | head -1)
[ -z "$HAS_DRILL" ] && add_finding "med" "Sem teste/cron de restore drill — 'backup nunca testado = backup que não existe'" "" ""

# 3. Backup at-rest cifrado (sinal: AES, KMS, encryption)
HAS_ENCRYPTION=$(grep -rlE "(AES.256|KMS|encryption.at.rest|TDE)" .env.example docker-compose.yml terraform/ 2>/dev/null | head -1)
[ -z "$HAS_ENCRYPTION" ] && add_finding "med" "Sem evidência de backup cifrado at-rest (AES-256/KMS)" "" ""

# 4. PITR config (Postgres)
if is_prisma; then
  if grep -qE "postgres" prisma/schema.prisma 2>/dev/null; then
    if ! grep -rqE "(wal_level|archive_mode|continuous_archiving|PITR|point.in.time)" docker-compose.yml *.tf k8s/ scripts/ 2>/dev/null; then
      add_finding "low" "Sem configuração PITR detectada — recovery limitado ao último snapshot" "" ""
    fi
  fi
fi

emit_result "$BLINDAR_AGENT" "passed" 0
