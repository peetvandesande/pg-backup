#!/bin/sh
set -eu

log() { printf "%s %s\n" "$(date -Is)" "$*"; }

# Required
: "${POSTGRES_USER:?Must set POSTGRES_USER}"
: "${POSTGRES_PASSWORD:?Must set POSTGRES_PASSWORD}"
: "${POSTGRES_DB:?Must set POSTGRES_DB}"

# Optional
POSTGRES_HOST="${POSTGRES_HOST:-db}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
BACKUP_DIR="${BACKUPS_DIR:-/backups}"
PREFIX="${BACKUP_NAME_PREFIX:-postgres-${POSTGRES_DB}}"

VERIFY_SHA256="${VERIFY_SHA256:-1}"   # 1/0
COMPRESS="${COMPRESS:-gz}"            # gz|zst|bz2|none
COMPRESS_LEVEL="${COMPRESS_LEVEL:-}"  # optional

CHOWN_UID="${CHOWN_UID:-}"
CHOWN_GID="${CHOWN_GID:-}"
CHMOD_MODE="${CHMOD_MODE:-}"

DATE_FMT="${DATE_FMT:-%Y%m%d}"
TS="$(date -u +"$DATE_FMT")"

case "$COMPRESS" in
  gz)   EXT=".sql.gz"  ;;
  bz2)  EXT=".sql.bz2" ;;
  zst)  EXT=".sql.zst" ;;
  none) EXT=".sql"     ;;
  *)    log "ERROR: Invalid COMPRESS='$COMPRESS'"; exit 1 ;;
esac

mkdir -p "$BACKUP_DIR"
OUT_PATH="${BACKUP_DIR%/}/${PREFIX}-${TS}${EXT}"
SHA_PATH="${OUT_PATH}.sha256"

log "Starting PostgreSQL backup of '${POSTGRES_DB}' to ${OUT_PATH}"

export PGPASSWORD="${POSTGRES_PASSWORD}"

# Build base pg_dump cmd
PGDUMP_BASE="pg_dump -h '${POSTGRES_HOST}' -p '${POSTGRES_PORT}' -U '${POSTGRES_USER}' -d '${POSTGRES_DB}' --no-owner --no-privileges --clean --if-exists"

# Run pg_dump with compression
case "$COMPRESS" in
  gz)
    if [ -n "$COMPRESS_LEVEL" ]; then
      sh -c "$PGDUMP_BASE" | gzip -${COMPRESS_LEVEL} > "$OUT_PATH"
    else
      sh -c "$PGDUMP_BASE" | gzip > "$OUT_PATH"
    fi
    ;;
  bz2)
    if [ -n "$COMPRESS_LEVEL" ]; then
      sh -c "$PGDUMP_BASE" | bzip2 -${COMPRESS_LEVEL} > "$OUT_PATH"
    else
      sh -c "$PGDUMP_BASE" | bzip2 > "$OUT_PATH"
    fi
    ;;
  zst)
    if [ -n "$COMPRESS_LEVEL" ]; then
      sh -c "$PGDUMP_BASE" | zstd -q -${COMPRESS_LEVEL} -o "$OUT_PATH"
    else
      sh -c "$PGDUMP_BASE" | zstd -q -o "$OUT_PATH"
    fi
    ;;
  none)
      sh -c "$PGDUMP_BASE" > "$OUT_PATH"
    ;;
esac

if [ "$VERIFY_SHA256" = "1" ]; then
  if sha256sum "$OUT_PATH" > "$SHA_PATH"; then
    log "Checksum written: $(basename "$SHA_PATH")"
  else
    log "WARNING: failed to write checksum"
  fi
fi

# Apply ownership/permissions if provided
if [ -n "$CHOWN_UID" ] && [ -n "$CHOWN_GID" ]; then
  chown "$CHOWN_UID:$CHOWN_GID" "$OUT_PATH" 2>/dev/null || true
  [ -f "$SHA_PATH" ] && chown "$CHOWN_UID:$CHOWN_GID" "$SHA_PATH" 2>/dev/null || true
  log "Set ownership to ${CHOWN_UID}:${CHOWN_GID}"
fi

if [ -n "$CHMOD_MODE" ]; then
  chmod "$CHMOD_MODE" "$OUT_PATH" 2>/dev/null || true
  [ -f "$SHA_PATH" ] && chmod "$CHMOD_MODE" "$SHA_PATH" 2>/dev/null || true
  log "Set permissions to ${CHMOD_MODE}"
fi

SIZE="$(du -h "$OUT_PATH" | awk '{print $1}')"
log "Backup complete (${SIZE})"
