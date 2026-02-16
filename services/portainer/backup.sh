#!/bin/bash
#
# Portainer Backup Script
# Creates backups via API with tiered retention: daily (7d), weekly (4w), monthly (3m)
#

set -euo pipefail

# ===== CONFIGURATION =====
# Override these via environment variables
BACKUP_DIR="${BACKUP_DIR:-/backups}"
PORTAINER_URL="${PORTAINER_URL:-https://portainer:9443}"
API_KEY="${PORTAINER_API_KEY:-}"
LOG_FILE="${BACKUP_DIR}/backup.log"

# SSL Verification (default: false, assumes self-signed certs in homelab)
SSL_VERIFY="${SSL_VERIFY:-false}"
CURL_SSL_OPTS=""
[[ "$SSL_VERIFY" != "true" ]] && CURL_SSL_OPTS="-k"

# Retention in days
RETENTION_DAILY="${RETENTION_DAILY:-7}"
RETENTION_WEEKLY="${RETENTION_WEEKLY:-28}"    # 4 weeks
RETENTION_MONTHLY="${RETENTION_MONTHLY:-90}" # ~3 months

# Optional Hooks
PRE_BACKUP_HOOK="${PRE_BACKUP_HOOK:-}"
POST_BACKUP_HOOK="${POST_BACKUP_HOOK:-}"

# ===== UTILITIES =====

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

fatal() {
    log "FATAL: $*"
    exit 1
}

# ===== VALIDATION =====

validate_env() {
    if [[ -z "$API_KEY" ]]; then
        fatal "PORTAINER_API_KEY is not set."
    fi

    # Ensure backup directory exists and is writable
    if ! mkdir -p "$BACKUP_DIR"; then
        fatal "Cannot create backup directory: $BACKUP_DIR"
    fi
    if ! touch "$LOG_FILE"; then
        fatal "Cannot write to log file: $LOG_FILE"
    fi

    # Check disk space (require at least 500MB free)
    local avail_kb
    avail_kb=$(df -k "$BACKUP_DIR" | awk 'NR==2 {print $4}')
    if (( avail_kb < 512000 )); then
        fatal "Low disk space: ${avail_kb}KB available in $BACKUP_DIR (min 512MB required)"
    fi
}

# ===== LOCKING =====

acquire_lock() {
    local lock_file="${BACKUP_DIR}/.backup.lock"

    # Check if lock exists and is stale (> 3 hours)
    if [[ -f "$lock_file" ]]; then
        local lock_age
        lock_age=$(($(date +%s) - $(stat -c %Y "$lock_file")))
        if (( lock_age > 10800 )); then
            log "Removing stale lock file (age: ${lock_age}s)"
            rm -f "$lock_file"
        else
            log "Backup is already running (lock file exists). Exiting."
            exit 0
        fi
    fi

    # Create lock
    touch "$lock_file"

    # Ensure lock is removed on exit
    trap 'rm -f "$lock_file"' EXIT
}

# ===== BACKUP LOGIC =====

get_backup_type() {
    local dow dom
    dow=$(date +%u)   # 1=Monday ... 7=Sunday
    dom=$(date +%d)   # Day of month

    # Priority: Monthly > Weekly > Daily
    if [[ "$dom" == "01" ]]; then
        echo "monthly"
    elif [[ "$dow" == "7" ]]; then
        echo "weekly"
    else
        echo "daily"
    fi
}

