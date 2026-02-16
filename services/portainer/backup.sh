#!/bin/sh
set -e

# Backup Portainer to restic repository
# Runs inside sidecar container

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# Check required env
if [ -z "$PORTAINER_API_KEY" ]; then
  log "ERROR: PORTAINER_API_KEY must be set"
  exit 1
fi

# Init restic repo if needed
if ! restic snapshots >/dev/null 2>&1; then
  log "Initializing restic repository at $RESTIC_REPOSITORY"
  restic init
fi

log "Starting Portainer backup"

# Create temp file for backup
TEMP_FILE=$(mktemp)
trap 'rm -f "$TEMP_FILE"' EXIT

# Download backup using API key
log "Downloading backup from Portainer"
if ! curl -sSf -X POST \
  -H "X-API-Key: $PORTAINER_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{}' \
  -o "$TEMP_FILE" \
  "$PORTAINER_API_URL/backup"; then
  log "ERROR: Failed to download backup"
  exit 1
fi

# Verify backup
if [ ! -s "$TEMP_FILE" ]; then
  log "ERROR: Backup file is empty"
  exit 1
fi

# Backup to restic
log "Storing backup in restic"
if restic backup "$TEMP_FILE" --tag portainer --stdin-filename "portainer_backup.tar.gz"; then
  log "Backup completed successfully"
else
  log "ERROR: Restic backup failed"
  exit 1
fi

# Apply retention policy
log "Applying retention: daily=$KEEP_DAILY weekly=$KEEP_WEEKLY monthly=$KEEP_MONTHLY"
restic forget --tag portainer \
  --keep-daily "$KEEP_DAILY" \
  --keep-weekly "$KEEP_WEEKLY" \
  --keep-monthly "$KEEP_MONTHLY" \
  --prune

log "Backup and cleanup completed"
