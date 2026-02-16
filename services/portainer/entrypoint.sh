#!/bin/sh
set -e

# Entrypoint for Portainer backup sidecar

log() {
  echo "[entrypoint] $*"
}

# Validate required env
if [ -z "$PORTAINER_API_KEY" ]; then
  log "ERROR: PORTAINER_API_KEY must be set"
  exit 1
fi

log "Portainer Backup Sidecar"
log "Schedule: $BACKUP_SCHEDULE"
log "Portainer API: $PORTAINER_API_URL"
log "Restic repo: $RESTIC_REPOSITORY"

# Create cron job
log "Setting up cron schedule: $BACKUP_SCHEDULE"
echo "$BACKUP_SCHEDULE /usr/local/bin/backup.sh >> /var/log/backup.log 2>&1" | crontab -

# Run initial backup immediately
log "Running initial backup..."
/usr/local/bin/backup.sh || log "Initial backup failed (will retry on schedule)"

# Start cron in foreground
log "Starting cron daemon"
exec crond -f -l 0 -L /var/log/cron.log