create_backup() {
    local outfile="$1"
    local tmpfile="${outfile}.tmp"

    log "Requesting backup from Portainer API..."

    local http_code curl_output
    # We capture stderr to a variable in case curl throws network errors,
    # but we write the response body to the tmpfile.
    http_code=$(curl -s ${CURL_SSL_OPTS} -w "%{http_code}" -o "$tmpfile" \
        --max-time 300 --connect-timeout 30 \
        -X POST "${PORTAINER_URL}/api/backup" \
        -H "X-API-Key: ${API_KEY}" \
        -H "Content-Type: application/json" \
        -d '{"password":""}' 2>&1)

    # Check for curl execution errors (e.g. DNS failure)
    if [[ ! "$http_code" =~ ^[0-9]+$ ]]; then
        rm -f "$tmpfile"
        fatal "curl connection failed: $http_code"
    fi

    if [[ "$http_code" -ne 200 ]]; then
        local error_msg
        error_msg=$(cat "$tmpfile")
        rm -f "$tmpfile"
        fatal "API returned HTTP $http_code: $error_msg"
    fi

    # Validate gzip integrity
    if ! gunzip -t "$tmpfile" 2>/dev/null; then
        rm -f "$tmpfile"
        fatal "Downloaded file is corrupted (invalid gzip)"
    fi

    # Atomic move
    mv "$tmpfile" "$outfile"

    local size_mb
    size_mb=$(($(du -k "$outfile" | cut -f1) / 1024))
    log "Backup successful: $(basename "$outfile") (${size_mb}MB)"
}

# ===== RETENTION =====

cleanup_old_backups() {
    local pattern="$1"
    local max_age="$2"
    local type_name="$3"

    local deleted_count=0
    while IFS= read -r -d '' file; do
        log "Pruning old ${type_name}: $(basename "$file")"
        rm -f "$file"
        ((deleted_count++))
    done < <(find "$BACKUP_DIR" -name "$pattern" -type f -mtime "+$max_age" -print0 2>/dev/null)

    if (( deleted_count > 0 )); then
        log "Pruned ${deleted_count} ${type_name} backup(s)"
    fi
}

# ===== MAIN =====

main() {
    validate_env
    acquire_lock

    log "=== Portainer Backup Started ==="

    # Pre-backup hook
    if [[ -n "$PRE_BACKUP_HOOK" ]]; then
        log "Running pre-backup hook..."
        if ! sh -c "$PRE_BACKUP_HOOK"; then
            log "WARNING: Pre-backup hook failed (continuing anyway)"
        fi
    fi

    # Determine type and filename
    local btype timestamp filename filepath
    btype=$(get_backup_type)
    timestamp=$(date +"%Y%m%d_%H%M%S")
    filename="portainer_${btype}_${timestamp}.tar.gz"
    filepath="${BACKUP_DIR}/${filename}"

    # Execute Backup
    create_backup "$filepath"

    # Execute Retention
    cleanup_old_backups "portainer_daily_*.tar.gz" "$RETENTION_DAILY" "daily"
    cleanup_old_backups "portainer_weekly_*.tar.gz" "$RETENTION_WEEKLY" "weekly"
    cleanup_old_backups "portainer_monthly_*.tar.gz" "$RETENTION_MONTHLY" "monthly"

    # Stats
    local d_cnt w_cnt m_cnt total_size_mb
    d_cnt=$(find "$BACKUP_DIR" -name "portainer_daily_*.tar.gz" -type f 2>/dev/null | wc -l)
    w_cnt=$(find "$BACKUP_DIR" -name "portainer_weekly_*.tar.gz" -type f 2>/dev/null | wc -l)
    m_cnt=$(find "$BACKUP_DIR" -name "portainer_monthly_*.tar.gz" -type f 2>/dev/null | wc -l)
    total_size_mb=$(($(du -sk "$BACKUP_DIR" | cut -f1) / 1024))

    log "Backup Complete. Type: ${btype} | Retained: ${d_cnt}d/${w_cnt}w/${m_cnt}m | Total Size: ${total_size_mb}MB"

    # Post-backup hook
    if [[ -n "$POST_BACKUP_HOOK" ]]; then
        log "Running post-backup hook..."
        if ! sh -c "$POST_BACKUP_HOOK"; then
            log "WARNING: Post-backup hook failed"
        fi
    fi

    # Output JSON for monitoring (e.g. Prometheus node_exporter textfile collector)
    # Using simple printf to avoid dependency on jq
    printf '{"status":"ok","type":"%s","file":"%s","size_mb":%d,"retained":{"daily":%d,"weekly":%d,"monthly":%d}}\n' \
        "$btype" "$filename" "$(($(du -k "$filepath" | cut -f1) / 1024))" "$d_cnt" "$w_cnt" "$m_cnt"
}

main "$@"
