#!/usr/bin/env bash
set -euo pipefail

# Required env vars
: "${POSTGRES_USER:?Must set POSTGRES_USER}"
: "${POSTGRES_PASSWORD:?Must set POSTGRES_PASSWORD}"
: "${POSTGRES_DB:?Must set POSTGRES_DB}"

BACKUP_DIR="/backup"

# If an argument is given, treat it as the backup file to restore
if [ "${1:-}" != "" ]; then
  BACKUP_FILE="$1"
else
  # No arg: choose yesterday's backup file

  # Try GNU date first
  if YDAY_FMT="$(date -d 'yesterday' +%Y%m%d 2>/dev/null)"; then
    CANDIDATE="${BACKUP_DIR}/${POSTGRES_DB}-${YDAY_FMT}.sql.gz"
    if [ -f "$CANDIDATE" ]; then
      BACKUP_FILE="$CANDIDATE"
    else
      # Fallback: pick the latest backup not from 'today'
      TODAY_FMT="$(date +%Y%m%d)"
      BACKUP_FILE="$(ls -1 ${BACKUP_DIR}/${POSTGRES_DB}-*.sql.gz 2>/dev/null \
        | sed -n 's#.*-\([0-9]\{8\}\)\.sql\.gz$#\1 \0#p' \
        | sort \
        | awk -v today="$TODAY_FMT" '$1 != today {print $2}' \
        | tail -n1 || true)"
    fi
  else
    # BusyBox/other date without -d: fallback to "latest not today"
    TODAY_FMT="$(date +%Y%m%d)"
    BACKUP_FILE="$(ls -1 ${BACKUP_DIR}/${POSTGRES_DB}-*.sql.gz 2>/dev/null \
      | sed -n 's#.*-\([0-9]\{8\}\)\.sql\.gz$#\1 \0#p' \
      | sort \
      | awk -v today="$TODAY_FMT" '$1 != today {print $2}' \
      | tail -n1 || true)"
  fi
fi

if [ -z "${BACKUP_FILE:-}" ] || [ ! -f "$BACKUP_FILE" ]; then
  echo "$(date -Is) ERROR: Could not find a backup file to restore." >&2
  echo "  Looked for: ${BACKUP_DIR}/${POSTGRES_DB}-YYYYMMDD.sql.gz (yesterday or latest not-today)" >&2
  echo "  Or pass a file explicitly: pg-restore /backup/${POSTGRES_DB}-20250115.sql.gz" >&2
  exit 1
fi

export PGPASSWORD="${POSTGRES_PASSWORD}"

echo "$(date -Is) Restoring ${BACKUP_FILE} into database '${POSTGRES_DB}' as user '${POSTGRES_USER}'"

# Stream gunzip -> psql (stop on first error)
if gzip -dc "$BACKUP_FILE" \
  | psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" --set=ON_ERROR_STOP=1
then
  echo "$(date -Is) Restore completed successfully."
else
  echo "$(date -Is) Restore FAILED." >&2
  exit 1
fi

unset PGPASSWORD
