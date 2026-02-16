#!/bin/sh
set -e

# Entrypoint for Portainer backup sidecar
# Simple loop-based scheduling (no cron needed)

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

# Parse cron schedule (simple: "0 3 * * *" -> run at 3am daily)
# For simplicity, convert to seconds-based sleep if non-standard cron
# or just run immediately and sleep 24h for daily backups

run_backup() {
  log "Running backup..."
  /usr/local/bin/backup.sh || log "Backup failed, will retry"
}

# Run initial backup immediately
run_backup

# Simple daily loop (86400 seconds = 24 hours)
# Parse hour from BACKUP_SCHEDULE if possible
SCHEDULE_HOUR=$(echo "$BACKUP_SCHEDULE" | awk '{print $2}')
if [ -z "$SCHEDULE_HOUR" ] || [ "$SCHEDULE_HOUR" = "*" ]; then
  SCHEDULE_HOUR=3  # default to 3am
fi

log "Scheduling backups daily at ${SCHEDULE_HOUR}:00"

while true; do
  # Calculate seconds until next run
  CURRENT_HOUR=$(date +%H)
  CURRENT_MIN=$(date +%M)
  CURRENT_SEC=$(date +%S)
  
  # Seconds elapsed today
  ELAPSED=$((CURRENT_HOUR * 3600 + CURRENT_MIN * 60 + CURRENT_SEC))
  TARGET=$((SCHEDULE_HOUR * 3600))
  
  if [ "$ELAPSED" -lt "$TARGET" ]; then
    # Target is later today
    WAIT=$((TARGET - ELAPSED))
  else
    # Target is tomorrow
    WAIT=$((86400 - ELAPSED + TARGET))
  fi
  
  log "Next backup in $((WAIT / 3600))h $(((WAIT % 3600) / 60))m"
  sleep "$WAIT"
  
  run_backup
done
