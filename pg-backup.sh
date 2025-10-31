#!/usr/bin/env bash
set -euo pipefail

: "${POSTGRES_USER:?Must set POSTGRES_USER}"
: "${POSTGRES_PASSWORD:?Must set POSTGRES_PASSWORD}"
: "${POSTGRES_DB:?Must set POSTGRES_DB}"

# Optional: prefer POSTGRES_HOST/POSTGRES_PORT; fall back to libpq defaults (socket / 5432)
PGHOST_OPT=()
PGPORT_OPT=()
[[ -n "${POSTGRES_HOST:-}" ]] && PGHOST_OPT=( -h "$POSTGRES_HOST" )
[[ -n "${POSTGRES_PORT:-}" ]] && PGPORT_OPT=( -p "$POSTGRES_PORT" )

export PGPASSWORD="${POSTGRES_PASSWORD}"

DATE="$(date +%Y%m%d)"
OUT_DIR="/backup"
OUT_FILE="${OUT_DIR}/${POSTGRES_DB}-${DATE}.sql.gz"

export PGPASSWORD="${POSTGRES_PASSWORD}"

echo "$(date -Is) Starting backup of ${POSTGRES_DB} as ${POSTGRES_USER}${POSTGRES_HOST:+ on ${POSTGRES_HOST}}"

# Plain SQL -> gzip (simple to restore)
if pg_dump \
      "${PGHOST_OPT[@]}" "${PGPORT_OPT[@]}" \
      -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
      --no-owner --no-privileges \
   | gzip -9 > "$OUT_FILE"
then
  echo "$(date -Is) Backup completed: $OUT_FILE"
else
  echo "$(date -Is) Backup FAILED" >&2
  exit 1
fi

unset PGPASSWORD
