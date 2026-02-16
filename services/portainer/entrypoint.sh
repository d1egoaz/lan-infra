#!/bin/sh
set -e

# Entrypoint for Portainer backup sidecar
# Sets up cron and runs backup on schedule

log() {
  echo "[entrypoint] $*"
}

# Validate required env
if [ -z "$PORTAINER_USERNAME" ] || [ -z "$PORTAINER_PASSWORD" ]; then
  log "ERROR: PORTAINER_USERNAME and PORTAINER_PASSWORD must be set"
  exit 1
fi

if [ -z "$RESTIC_PASSWORD" ]; then
  log "ERROR: RESTIC_PASSWORD must be set"
  exit 1
fi

log "Portainer Backup Sidecar"
log "Schedule: $BACKUP_SCHEDULE"
log "Portainer API: $PORTAINER_API_URL"
log "Restic repo: ${RESTIC_REPOSITORY:-/backups}"

# Create cron job
log "Setting up cron schedule: $BACKUP_SCHEDULE"
echo "$BACKUP_SCHEDULE /usr/local/bin/backup.sh >> /var/log/backup.log 2>&1" | crontab -

# Run initial backup immediately
log "Running initial backup..."
/usr/local/bin/backup.sh || log "Initial backup failed (will retry on schedule)"

# Start cron in foreground
log "Starting cron daemon"
exec crond -f -l 0 -L /var/log/cron.log
