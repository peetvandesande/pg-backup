#!/usr/bin/env bash
set -euo pipefail

# Required env vars
: "${POSTGRES_USER:?Must set POSTGRES_USER}"
: "${POSTGRES_PASSWORD:?Must set POSTGRES_PASSWORD}"
: "${POSTGRES_DB:?Must set POSTGRES_DB}"

BACKUP_DIR="/backup"

# Resolve backup file:
#  - arg1 if provided
#  - else try "yesterday" (GNU date); if not available, fall back to latest not-today
if [[ -n "${1:-}" ]]; then
  BACKUP_FILE="$1"
else
  if YDAY="$(date -d 'yesterday' +%Y%m%d 2>/dev/null)"; then
    CAND="${BACKUP_DIR}/${POSTGRES_DB}-${YDAY}.sql.gz"
    if [[ -f "$CAND" ]]; then BACKUP_FILE="$CAND"; fi
  fi
  if [[ -z "${BACKUP_FILE:-}" ]]; then
    TODAY="$(date +%Y%m%d)"
    BACKUP_FILE="$(ls -1 ${BACKUP_DIR}/${POSTGRES_DB}-*.sql.gz 2>/dev/null \
      | sed -n 's#.*-\([0-9]\{8\}\)\.sql\.gz$#\1 \0#p' \
      | sort \
      | awk -v today="$TODAY" '$1 != today {print $2}' \
      | tail -n1 || true)"
  fi
fi

if [[ -z "${BACKUP_FILE:-}" || ! -f "$BACKUP_FILE" ]]; then
  echo "$(date -Is) ERROR: Backup file not found. Pass a file or ensure yesterday/latest exists." >&2
  exit 1
fi

export PGPASSWORD="${POSTGRES_PASSWORD}"

# Optional host/port
PGHOST_OPT=()
PGPORT_OPT=()
[[ -n "${POSTGRES_HOST:-}" ]] && PGHOST_OPT=( -h "$POSTGRES_HOST" )
[[ -n "${POSTGRES_PORT:-}" ]] && PGPORT_OPT=( -p "$POSTGRES_PORT" )

echo "$(date -Is) Restoring ${BACKUP_FILE} into '${POSTGRES_DB}' as '${POSTGRES_USER}'${POSTGRES_HOST:+ on ${POSTGRES_HOST}}"

# Stream gunzip -> psql; stop on first error
if gzip -dc "$BACKUP_FILE" \
  | psql "${PGHOST_OPT[@]}" "${PGPORT_OPT[@]}" -U "$POSTGRES_USER" -d "$POSTGRES_DB" --set=ON_ERROR_STOP=1
then
  echo "$(date -Is) Restore completed successfully."
else
  echo "$(date -Is) Restore FAILED." >&2
  exit 1
fi

unset PGPASSWORD
