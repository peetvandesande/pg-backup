#!/usr/bin/env bash
set -euo pipefail

: "${POSTGRES_USER:?Must set POSTGRES_USER}"
: "${POSTGRES_PASSWORD:?Must set POSTGRES_PASSWORD}"
: "${POSTGRES_DB:?Must set POSTGRES_DB}"

DATE="$(date +%Y%m%d)"
OUT_DIR="/backup"
OUT_FILE="${OUT_DIR}/${POSTGRES_DB}-${DATE}.sql.gz"

export PGPASSWORD="${POSTGRES_PASSWORD}"

echo "$(date -Is) Starting backup of ${POSTGRES_DB} as ${POSTGRES_USER}"

if pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB" \
  --no-owner --no-privileges \
  | gzip -9 > "$OUT_FILE"
then
  echo "$(date -Is) Backup completed: $OUT_FILE"
else
  echo "$(date -Is) Backup FAILED" >&2
  exit 1
fi

unset PGPASSWORD
