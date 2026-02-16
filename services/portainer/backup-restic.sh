#!/bin/bash
# Portainer backup with restic
# Simple script to backup Portainer via API and store with restic
# Supports API key or username/password authentication

set -euo pipefail

# Default configuration
PORTAINER_URL="${PORTAINER_URL:-https://portainer:9443}"
BACKUP_SCHEDULE="${BACKUP_SCHEDULE:-0 3 * * *}"
TZ="${TZ:-America/Vancouver}"

# Retention policy for restic
KEEP_DAILY="${RESTIC_KEEP_DAILY:-7}"
KEEP_WEEKLY="${RESTIC_KEEP_WEEKLY:-4}"
KEEP_MONTHLY="${RESTIC_KEEP_MONTHLY:-3}"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

fatal() {
    log "FATAL: $*"
    exit 1
}

# Validate restic configuration
if [[ -z "${RESTIC_REPOSITORY:-}" || -z "${RESTIC_PASSWORD:-}" ]]; then
    fatal "RESTIC_REPOSITORY and RESTIC_PASSWORD must be set"
fi

# Validate Portainer authentication
if [[ -z "${PORTAINER_API_KEY:-}" && ( -z "${PORTAINER_USERNAME:-}" || -z "${PORTAINER_PASSWORD:-}" ) ]]; then
    fatal "Either PORTAINER_API_KEY or PORTAINER_USERNAME/PORTAINER_PASSWORD must be set"
fi

# Initialize restic repository if needed
if ! restic snapshots >/dev/null 2>&1; then
    log "Initializing restic repository..."
    restic init
fi

# Determine authentication method
if [[ -n "$PORTAINER_API_KEY" ]]; then
    AUTH_HEADER="X-API-Key: $PORTAINER_API_KEY"
    log "Using API key authentication"
else
    # Get JWT token
    log "Authenticating with username/password..."
    TOKEN=$(curl -sSf -X POST \
        -H "Content-Type: application/json" \
        -d "{\"Username\":\"$PORTAINER_USERNAME\",\"Password\":\"$PORTAINER_PASSWORD\"}" \
        "$PORTAINER_URL/api/auth" 2>/dev/null | jq -r '.jwt // empty')
    
    if [[ -z "$TOKEN" ]]; then
        fatal "Failed to authenticate with username/password"
    fi
    AUTH_HEADER="Authorization: Bearer $TOKEN"
    log "Authentication successful"
fi

# Perform backup
log "Starting Portainer backup..."
BACKUP_SIZE=0
if [[ -n "${AUTH_HEADER:-}" ]]; then
    # Use curl to download backup and pipe to restic
    curl -sSf -X POST \
        -H "Content-Type: application/json" \
        -H "$AUTH_HEADER" \
        -d '{}' \
        "$PORTAINER_URL/api/backup" | \
    restic backup --stdin --stdin-filename "portainer_backup.tar.gz" \
        --tag portainer \
        --tag "host:${RESTIC_HOST:-$(hostname)}" \
        --tag "$(date +%Y-%m-%d)"
    
    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        fatal "Failed to download backup from Portainer"
    fi
    if [[ ${PIPESTATUS[1]} -ne 0 ]]; then
        fatal "Failed to upload backup to restic"
    fi
else
    fatal "No authentication method available"
fi

log "Backup completed successfully"

# Apply retention policy
log "Applying retention policy (keep-daily:$KEEP_DAILY, keep-weekly:$KEEP_WEEKLY, keep-monthly:$KEEP_MONTHLY)"
restic forget \
    --tag portainer \
    --keep-daily "$KEEP_DAILY" \
    --keep-weekly "$KEEP_WEEKLY" \
    --keep-monthly "$KEEP_MONTHLY" \
    --prune

log "Retention policy applied"

# Log snapshot summary
log "Recent Portainer snapshots:"
restic snapshots --tag portainer --latest 5