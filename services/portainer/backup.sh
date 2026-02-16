#!/bin/bash
#
# Portainer Backup Script - Improved Retention
# Creates backups via API with tiered retention: daily (7d), weekly (4w), monthly (3m)
#

set -euo pipefail

# ===== CONFIG (override via env vars) =====
BACKUP_DIR="${BACKUP_DIR:-/backups}"
PORTAINER_URL="${PORTAINER_URL:-https://portainer:9443}"
API_KEY="${PORTAINER_API_KEY:-}"
LOG_FILE="${BACKUP_DIR}/backup.log"

# Retention (days)
RETENTION_DAILY="${RETENTION_DAILY:-7}"
RETENTION_WEEKLY="${RETENTION_WEEKLY:-28}"    # 4 weeks
RETENTION_MONTHLY="${RETENTION_MONTHLY:-90}" # ~3 months

# Hooks (optional commands to run)
PRE_BACKUP_HOOK="${PRE_BACKUP_HOOK:-}"
POST_BACKUP_HOOK="${POST_BACKUP_HOOK:-}"

# ===== UTILITIES =====

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo "$msg" | tee -a "$LOG_FILE"
}

fatal() {
    log "FATAL: $*" >&2
    exit 1
}

json_out() {
    cat <<EOF
{"ts":"$(date -Iseconds)","status":"$1","type":"$2","file":"$3","size_mb":$4,"retained":{"daily":$5,"weekly":$6,"monthly":$7}}
EOF
}

# ===== VALIDATION =====

validate() {
    [[ -z "$API_KEY" ]] && fatal "PORTAINER_API_KEY not set"
    mkdir -p "$BACKUP_DIR" || fatal "Cannot create $BACKUP_DIR"
    touch "$LOG_FILE" 2>/dev/null || fatal "Cannot write to $LOG_FILE"

    # Check disk space (need at least 500MB free)
    local avail_kb
    avail_kb=$(df -k "$BACKUP_DIR" | awk 'NR==2 {print $4}')
    (( avail_kb < 512000 )) && log "WARN: Low disk space (${avail_kb}KB available)"
}

# ===== BACKUP TYPE DETERMINATION =====

# Returns: daily, weekly, or monthly based on date
get_backup_type() {
    local dow dom
    dow=$(date +%u)   # 1=Monday, 7=Sunday
    dom=$(date +%d)   # 01-31

    if [[ "$dom" == "01" ]]; then
        echo "monthly"
    elif [[ "$dow" == "7" ]]; then
        echo "weekly"
    else
        echo "daily"
    fi
}

# ===== BACKUP CREATION =====

create_backup() {
    local outfile="$1"
    local tmpfile="${outfile}.tmp.$$"

    log "Creating backup via Portainer API..."

    local http_code
    http_code=$(curl -s -k -o "$tmpfile" -w "%{http_code}" \
        --max-time 300 \
        -X POST "${PORTAINER_URL}/api/backup" \
        -H "X-API-Key: ${API_KEY}" \
        -H "Content-Type: application/json" \
        -d '{"password":""}')

    if [[ "$http_code" != "200" ]]; then
        rm -f "$tmpfile"
        fatal "API returned HTTP $http_code"
    fi

    # Verify gzip magic (1f8b)
    local magic
    magic=$(xxd -l 2 -p "$tmpfile" 2>/dev/null || echo "")
    if [[ "$magic" != "1f8b" ]]; then
        rm -f "$tmpfile"
        fatal "Downloaded file is not a valid gzip archive (magic: $magic)"
    fi

    # Atomic move
    mv "$tmpfile" "$outfile"

    local size_mb
    size_mb=$(du -m "$outfile" | cut -f1)
    log "Backup created: $(basename "$outfile") (${size_mb}MB)"
}

# ===== RETENTION CLEANUP =====

# Keep files based on mtime, not names. More robust.
cleanup_by_age() {
    local pattern="$1"
    local max_age_days="$2"
    local type_name="$3"

    local count_before count_after
    count_before=$(find "$BACKUP_DIR" -name "$pattern" -type f 2>/dev/null | wc -l)

    find "$BACKUP_DIR" -name "$pattern" -type f -mtime "+${max_age_days}" -print0 2>/dev/null | \
        while IFS= read -r -d '' file; do
            log "Pruning old $type_name: $(basename "$file")"
            rm -f "$file"
        done

    count_after=$(find "$BACKUP_DIR" -name "$pattern" -type f 2>/dev/null | wc -l)
    local pruned=$((count_before - count_after))
    (( pruned > 0 )) && log "Pruned $pruned $type_name backup(s)"
}

# ===== MAIN =====

main() {
    log "=== Portainer Backup Started ==="

    validate

    # Pre-backup hook
    if [[ -n "$PRE_BACKUP_HOOK" ]]; then
        log "Running pre-backup hook..."
        eval "$PRE_BACKUP_HOOK" || log "Pre-backup hook failed (continuing)"
    fi

    local btype
    btype=$(get_backup_type)

    local timestamp
    timestamp=$(date +"%Y%m%d_%H%M%S")

    local filename="portainer_${btype}_${timestamp}.tar.gz"
    local filepath="${BACKUP_DIR}/${filename}"

    create_backup "$filepath"

    # Cleanup by age (mtime-based, more reliable than name parsing)
    cleanup_by_age "portainer_daily_*.tar.gz" "$RETENTION_DAILY" "daily"
    cleanup_by_age "portainer_weekly_*.tar.gz" "$RETENTION_WEEKLY" "weekly"
    cleanup_by_age "portainer_monthly_*.tar.gz" "$RETENTION_MONTHLY" "monthly"

    # Count retained backups
    local d_cnt w_cnt m_cnt size_mb
    d_cnt=$(find "$BACKUP_DIR" -name "portainer_daily_*.tar.gz" -type f 2>/dev/null | wc -l)
    w_cnt=$(find "$BACKUP_DIR" -name "portainer_weekly_*.tar.gz" -type f 2>/dev/null | wc -l)
    m_cnt=$(find "$BACKUP_DIR" -name "portainer_monthly_*.tar.gz" -type f 2>/dev/null | wc -l)
    size_mb=$(du -sm "$BACKUP_DIR" | cut -f1)

    log "Backup complete. Type: $btype | Retained: ${d_cnt}d/${w_cnt}w/${m_cnt}m | Total: ${size_mb}MB"

    # Post-backup hook
    if [[ -n "$POST_BACKUP_HOOK" ]]; then
        log "Running post-backup hook..."
        eval "$POST_BACKUP_HOOK" || log "Post-backup hook failed"
    fi

    # JSON output for monitoring
    json_out "ok" "$btype" "$filename" "$(du -m "$filepath" | cut -f1)" "$d_cnt" "$w_cnt" "$m_cnt"
}

main "$@"
