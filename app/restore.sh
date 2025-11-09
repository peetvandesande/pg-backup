#!/bin/sh
set -eu
# ------------------------------------------------------------
# pg-backup :: restore
# - Restores a PostgreSQL dump (.sql[.gz|.bz2|.zst]) into a target DB.
# - When dumps include pg_dumpall --globals-only, roles are recreated too.
# - Defaults to portable restore by stripping owner/ACL lines (configurable).
# ------------------------------------------------------------
# Usage:
#   restore [<dump_file_or_dir>] [<dbname>]
#     - If <dump_file_or_dir> is a directory or empty, selects newest .sql* by BACKUP_NAME_PREFIX.
#
# Env vars:
#   POSTGRES_USER        (required)  # user used to connect for restore (ideally superuser)
#   POSTGRES_PASSWORD    (required)
#   POSTGRES_DB          (default: same as provided arg or env)
#   POSTGRES_HOST        (default=db)
#   POSTGRES_PORT        (default=5432)
#
#   BACKUPS_DIR          (default=/backups)  # used when searching for newest
#   BACKUP_NAME_PREFIX   (optional, default=$POSTGRES_DB-postgres)
#
#   RESTORE_STRIP_ACL    (default=1)         # 1=strip ALTER OWNER/GRANT/REVOKE lines
#   PSQL_ON_ERROR_STOP   (default=1)         # fail fast on first SQL error
# ------------------------------------------------------------

log() { printf "%s %s\n" "$(date -Is)" "$*"; }

PGUSER="${POSTGRES_USER:-}"
PGPASS="${POSTGRES_PASSWORD:-}"
PGHOST="${POSTGRES_HOST:-db}"
PGPORT="${POSTGRES_PORT:-5432}"
PGDB_ENV="${POSTGRES_DB:-}"

BACKUP_DIR="${BACKUPS_DIR:-/backups}"
PREFIX="${BACKUP_NAME_PREFIX:-$POSTGRES_DB-postgres}"
RESTORE_STRIP_ACL="${RESTORE_STRIP_ACL:-1}"
PSQL_ON_ERROR_STOP="${PSQL_ON_ERROR_STOP:-1}"

[ -n "$PGUSER" ] || { log "ERROR: POSTGRES_USER is required"; exit 1; }
[ -n "$PGPASS" ] || { log "ERROR: POSTGRES_PASSWORD is required"; exit 1; }

export PGPASSWORD="$PGPASS"

# ---- locate dump ------------------------------------------------------------
DUMP_PATH="${1:-}"           # optional: file or directory
TARGET_DB="${2:-$PGDB_ENV}"  # optional; fallback to env

if [ -z "$DUMP_PATH" ] || [ -d "$DUMP_PATH" ]; then
  # search newest in BACKUPS_DIR by prefix (if provided) or any .sql*
  search_dir="${DUMP_PATH:-$BACKUP_DIR}"
  log "Scanning for newest archive in: $search_dir"
  if [ -n "$PREFIX" ]; then
    newest="$(ls -1t "$search_dir"/"$PREFIX-"*.sql* 2>/dev/null | head -n1 || true)"
  else
    newest="$(ls -1t "$search_dir"/*.sql* 2>/dev/null | head -n1 || true)"
  fi
  DUMP_FILE="${newest:-}"
else
  DUMP_FILE="$DUMP_PATH"
fi

[ -n "${DUMP_FILE:-}" ] || { log "ERROR: No dump file found. Provide a path or ensure backups exist."; exit 1; }
[ -f "$DUMP_FILE" ] || { log "ERROR: Dump file does not exist: $DUMP_FILE"; exit 1; }

log "Selected dump: $DUMP_FILE"

# infer db name if not provided
if [ -z "$TARGET_DB" ]; then
  # try to derive from prefix in filename: <prefix>-YYYYMMDD.sql[.*]
  base="$(basename "$DUMP_FILE")"
  TARGET_DB="${base%%-*}"
  log "Inferred target database: $TARGET_DB"
fi

[ -n "$TARGET_DB" ] || { log "ERROR: Target database name not provided or inferable."; exit 1; }

# ---- checksum ---------------------------------------------------------------
SHA="${DUMP_FILE}.sha256"
if [ -f "$SHA" ]; then
  log "Verifying checksum: $SHA"
  sha256sum -c "$SHA" >/dev/null
fi

# ---- decompressor -----------------------------------------------------------
DECOMPRESSOR="cat"
case "$DUMP_FILE" in
  *.sql.gz)  DECOMPRESSOR="zcat"  ;;
  *.sql.bz2) DECOMPRESSOR="bzcat" ;;
  *.sql.zst) DECOMPRESSOR="zstd -d -c" ;;
  *.sql)     DECOMPRESSOR="cat"   ;;
  *)
    log "ERROR: Unknown dump file extension: $DUMP_FILE"
    exit 1
    ;;
esac

# ---- restore ---------------------------------------------------------------
ON_ERROR=""
[ "$PSQL_ON_ERROR_STOP" = "1" ] && ON_ERROR="-v ON_ERROR_STOP=1"

log "Restoring into database: $TARGET_DB"

set +e
if [ "$RESTORE_STRIP_ACL" = "1" ]; then
  # Strip most owner/ACL-related lines for portability
  $DECOMPRESSOR "$DUMP_FILE" \
    | sed -E '/^ALTER .* OWNER TO /d; /^GRANT /d; /^REVOKE /d' \
    | psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" $ON_ERROR "$TARGET_DB"
else
  $DECOMPRESSOR "$DUMP_FILE" \
    | psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" $ON_ERROR "$TARGET_DB"
fi
rc=$?
set -e

if [ $rc -ne 0 ]; then
  log "Restore FAILED."
  exit $rc
fi

log "Restore completed successfully."
