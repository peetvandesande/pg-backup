#!/bin/sh
set -eu

log() { printf "%s %s\n" "$(date -Is)" "$*"; }

# Required for DB connection
: "${POSTGRES_USER:?Must set POSTGRES_USER}"
: "${POSTGRES_PASSWORD:?Must set POSTGRES_PASSWORD}"
: "${POSTGRES_DB:?Must set POSTGRES_DB}"

POSTGRES_HOST="${POSTGRES_HOST:-db}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"

BACKUP_DIR="${BACKUPS_DIR:-/backups}"
PREFIX="${BACKUP_NAME_PREFIX:-postgres-${POSTGRES_DB}}"
VERIFY="${VERIFY_SHA256:-1}"   # 1 = verify if .sha256 exists; 0 = skip

# Busybox-friendly newest-file resolver
find_latest() {
  tmp="$(mktemp)"
  for pat in \
    "$BACKUP_DIR/${PREFIX}*.sql.gz" \
    "$BACKUP_DIR/${PREFIX}*.sql.bz2" \
    "$BACKUP_DIR/${PREFIX}*.sql.zst" \
    "$BACKUP_DIR/${PREFIX}*.sql"
  do
    for f in $pat; do
      [ -e "$f" ] || continue
      printf '%s\0' "$f" >> "$tmp"
    done
  done
  if [ -s "$tmp" ]; then
    CANDIDATE="$(xargs -0 ls -1t 2>/dev/null <"$tmp" | head -n1 || true)"
    rm -f "$tmp"
    [ -n "${CANDIDATE:-}" ] && printf '%s\n' "$CANDIDATE" || return 1
  else
    rm -f "$tmp"
    return 1
  fi
}

# Resolve backup file (arg or latest)
ARG_FILE="${1:-}"
BACKUP_FILE=""
if [ -n "$ARG_FILE" ]; then
  [ -f "$ARG_FILE" ] || { log "ERROR: Provided file does not exist: $ARG_FILE"; exit 1; }
  BACKUP_FILE="$ARG_FILE"
  log "Using explicit backup file: $BACKUP_FILE"
else
  log "PREFIX: ${PREFIX:-<none>}"
  log "Scanning for newest archive in: $BACKUP_DIR"
  CANDIDATE="$(find_latest || true)"
  if [ -n "${CANDIDATE:-}" ] && [ -f "$CANDIDATE" ]; then
    BACKUP_FILE="$CANDIDATE"
    log "Selected newest archive: $BACKUP_FILE"
  else
    log "ERROR: Backup file '' not found. Provide a file path or ensure historical backups exist." >&2
    exit 1
  fi
fi

# Verify checksum if requested
if [ "$VERIFY" = "1" ] && [ -f "${BACKUP_FILE}.sha256" ]; then
  log "Verifying checksum: ${BACKUP_FILE}.sha256"
  if ! sha256sum -c "${BACKUP_FILE}.sha256"; then
    log "ERROR: SHA-256 verification failed for ${BACKUP_FILE}" >&2
    exit 1
  fi
fi

export PGPASSWORD="${POSTGRES_PASSWORD}"
HOST_OPTS="-h '${POSTGRES_HOST}' -p '${POSTGRES_PORT}'"

# Decompress and restore with ON_ERROR_STOP
case "$BACKUP_FILE" in
  *.sql.gz)
    if gzip -dc "${BACKUP_FILE}" | sh -c "psql ${HOST_OPTS} -U '${POSTGRES_USER}' -d '${POSTGRES_DB}' --set=ON_ERROR_STOP=1"; then
      log "Restore completed successfully."
    else
      log "Restore FAILED." >&2; exit 1
    fi
    ;;
  *.sql.bz2)
    if bzip2 -dc "${BACKUP_FILE}" | sh -c "psql ${HOST_OPTS} -U '${POSTGRES_USER}' -d '${POSTGRES_DB}' --set=ON_ERROR_STOP=1"; then
      log "Restore completed successfully."
    else
      log "Restore FAILED." >&2; exit 1
    fi
    ;;
  *.sql.zst)
    if zstd -dc "${BACKUP_FILE}" | sh -c "psql ${HOST_OPTS} -U '${POSTGRES_USER}' -d '${POSTGRES_DB}' --set=ON_ERROR_STOP=1"; then
      log "Restore completed successfully."
    else
      log "Restore FAILED." >&2; exit 1
    fi
    ;;
  *.sql)
    if sh -c "psql ${HOST_OPTS} -U '${POSTGRES_USER}' -d '${POSTGRES_DB}' --set=ON_ERROR_STOP=1" < "${BACKUP_FILE}"; then
      log "Restore completed successfully."
    else
      log "Restore FAILED." >&2; exit 1
    fi
    ;;
  *)
    log "ERROR: Unsupported backup extension: $BACKUP_FILE" >&2; exit 1
    ;;
esac
