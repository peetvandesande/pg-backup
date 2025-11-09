#!/bin/sh
set -eu
# ------------------------------------------------------------
# pg-backup :: backup.sh
# - Creates a timestamped PostgreSQL dump (.sql[.gz|.bz2|.zst]).
# - Optionally includes cluster-level globals (roles, etc.).
# - Portable by default: --no-owner --no-privileges (configurable).
# - Busybox/Alpine/GNU userland friendly.
# - Booleans are 1/0 (VERIFY_SHA256, INCLUDE_GLOBALS).
# - chown/chmod apply automatically if CHOWN_UID/GID or CHMOD_MODE are provided.
# ------------------------------------------------------------
# Env vars:
#   POSTGRES_USER        (required)
#   POSTGRES_PASSWORD    (required)
#   POSTGRES_DB          (required)
#   POSTGRES_HOST        (default=db)
#   POSTGRES_PORT        (default=5432)
#
#   BACKUPS_DIR          (default=/backups)
#   BACKUP_NAME_PREFIX   (default: <POSTGRES_DB>-postgres)
#
#   COMPRESS             (default=gz) one of: gz | bz2 | zst | none
#   COMPRESS_LEVEL       (optional) e.g. 1..9 for gz/bz2, 1..22 for zstd
#   VERIFY_SHA256        (default=1)  1=write .sha256 next to dump
#
#   DUMP_NO_OWNER        (default=1)  1=add --no-owner to pg_dump
#   DUMP_NO_PRIVILEGES   (default=1)  1=add --no-privileges to pg_dump
#   INCLUDE_GLOBALS      (default=0)  1=prepend pg_dumpall --globals-only
#                                   (requires superuser privileges)
#
#   CHOWN_UID            (optional) numeric uid or name
#   CHOWN_GID            (optional) numeric gid or name
#   CHMOD_MODE           (optional) e.g., 0640
#
#   DATE_FMT             (default=%Y%m%d) UTC date for filename
# ------------------------------------------------------------

log() { printf "%s %s\n" "$(date -Is)" "$*"; }

# ---- inputs / defaults ------------------------------------------------------
PGUSER="${POSTGRES_USER:-}"
PGPASS="${POSTGRES_PASSWORD:-}"
PGDB="${POSTGRES_DB:-}"
PGHOST="${POSTGRES_HOST:-db}"
PGPORT="${POSTGRES_PORT:-5432}"

BACKUP_DIR="${BACKUPS_DIR:-/backups}"
PREFIX_DEFAULT="${PGDB:-db}-postgres"
PREFIX="${BACKUP_NAME_PREFIX:-$PREFIX_DEFAULT}"

COMPRESS="${COMPRESS:-gz}"            # gz | bz2 | zst | none
COMPRESS_LEVEL="${COMPRESS_LEVEL:-}"  # optional
VERIFY_SHA256="${VERIFY_SHA256:-1}"   # 1/0

DUMP_NO_OWNER="${DUMP_NO_OWNER:-1}"               # 1/0
DUMP_NO_PRIVILEGES="${DUMP_NO_PRIVILEGES:-1}"     # 1/0
INCLUDE_GLOBALS="${INCLUDE_GLOBALS:-0}"           # 1/0

CHOWN_UID="${CHOWN_UID:-}"
CHOWN_GID="${CHOWN_GID:-}"
CHMOD_MODE="${CHMOD_MODE:-}"

DATE_FMT="${DATE_FMT:-%Y%m%d}"

# ---- validate ---------------------------------------------------------------
[ -n "$PGUSER" ] || { log "ERROR: POSTGRES_USER is required"; exit 1; }
[ -n "$PGPASS" ] || { log "ERROR: POSTGRES_PASSWORD is required"; exit 1; }
[ -n "$PGDB"   ] || { log "ERROR: POSTGRES_DB is required"; exit 1; }
[ -d "$BACKUP_DIR" ] || mkdir -p "$BACKUP_DIR"

# ---- filename ---------------------------------------------------------------
TS="$(date -u +"$DATE_FMT")"
case "$COMPRESS" in
  gz)   EXT=".sql.gz"  ;;
  bz2)  EXT=".sql.bz2" ;;
  zst)  EXT=".sql.zst" ;;
  none) EXT=".sql"     ;;
  *)    log "ERROR: Invalid COMPRESS='$COMPRESS' (use gz|bz2|zst|none)"; exit 1 ;;
esac
OUT="${BACKUP_DIR%/}/${PREFIX}-${TS}${EXT}"
SHA="${OUT}.sha256"

log "Starting PostgreSQL dump → ${OUT}"

