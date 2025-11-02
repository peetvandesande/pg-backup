#!/bin/sh
set -eu

log() { printf "%s %s\n" "$(date -Is)" "$*" ; }

# ---------------------------------------------------------------------
# Environment
# ---------------------------------------------------------------------
BACKUP_DEST="${BACKUP_DEST:-/backups}"
RUN_BACKUP_ON_START="${RUN_BACKUP_ON_START:-false}" # true = run before cron
RUN_ONCE="${RUN_ONCE:-false}"                       # true = run once and exit
BACKUP_CHOWN="${BACKUP_CHOWN:-}"                    # e.g. "1000:1000"
BACKUP_CHMOD="${BACKUP_CHMOD:-}"                    # e.g. "0640"

# ---------------------------------------------------------------------
# Ensure backups dir exists and is writable
# ---------------------------------------------------------------------
if [ ! -d "$BACKUP_DEST" ]; then
  log "Creating backups dir: $BACKUP_DEST"
  mkdir -p "$BACKUP_DEST"
fi

# Test writability
if ! sh -c "touch '$BACKUP_DEST/.write_test' && rm -f '$BACKUP_DEST/.write_test'"; then
  log "ERROR: $BACKUP_DEST is not writable. Check bind mount or permissions."
  exit 1
fi

# ---------------------------------------------------------------------
# RUN_ONCE mode — one-shot backup and exit
# ---------------------------------------------------------------------
if [ "$RUN_ONCE" = "true" ]; then
  log "RUN_ONCE=true -> performing single backup then exiting"
  if /usr/local/bin/backup; then
    log "Backup completed successfully (RUN_ONCE)"
    exit 0
  else
    log "Backup FAILED (RUN_ONCE)"
    exit 1
  fi
fi

# ---------------------------------------------------------------------
# Optional immediate backup before cron
# ---------------------------------------------------------------------
if [ "$RUN_BACKUP_ON_START" = "true" ]; then
  log "RUN_BACKUP_ON_START=true -> running initial backup..."
  if ! /usr/local/bin/backup; then
    log "Initial backup FAILED (continuing to cron)"
  else
    log "Initial backup completed"
  fi
fi

# ---------------------------------------------------------------------
# Default: Start cron in foreground
# ---------------------------------------------------------------------
CROND_BIN="$(command -v crond)"
echo "[entrypoint] Starting crond ($CROND_BIN)…"
exec "$CROND_BIN" -f -l 2 /dev/stdout

