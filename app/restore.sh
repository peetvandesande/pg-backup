#!/bin/sh
set -eu

# Simple logger with ISO timestamp
log() { printf "%s %s\n" "$(date -Is)" "$*" ; }

# Required
: "${POSTGRES_USER:?Must set POSTGRES_USER}"
: "${POSTGRES_PASSWORD:?Must set POSTGRES_PASSWORD}"
: "${POSTGRES_DB:?Must set POSTGRES_DB}"

# Optional
BACKUP_DIR="${BACKUPS_DIR:-/backups}"
VERIFY="${VERIFY_SHA256:-1}"   # 1 = verify if .sha256 exists; 0 = skip

# Resolve backup file:
# - Arg 1 if given
if [ -n "${1:-}" ]; then
  BACKUP_FILE="$1"
else
  TODAY="$(date +%Y%m%d)"
  BACKUP_FILE="$(ls -1 ${BACKUP_DIR}/${POSTGRES_DB}-*.sql.gz 2>/dev/null \
    | sed -n 's#.*-\([0-9]\{8\}\)\.sql\.gz$#\1 \0#p' \
    | sort \
    | awk -v t="$TODAY" '$1 != t {print $2}' \
    | tail -n1 || true)"
fi

if [ -z "${BACKUP_FILE:-}" ] || [ ! -f "${BACKUP_FILE}" ]; then
  log "ERROR: Backup file not found. Provide a file path or ensure historical backups exist." >&2
  exit 1
fi

export PGPASSWORD="${POSTGRES_PASSWORD}"

HOST_OPTS=""
[ -n "${POSTGRES_HOST:-}" ] && HOST_OPTS="$HOST_OPTS -h ${POSTGRES_HOST}"
[ -n "${POSTGRES_PORT:-}" ] && HOST_OPTS="$HOST_OPTS -p ${POSTGRES_PORT}"

log "Restoring ${BACKUP_FILE} into '${POSTGRES_DB}' as '${POSTGRES_USER}'${POSTGRES_HOST:+ on ${POSTGRES_HOST}}"

# Verify checksum if file exists and VERIFY is true
if [ "${VERIFY}" != "0" ] && [ -f "${BACKUP_FILE}.sha256" ]; then
  log "Verifying checksum: ${BACKUP_FILE}.sha256"
  if ! sha256sum -c "${BACKUP_FILE}.sha256"; then
    log "ERROR: SHA-256 verification failed for ${BACKUP_FILE}" >&2
    exit 1
  fi
fi

# gunzip -> psql; stop on first error
if gzip -dc "${BACKUP_FILE}" | sh -c "psql ${HOST_OPTS} -U '${POSTGRES_USER}' -d '${POSTGRES_DB}' --set=ON_ERROR_STOP=1"; then
  log "Restore completed successfully."
else
  log "Restore FAILED." >&2
  exit 1
fi
