#!/usr/bin/env sh
set -eu

# Required
: "${POSTGRES_USER:?Must set POSTGRES_USER}"
: "${POSTGRES_PASSWORD:?Must set POSTGRES_PASSWORD}"
: "${POSTGRES_DB:?Must set POSTGRES_DB}"

# Optional
OUT_DIR="${BACKUPS_DIR:-/backups}"
DATE="$(date +%Y%m%d)"
OUT_FILE="${OUT_DIR}/${POSTGRES_DB}-${DATE}.sql.gz"

# Optional connectivity (TCP) — if POSTGRES_HOST is set, use it; else socket/default
HOST_OPTS=""
[ -n "${POSTGRES_HOST:-}" ] && HOST_OPTS="$HOST_OPTS -h ${POSTGRES_HOST}"
[ -n "${POSTGRES_PORT:-}" ] && HOST_OPTS="$HOST_OPTS -p ${POSTGRES_PORT}"

# Ownership and perms (optional)
# BACKUP_CHOWN example: "1000:1000" or "backup:backup"
# BACKUP_CHMOD example: "0640"
CHOWN_TARGET="${BACKUP_CHOWN:-}"
CHMOD_MODE="${BACKUP_CHMOD:-}"

# Create target dir
mkdir -p "${OUT_DIR}"

export PGPASSWORD="${POSTGRES_PASSWORD}"

echo "$(date -Is) Starting backup of ${POSTGRES_DB} as ${POSTGRES_USER}${POSTGRES_HOST:+ on ${POSTGRES_HOST}}"

# Dump → gzip
if sh -c "pg_dump ${HOST_OPTS} -U '${POSTGRES_USER}' -d '${POSTGRES_DB}' --no-owner --no-privileges" \
  | gzip -9 > "${OUT_FILE}"; then
  echo "$(date -Is) Backup completed: ${OUT_FILE}"
else
  echo "$(date -Is) Backup FAILED" >&2
  exit 1
fi

# Write SHA-256 checksum alongside (always)
# Produces a file like: "<hash>  xwiki-YYYYMMDD.sql.gz"
sha256sum "${OUT_FILE}" > "${OUT_FILE}.sha256"

# Ownership/perms fix-up (best-effort; ignore if not permitted)
if [ -n "${CHOWN_TARGET}" ]; then
  chown -h "${CHOWN_TARGET}" "${OUT_FILE}" "${OUT_FILE}.sha256" 2>/dev/null || true
fi
if [ -n "${CHMOD_MODE}" ]; then
  chmod "${CHMOD_MODE}" "${OUT_FILE}" "${OUT_FILE}.sha256" 2>/dev/null || true
fi

echo "$(date -Is) Checksum written: ${OUT_FILE}.sha256"
