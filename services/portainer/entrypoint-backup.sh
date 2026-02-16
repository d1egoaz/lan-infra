#!/bin/bash
# Entrypoint for restic backup container

set -euo pipefail

BACKUP_SCHEDULE="${BACKUP_SCHEDULE:-0 3 * * *}"
TZ="${TZ:-America/Vancouver}"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log "Portainer Restic Backup Service"
log "================================"
log "Schedule: $BACKUP_SCHEDULE"
log "Timezone: $TZ"
log "Portainer URL: ${PORTAINER_URL:-https://portainer:9443}"
log "Restic Repository: ${RESTIC_REPOSITORY:-}"

# Export environment variables for cron
env | while IFS= read -r line; do
    name="${line%%=*}"
    # Skip special variables
    case "$name" in
        HOME|PWD|TERM|SHLVL|PATH|_|OLDPWD|SHELL)
            continue
            ;;
    esac
    # Escape values for crontab
    value="${line#*=}"
    echo "$name='$value'"
done > /tmp/cron.env

# Create crontab
{
    echo "SHELL=/bin/bash"
    echo "PATH=/usr/local/bin:/usr/bin:/bin"
    echo "BASH_ENV=/tmp/cron.env"
    cat /tmp/cron.env
    echo "$BACKUP_SCHEDULE backup-restic.sh 2>&1 | logger -t portainer-backup"
} | crontab -

log "Cron schedule installed"

# Optional immediate backup for testing
if [[ "${FIRST_RUN:-false}" == "true" ]]; then
    log "FIRST_RUN enabled - executing backup now..."
    backup-restic.sh || log "Initial backup failed (check logs)"
fi

log "Starting cron daemon..."
exec crond -f -d 0