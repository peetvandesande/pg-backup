#!/bin/sh
set -eu

# Simple logger with ISO timestamp
log() { printf "%s %s\n" "$(date -Is)" "$*"; }

# Required
: "${POSTGRES_USER:?Must set POSTGRES_USER}"
: "${POSTGRES_PASSWORD:?Must set POSTGRES_PASSWORD}"
: "${POSTGRES_DB:?Must set POSTGRES_DB}"

# Optional
OUT_DIR="${BACKUP_DEST:-/backups}"
CHOWN_TARGET="${BACKUP_CHOWN:-}"
CHMOD_TARGET="${BACKUP_CHMOD:-}"

# Deduct values
DATE="$(date +%Y%m%d)"
OUT_BASENAME="${POSTGRES_DB}-${DATE}.sql.gz"
OUT_PATH="${OUT_DIR}/${OUT_BASENAME}"

# Optional connectivity (TCP) — if POSTGRES_HOST is set, use it; else socket/default
HOST_OPTS=""
[ -n "${POSTGRES_HOST:-}" ] && HOST_OPTS="$HOST_OPTS -h ${POSTGRES_HOST}"
[ -n "${POSTGRES_PORT:-}" ] && HOST_OPTS="$HOST_OPTS -p ${POSTGRES_PORT}"


export PGPASSWORD="${POSTGRES_PASSWORD}"

log "Starting backup of ${POSTGRES_DB} as ${POSTGRES_USER}${POSTGRES_HOST:+ on ${POSTGRES_HOST}}"

# Dump → gzip
if sh -c "pg_dump ${HOST_OPTS} -U '${POSTGRES_USER}' -d '${POSTGRES_DB}' --no-owner --no-privileges" \
  | gzip -9 > "${OUT_PATH}"; then
  log "Backup completed: ${OUT_PATH}"
else
  echo "$(date -Is) Backup FAILED" >&2
  exit 1
fi

# Create checksum
cd "$OUT_DIR" && sha256sum "$OUT_BASENAME" > "${OUT_BASENAME}.sha256"
log "Checksum written: ${OUT_BASENAME}.sha256"

# Apply ownership / permissions
if [ -n "${CHOWN_TARGET}" ]; then
  log "Setting ownership to ${CHOWN_TARGET}"
  chown -h "${CHOWN_TARGET}" "${OUT_PATH}" "${OUT_PATH}.sha256" 2>/dev/null || true
fi

if [ -n "${CHMOD_TARGET}" ]; then
  log "Setting permissions to ${CHMOD_TARGET}"
  chmod "${CHMOD_TARGET}" "${OUT_PATH}" "${OUT_PATH}.sha256" 2>/dev/null || true
fi

SIZE="$(du -h "$OUT_PATH" | awk '{print $1}')"
log "Backup complete (${SIZE})"