# ---- dump command -----------------------------------------------------------
export PGPASSWORD="$PGPASS"
PGCOMMON="-h $PGHOST -p $PGPORT -U $PGUSER"

PGDUMP_OPTS=""
[ "$DUMP_NO_OWNER" = "1" ] && PGDUMP_OPTS="$PGDUMP_OPTS --no-owner"
[ "$DUMP_NO_PRIVILEGES" = "1" ] && PGDUMP_OPTS="$PGDUMP_OPTS --no-privileges"

# If requested, prepend pg_dumpall --globals-only (roles, etc.)
GLOBAL_CMD=""
if [ "$INCLUDE_GLOBALS" = "1" ]; then
  # This requires that $PGUSER has superuser rights.
  GLOBAL_CMD="pg_dumpall $PGCOMMON --globals-only; echo; "
fi

# ---- run pg_dump (+optional globals) with compression -----------------------
case "$COMPRESS" in
  gz)
    if [ -n "$COMPRESS_LEVEL" ]; then
      sh -c "${GLOBAL_CMD}pg_dump $PGCOMMON -d '$PGDB' $PGDUMP_OPTS | gzip -c -${COMPRESS_LEVEL} > '$OUT'"
    else
      sh -c "${GLOBAL_CMD}pg_dump $PGCOMMON -d '$PGDB' $PGDUMP_OPTS | gzip -c > '$OUT'"
    fi
    ;;
  bz2)
    if [ -n "$COMPRESS_LEVEL" ]; then
      sh -c "${GLOBAL_CMD}pg_dump $PGCOMMON -d '$PGDB' $PGDUMP_OPTS | bzip2 -c -${COMPRESS_LEVEL} > '$OUT'"
    else
      sh -c "${GLOBAL_CMD}pg_dump $PGCOMMON -d '$PGDB' $PGDUMP_OPTS | bzip2 -c > '$OUT'"
    fi
    ;;
  zst)
    if command -v zstd >/dev/null 2>&1; then
      if [ -n "$COMPRESS_LEVEL" ]; then
        sh -c "${GLOBAL_CMD}pg_dump $PGCOMMON -d '$PGDB' $PGDUMP_OPTS | zstd -q -z -T0 -${COMPRESS_LEVEL} -o '$OUT'"
      else
        sh -c "${GLOBAL_CMD}pg_dump $PGCOMMON -d '$PGDB' $PGDUMP_OPTS | zstd -q -z -T0 -o '$OUT'"
      fi
    else
      log "ERROR: zstd not available in image; set COMPRESS=none|gz|bz2"
      exit 1
    fi
    ;;
  none)
    if [ "$INCLUDE_GLOBALS" = "1" ]; then
      # Write globals and DB dump into the same file
      sh -c "pg_dumpall $PGCOMMON --globals-only; pg_dump $PGCOMMON -d '$PGDB' $PGDUMP_OPTS" > "$OUT"
    else
      pg_dump $PGCOMMON -d "$PGDB" $PGDUMP_OPTS > "$OUT"
    fi
    ;;
esac

SIZE="$(du -h "$OUT" | awk '{print $1}')"
log "Dump written: $OUT ($SIZE)"

# ---- checksum ---------------------------------------------------------------
if [ "$VERIFY_SHA256" = "1" ]; then
  sha256sum "$OUT" > "$SHA"
  log "Wrote checksum file: $SHA"
fi

# ---- post-processing: chown/chmod -------------------------------------------
if [ -n "$CHOWN_UID" ] || [ -n "$CHOWN_GID" ]; then
  target_uid="${CHOWN_UID:-}"
  target_gid="${CHOWN_GID:-}"
  if [ -z "$target_uid" ] && [ -n "$target_gid" ]; then
    target_uid="$(id -u)"
  elif [ -n "$target_uid" ] && [ -z "$target_gid" ]; then
    target_gid="$(id -g)"
  fi

  if [ -n "$target_uid" ] && [ -n "$target_gid" ]; then
    chown "$target_uid:$target_gid" "$OUT" 2>/dev/null || true
    [ -f "$SHA" ] && chown "$target_uid:$target_gid" "$SHA" 2>/dev/null || true
    log "Set ownership to ${target_uid}:${target_gid}"
  fi
fi

if [ -n "${CHMOD_MODE:-}" ]; then
  chmod "$CHMOD_MODE" "$OUT" 2>/dev/null || true
  [ -f "$SHA" ] && chmod "$CHMOD_MODE" "$SHA" 2>/dev/null || true
  log "Set permissions to ${CHMOD_MODE}"
fi

log "PostgreSQL backup completed successfully."
