#!/bin/sh
set -eu
# ------------------------------------------------------------
# pg-backup :: restore
# - Restores a PostgreSQL dump (.sql[.gz|.bz2|.zst]) into a target DB.
# - When dumps include pg_dumpall --globals-only, roles are recreated too.
# - Defaults to portable restore by stripping owner/ACL lines (configurable).
# - NEW: Ignores "role ... already exists" errors so you can restore onto
#        an existing cluster without failing hard.
# ------------------------------------------------------------
# Usage:
#   restore [<dump_file_or_dir>] [<dbname>]
#     - If <dump_file_or_dir> is a directory or empty, selects newest .sql*
#       by BACKUP_NAME_PREFIX.
#
# Env vars:
#   POSTGRES_USER        (required)
#   POSTGRES_PASSWORD    (required)
#   POSTGRES_DB          (default: same as provided arg or env)
#   POSTGRES_HOST        (default=db)
#   POSTGRES_PORT        (default=5432)
#
#   BACKUPS_DIR          (default=/backups)
#   BACKUP_NAME_PREFIX   (optional, default=$POSTGRES_DB-postgres)
#
#   RESTORE_STRIP_ACL    (default=1)  # 1=strip ALTER OWNER/GRANT/REVOKE
#   PSQL_ON_ERROR_STOP   (default=0)  # 0=continue on errors, 1=stop on first
# ------------------------------------------------------------

log() { printf "%s %s\n" "$(date -Is)" "$*"; }

PGUSER="${POSTGRES_USER:-}"
PGPASS="${POSTGRES_PASSWORD:-}"
PGHOST="${POSTGRES_HOST:-db}"
PGPORT="${POSTGRES_PORT:-5432}"
PGDB_ENV="${POSTGRES_DB:-}"

BACKUP_DIR="${BACKUPS_DIR:-/backups}"
PREFIX="${BACKUP_NAME_PREFIX:-$PGDB_ENV-postgres}"

RESTORE_STRIP_ACL="${RESTORE_STRIP_ACL:-1}"
# Default to 0 so we can continue past "role already exists" and still
# restore the main DB contents.
PSQL_ON_ERROR_STOP="${PSQL_ON_ERROR_STOP:-0}"

[ -n "$PGUSER" ] || { log "ERROR: POSTGRES_USER is required"; exit 1; }
[ -n "$PGPASS" ] || { log "ERROR: POSTGRES_PASSWORD is required"; exit 1; }

export PGPASSWORD="$PGPASS"

# ---- locate dump ------------------------------------------------------------
DUMP_PATH="${1:-}"           # optional: file or directory
TARGET_DB="${2:-$PGDB_ENV}"  # optional; fallback to env

if [ -z "$DUMP_PATH" ] || [ -d "$DUMP_PATH" ]; then
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

if [ -z "$TARGET_DB" ]; then
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
if [ "$PSQL_ON_ERROR_STOP" = "1" ]; then
  ON_ERROR="-v ON_ERROR_STOP=1"
else
  ON_ERROR="-v ON_ERROR_STOP=0"
fi

log "Restoring into database: $TARGET_DB"

TMP_LOG="$(mktemp /tmp/pg-restore-XXXXXX.log)"

set +e
if [ "$RESTORE_STRIP_ACL" = "1" ]; then
  # Strip most owner/ACL-related lines for portability
  $DECOMPRESSOR "$DUMP_FILE" \
    | sed -E '/^ALTER .* OWNER TO /d; /^GRANT /d; /^REVOKE /d' \
    | psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" $ON_ERROR "$TARGET_DB" 2>"$TMP_LOG"
else
  $DECOMPRESSOR "$DUMP_FILE" \
    | psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" $ON_ERROR "$TARGET_DB" 2>"$TMP_LOG"
fi
rc=$?
set -e

if [ $rc -ne 0 ]; then
  # If the only issues are "role ... already exists", treat as success.
  if grep -q 'ERROR:  role ".*" already exists' "$TMP_LOG"; then
    log 'Role(s) already existed; ignoring "role ... already exists" errors.'
    rc=0
  else
    log "psql reported errors during restore:"
    sed 's/^/psql: /' "$TMP_LOG" >&2
    log "Restore FAILED."
  fi
fi

rm -f "$TMP_LOG"

if [ $rc -ne 0 ]; then
  exit $rc
fi

log "Restore completed successfully."
