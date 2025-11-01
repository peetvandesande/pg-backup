#!/usr/bin/env sh
set -eu

log() { printf "%s %s\n" "$(date -Is)" "$*" ; }

# ---------------------------------------------------------------------
# Environment
# ---------------------------------------------------------------------
BACKUPS_DIR="${BACKUPS_DIR:-/backups}"
RUN_BACKUP_ON_START="${RUN_BACKUP_ON_START:-0}"   # 1 = run before cron
RUN_ONCE="${RUN_ONCE:-0}"                         # 1 = run once and exit
TZ="${TZ:-UTC}"                                   # timezone (default UTC)
BACKUP_CHOWN="${BACKUP_CHOWN:-}"                  # e.g. "1000:1000"
BACKUP_CHMOD="${BACKUP_CHMOD:-}"                  # e.g. "0640"

# ---------------------------------------------------------------------
# Timezone setup
# ---------------------------------------------------------------------
if [ -f "/usr/share/zoneinfo/$TZ" ]; then
  log "Setting timezone to $TZ"
  ln -sf "/usr/share/zoneinfo/$TZ" /etc/localtime
  echo "$TZ" > /etc/timezone
else
  log "WARNING: Unknown timezone '$TZ', keeping default (UTC)"
fi

# ---------------------------------------------------------------------
# Ensure backups dir exists and is writable
# ---------------------------------------------------------------------
if [ ! -d "$BACKUPS_DIR" ]; then
  log "Creating backups dir: $BACKUPS_DIR"
  mkdir -p "$BACKUPS_DIR"
fi

# Ownership / permissions
if [ -n "$BACKUP_CHOWN" ]; then
  chown -h "$BACKUP_CHOWN" "$BACKUPS_DIR" 2>/dev/null || true
fi
if [ -n "$BACKUP_CHMOD" ]; then
  chmod "$BACKUP_CHMOD" "$BACKUPS_DIR" 2>/dev/null || true
fi

# Test writability
if ! sh -c "touch '$BACKUPS_DIR/.write_test' && rm -f '$BACKUPS_DIR/.write_test'"; then
  log "ERROR: $BACKUPS_DIR is not writable. Check bind mount or permissions."
  exit 1
fi

# ---------------------------------------------------------------------
# RUN_ONCE mode — one-shot backup and exit
# ---------------------------------------------------------------------
if [ "$RUN_ONCE" = "1" ]; then
  log "RUN_ONCE=1 -> performing single backup then exiting"
  if /usr/local/bin/pg-backup; then
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
if [ "$RUN_BACKUP_ON_START" = "1" ]; then
  log "RUN_BACKUP_ON_START=1 -> running initial backup..."
  if ! /usr/local/bin/pg-backup; then
    log "Initial backup FAILED (continuing to cron)"
  else
    log "Initial backup completed"
  fi
fi

# ---------------------------------------------------------------------
# Start cron in foreground
# ---------------------------------------------------------------------
log "Starting dcron in foreground..."
exec crond -f -L /dev/stdout
