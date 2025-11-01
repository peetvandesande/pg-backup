#!/usr/bin/env sh
set -eu

# Required
: "${POSTGRES_USER:?Must set POSTGRES_USER}"
: "${POSTGRES_PASSWORD:?Must set POSTGRES_PASSWORD}"
: "${POSTGRES_DB:?Must set POSTGRES_DB}"

# Optional
BACKUP_DIR="${BACKUPS_DIR:-/backups}"
VERIFY="${VERIFY_SHA256:-1}"   # 1 = verify if .sha256 exists; 0 = skip

# Resolve backup file:
# - Arg 1 if given
# - Else: yesterday (GNU date works on Alpine via busybox? BusyBox supports %Y%m%d but not -d; so fallback to latest)
if [ -n "${1:-}" ]; then
  BACKUP_FILE="$1"
else
  # BusyBox 'date' lacks -d; choose latest not-today
  TODAY="$(date +%Y%m%d)"
  # shellcheck disable=SC2010
  BACKUP_FILE="$(ls -1 ${BACKUP_DIR}/${POSTGRES_DB}-*.sql.gz 2>/dev/null \
    | sed -n 's#.*-\([0-9]\{8\}\)\.sql\.gz$#\1 \0#p' \
    | sort \
    | awk -v t="$TODAY" '$1 != t {print $2}' \
    | tail -n1 || true)"
fi

if [ -z "${BACKUP_FILE:-}" ] || [ ! -f "${BACKUP_FILE}" ]; then
  echo "$(date -Is) ERROR: Backup file not found. Provide a file path or ensure historical backups exist." >&2
  exit 1
fi

export PGPASSWORD="${POSTGRES_PASSWORD}"

HOST_OPTS=""
[ -n "${POSTGRES_HOST:-}" ] && HOST_OPTS="$HOST_OPTS -h ${POSTGRES_HOST}"
[ -n "${POSTGRES_PORT:-}" ] && HOST_OPTS="$HOST_OPTS -p ${POSTGRES_PORT}"

echo "$(date -Is) Restoring ${BACKUP_FILE} into '${POSTGRES_DB}' as '${POSTGRES_USER}'${POSTGRES_HOST:+ on ${POSTGRES_HOST}}"

# Verify checksum if file exists and VERIFY is truthy
if [ "${VERIFY}" != "0" ] && [ -f "${BACKUP_FILE}.sha256" ]; then
  echo "$(date -Is) Verifying checksum: ${BACKUP_FILE}.sha256"
  if ! sha256sum -c "${BACKUP_FILE}.sha256"; then
    echo "$(date -Is) ERROR: SHA-256 verification failed for ${BACKUP_FILE}" >&2
    exit 1
  fi
fi

# gunzip -> psql; stop on first error
if gzip -dc "${BACKUP_FILE}" | sh -c "psql ${HOST_OPTS} -U '${POSTGRES_USER}' -d '${POSTGRES_DB}' --set=ON_ERROR_STOP=1"; then
  echo "$(date -Is) Restore completed successfully."
else
  echo "$(date -Is) Restore FAILED." >&2
  exit 1
fi
