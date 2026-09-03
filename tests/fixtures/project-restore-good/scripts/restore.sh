#!/usr/bin/env bash
# Restaura o dump mais recente num banco descartavel e valida a contagem.
aws s3 cp "s3://meu-bucket/backups/$1" /tmp/dump.sql.gz
gunzip -c /tmp/dump.sql.gz | pg_restore -d "$RESTORE_TARGET_URL"
psql "$RESTORE_TARGET_URL" -c "select count(*) from users;"
