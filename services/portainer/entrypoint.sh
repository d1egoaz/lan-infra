#!/bin/sh
#
# Entrypoint for Portainer backup container
# Runs backup at specified hour (default: 03:00) daily
#

set -eu

BACKUP_HOUR="${BACKUP_HOUR:-3}"
BACKUP_MINUTE="${BACKUP_MINUTE:-0}"

# Run immediately if FIRST_RUN=true (for testing)
if [ "${FIRST_RUN:-false}" = "true" ]; then
    echo "[$(date)] Running first backup..."
    /backup.sh
fi

echo "[$(date)] Portainer backup scheduler started"
echo "[$(date)] Schedule: daily at ${BACKUP_HOUR}:${BACKUP_MINUTE}"

while true; do
    # Calculate seconds until next backup
    NOW=$(date +%s)
    TODAY=$(date +%Y-%m-%d)
    NEXT="${TODAY} ${BACKUP_HOUR}:$(printf '%02d' $BACKUP_MINUTE):00"
    NEXT_TS=$(date -j -f "%Y-%m-%d %H:%M:%S" "$NEXT" +%s 2>/dev/null || date -d "$NEXT" +%s 2>/dev/null)
    
    # If next backup time has passed today, schedule for tomorrow
    if [ "$NEXT_TS" -le "$NOW" ]; then
        TOMORROW=$(date -j -v+1d +%Y-%m-%d 2>/dev/null || date -d "tomorrow" +%Y-%m-%d)
        NEXT="${TOMORROW} ${BACKUP_HOUR}:$(printf '%02d' $BACKUP_MINUTE):00"
        NEXT_TS=$(date -j -f "%Y-%m-%d %H:%M:%S" "$NEXT" +%s 2>/dev/null || date -d "$NEXT" +%s)
    fi
    
    SLEEP_SECONDS=$(( NEXT_TS - NOW ))
    HOURS=$(( SLEEP_SECONDS / 3600 ))
    MINS=$(( (SLEEP_SECONDS % 3600) / 60 ))
    
    echo "[$(date)] Next backup in ${HOURS}h ${MINS}m (at $NEXT)"
    
    sleep "$SLEEP_SECONDS"
    
    echo "[$(date)] Running scheduled backup..."
    /backup.sh
done
