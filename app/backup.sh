#!/bin/sh
set -eu

# Simple logger with ISO timestamp
log() { printf "%s %s\n" "$(date -Is)" "$*" ; }

# Trim leading/trailing single/double quotes
_normalize() {
  v="$1"
  v="${v#\'}"; v="${v%\' }"; v="${v%\' }"; v="${v%\' }"
  v="${v%\' }"; v="${v#\"}"; v="${v%\"}"
  printf '%s' "$v"
}

# Required
: "${POSTGRES_USER:?Must set POSTGRES_USER}"
: "${POSTGRES_PASSWORD:?Must set POSTGRES_PASSWORD}"
: "${POSTGRES_DB:?Must set POSTGRES_DB}"

# Optional
OUT_DIR="${BACKUP_DEST:-/backups}"
PREFIX="${BACKUP_NAME_PREFIX:-$POSTGRES_DB}"
CHOWN_TARGET="${BACKUP_CHOWN:-}"
CHMOD_TARGET="${BACKUP_CHMOD:-}"

# Deduct and sanitise values
CHOWN_TARGET="$(_normalize "$CHOWN_TARGET")"
CHMOD_TARGET="$(_normalize "$CHMOD_TARGET")"
case "$CHOWN_TARGET" in
  *[!A-Za-z0-9:._-]* ) log "WARN: ignoring unsafe BACKUP_CHOWN='$CHOWN_TARGET'"; CHOWN_TARGET="";;
esac
case "$CHMOD_TARGET" in
  ""|[0-7][0-7][0-7]|[0-7][0-7][0-7][0-7]) : ;;
  * ) log "WARN: ignoring unsafe BACKUP_CHMOD='$CHMOD_TARGET'"; CHMOD_TARGET="";;
esac
DATE="$(date +%Y%m%d)"
OUT_BASENAME="${PREFIX}-${DATE}.sql.gz"
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
sha256sum "$OUT_PATH" > "${OUT_PATH}.sha256"
log "Checksum written: ${OUT_PATH}.sha256"

# Apply ownership / permissions
if [ -n "${CHOWN_TARGET}" ]; then
  if chown -h "${CHOWN_TARGET}" "${OUT_PATH}" "${OUT_PATH}.sha256" 2>/dev/null; then
    log "Set ownership to ${CHOWN_TARGET}"
  else
    log "WARNING: Failed to set ownership to ${CHOWN_TARGET}"
  fi
fi

if [ -n "${CHMOD_TARGET}" ]; then
  if chmod "${CHMOD_TARGET}" "${OUT_PATH}" "${OUT_PATH}.sha256" 2>/dev/null; then
    log "Set permissions to ${CHMOD_TARGET}"
  else
    log "WARNING: Failed to set permissions to ${CHMOD_TARGET}"
  fi
fi

SIZE="$(du -h "$OUT_PATH" | awk '{print $1}')"
log "Backup complete (${SIZE})"
