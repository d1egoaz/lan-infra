#!/bin/bash
#
# Entrypoint: Sets up cron and runs backup scheduler
#

set -euo pipefail

SCHEDULE="${BACKUP_SCHEDULE:-0 3 * * *}"
BACKUP_DIR="${BACKUP_DIR:-/backups}"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log "Portainer Backup Service"
log "========================"
log "Schedule: $SCHEDULE"
log "Backup dir: $BACKUP_DIR"
log "Portainer: $PORTAINER_URL"
log "Retention: ${RETENTION_DAILY}d/${RETENTION_WEEKLY}w/${RETENTION_MONTHLY}m"

# Setup crontab with proper environment
{
    echo "SHELL=/bin/sh"
    echo "PATH=/usr/local/bin:/usr/bin:/bin"
    echo "BACKUP_DIR=$BACKUP_DIR"
    echo "PORTAINER_URL=$PORTAINER_URL"
    echo "PORTAINER_API_KEY=$PORTAINER_API_KEY"
    echo "SSL_VERIFY=${SSL_VERIFY:-false}"
    echo "RETENTION_DAILY=${RETENTION_DAILY:-7}"
    echo "RETENTION_WEEKLY=${RETENTION_WEEKLY:-28}"
    echo "RETENTION_MONTHLY=${RETENTION_MONTHLY:-90}"
    echo "PRE_BACKUP_HOOK=${PRE_BACKUP_HOOK:-}"
    echo "POST_BACKUP_HOOK=${POST_BACKUP_HOOK:-}"
    # Fix: Removed redirection to prevent double logging.
    # The script handles its own logging via tee.
    echo "$SCHEDULE /scripts/backup.sh"
} | crontab -

log "Cron schedule installed"

# First-run immediate backup (for testing)
if [[ "${FIRST_RUN:-false}" == "true" ]]; then
    log "FIRST_RUN enabled - executing backup now..."
    /scripts/backup.sh || log "Initial backup failed (check logs)"
fi

log "Starting cron daemon..."
exec crond -f -d 0
