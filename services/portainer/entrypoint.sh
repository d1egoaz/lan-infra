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

if [ -z "$RESTIC_PASSWORD" ]; then
  log "ERROR: RESTIC_PASSWORD must be set"
  exit 1
fi

log "Portainer Backup Sidecar"
log "Schedule: $BACKUP_SCHEDULE"
log "Portainer API: $PORTAINER_API_URL"
log "Restic repo: $RESTIC_REPOSITORY"

# Create cron job (output to container stdout so 'docker logs' works)
log "Setting up cron schedule: $BACKUP_SCHEDULE"
echo "$BACKUP_SCHEDULE /usr/local/bin/backup.sh >> /proc/1/fd/1 2>&1" | crontab -

# Run initial backup immediately
log "Running initial backup..."
/usr/local/bin/backup.sh || log "Initial backup failed (will retry on schedule)"

# Start cron in foreground (log to stdout for docker logs)
log "Starting cron daemon"
exec crond -f -l 0 -L /proc/1/fd/1
