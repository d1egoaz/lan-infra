#!/bin/sh
set -e

# Backup Portainer to restic repository
# Runs inside sidecar container

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# Check required env
if [ -z "$PORTAINER_USERNAME" ] || [ -z "$PORTAINER_PASSWORD" ]; then
  log "ERROR: PORTAINER_USERNAME and PORTAINER_PASSWORD must be set"
  exit 1
fi

if [ -z "$RESTIC_PASSWORD" ]; then
  log "ERROR: RESTIC_PASSWORD must be set"
  exit 1
fi

# Set restic repo default
RESTIC_REPOSITORY="${RESTIC_REPOSITORY:-/backups}"
export RESTIC_REPOSITORY
export RESTIC_PASSWORD

# Init restic repo if needed
if ! restic snapshots >/dev/null 2>&1; then
  log "Initializing restic repository at $RESTIC_REPOSITORY"
  restic init
fi

log "Starting Portainer backup"

# Auth with Portainer
log "Authenticating with Portainer at $PORTAINER_API_URL"
AUTH_TOKEN=$(curl -sSf -X POST \
  -H "Content-Type: application/json" \
  -d "{\"Username\":\"$PORTAINER_USERNAME\",\"Password\":\"$PORTAINER_PASSWORD\"}" \
  "$PORTAINER_API_URL/auth" 2>/dev/null | jq -r '.jwt // empty')

if [ -z "$AUTH_TOKEN" ]; then
  log "ERROR: Authentication failed"
  exit 1
fi

# Create temp file for backup
TEMP_FILE=$(mktemp)
trap 'rm -f "$TEMP_FILE"' EXIT

# Download backup
log "Downloading backup from Portainer"
if ! curl -sSf -X POST \
  -H "Authorization: Bearer $AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{}' \
  -o "$TEMP_FILE" \
  "$PORTAINER_API_URL/backup"; then
  log "ERROR: Failed to download backup"
  exit 1
fi

# Logout (best effort)
curl -s -X POST "$PORTAINER_API_URL/auth/logout" -H "Authorization: Bearer $AUTH_TOKEN" >/dev/null 2>&1 || true

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
