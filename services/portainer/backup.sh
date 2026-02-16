#!/bin/sh
#
# Portainer Backup Script with Daily/Weekly/Monthly Rotation
# Uses Portainer API to create consistent backups (locks DB during backup)
#
# Environment variables:
#   PORTAINER_URL      - Portainer URL (default: https://portainer.lan.diegoa.ca)
#   PORTAINER_API_KEY  - API key for authentication (required)
#   BACKUP_DIR         - Backup directory (default: /backups)
#
# Retention:
#   - Daily: 7 days
#   - Weekly: 4 weeks (promoted from Sunday's daily)
#   - Monthly: 3 months (promoted from 1st of month)
#

set -eu

# ===== CONFIG =====
BACKUP_DIR="${BACKUP_DIR:-/backups}"
PORTAINER_URL="${PORTAINER_URL:-https://portainer.lan.diegoa.ca}"
API_KEY="${PORTAINER_API_KEY:-}"
LOG_FILE="${BACKUP_DIR}/backup.log"

# Retention settings
KEEP_DAILY=7
KEEP_WEEKLY=4
KEEP_MONTHLY=3

# ===== FUNCTIONS =====

log() {
    ts=$(date +"%Y-%m-%d %H:%M:%S")
    echo "[$ts] $1" | tee -a "$LOG_FILE"
}

error() {
    log "ERROR: $1"
    exit 1
}

# ===== PRE-CHECKS =====

if [ -z "$API_KEY" ]; then
    error "PORTAINER_API_KEY not set"
fi

mkdir -p "$BACKUP_DIR"

# ===== BACKUP =====

DATE=$(date +"%Y-%m-%d")
DAY_OF_WEEK=$(date +"%u")  # 1=Mon, 7=Sun
DAY_OF_MONTH=$(date +"%d")
WEEK_NUMBER=$(date +"%V")  # ISO week number
MONTH=$(date +"%Y-%m")

DAILY_FILE="${BACKUP_DIR}/portainer_daily_${DATE}.tar.gz"
WEEKLY_FILE="${BACKUP_DIR}/portainer_weekly_${DATE}-W${WEEK_NUMBER}.tar.gz"
MONTHLY_FILE="${BACKUP_DIR}/portainer_monthly_${MONTH}.tar.gz"

log "Starting Portainer backup..."

# Create backup via API (Portainer locks DB during backup)
if ! curl -s -k -X POST "${PORTAINER_URL}/api/backup" \
    -H "X-API-Key: $API_KEY" \
    -H "Content-Type: application/json" \
    -d '{"password": ""}' \
    --output "$DAILY_FILE"; then
    error "Backup API call failed"
fi

# Verify backup was created
if [ ! -f "$DAILY_FILE" ] || [ ! -s "$DAILY_FILE" ]; then
    error "Backup file is empty or missing: $DAILY_FILE"
fi

BACKUP_SIZE=$(stat -c%s "$DAILY_FILE" 2>/dev/null || stat -f%z "$DAILY_FILE" 2>/dev/null)
log "Daily backup created: $DAILY_FILE ($(( BACKUP_SIZE / 1024 ))KB)"

# ===== PROMOTION (Weekly/Monthly) =====

# Promote to weekly on Sundays
if [ "$DAY_OF_WEEK" = "7" ]; then
    cp "$DAILY_FILE" "$WEEKLY_FILE"
    log "Promoted to weekly: $WEEKLY_FILE"
fi

# Promote to monthly on 1st of month
if [ "$DAY_OF_MONTH" = "01" ]; then
    cp "$DAILY_FILE" "$MONTHLY_FILE"
    log "Promoted to monthly: $MONTHLY_FILE"
fi

# ===== CLEANUP =====

# Cleanup old daily backups (keep KEEP_DAILY)
find "$BACKUP_DIR" -name "portainer_daily_*.tar.gz" -type f -mtime +"$KEEP_DAILY" -exec rm -v {} \; 2>&1 | while read -r line; do
    log "Deleted old daily: $line"
done

# Cleanup old weekly backups (keep KEEP_WEEKLY weeks = KEEP_WEEKLY * 7 days)
find "$BACKUP_DIR" -name "portainer_weekly_*.tar.gz" -type f -mtime +"$(( KEEP_WEEKLY * 7 ))" -exec rm -v {} \; 2>&1 | while read -r line; do
    log "Deleted old weekly: $line"
done

# Cleanup old monthly backups (keep KEEP_MONTHLY months ≈ 90 days)
find "$BACKUP_DIR" -name "portainer_monthly_*.tar.gz" -type f -mtime +"$(( KEEP_MONTHLY * 30 ))" -exec rm -v {} \; 2>&1 | while read -r line; do
    log "Deleted old monthly: $line"
done

# ===== SUMMARY =====

DAILY_COUNT=$(find "$BACKUP_DIR" -name "portainer_daily_*.tar.gz" -type f | wc -l | tr -d ' ')
WEEKLY_COUNT=$(find "$BACKUP_DIR" -name "portainer_weekly_*.tar.gz" -type f | wc -l | tr -d ' ')
MONTHLY_COUNT=$(find "$BACKUP_DIR" -name "portainer_monthly_*.tar.gz" -type f | wc -l | tr -d ' ')

log "Backup complete. Totals: $DAILY_COUNT daily, $WEEKLY_COUNT weekly, $MONTHLY_COUNT monthly"

# ===== JSON OUTPUT (for monitoring) =====

cat <<EOF
{
  "status": "success",
  "date": "$DATE",
  "daily_file": "$DAILY_FILE",
  "daily_size_kb": $(( BACKUP_SIZE / 1024 )),
  "counts": {
    "daily": $DAILY_COUNT,
    "weekly": $WEEKLY_COUNT,
    "monthly": $MONTHLY_COUNT
  }
}
EOF
