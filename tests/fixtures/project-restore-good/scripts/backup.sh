#!/usr/bin/env bash
# Backup diario do Postgres para o bucket.
pg_dump "$DATABASE_URL" | gzip > /tmp/dump.sql.gz
aws s3 cp /tmp/dump.sql.gz s3://meu-bucket/backups/
