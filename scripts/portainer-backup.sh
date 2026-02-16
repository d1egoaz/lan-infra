#!/bin/bash
# Simple Portainer backup script
# Downloads backup from Portainer API to a temp file
# Usage: ./portainer-backup.sh [output-file]

set -euo pipefail

# Config from env (with defaults)
PORTAINER_API_URL="${PORTAINER_API_URL:-http://localhost:9000/api}"
PORTAINER_USERNAME="${PORTAINER_USERNAME:-}"
PORTAINER_PASSWORD="${PORTAINER_PASSWORD:-}"
BACKUP_DIR="${BACKUP_DIR:-/tmp/portainer-backups}"

# Validate credentials
if [[ -z "$PORTAINER_USERNAME" || -z "$PORTAINER_PASSWORD" ]]; then
  echo "Error: PORTAINER_USERNAME and PORTAINER_PASSWORD must be set" >&2
  exit 1
fi

# Create backup dir
mkdir -p "$BACKUP_DIR"

# Generate filename
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_FILE="${1:-$BACKUP_DIR/portainer_backup_$TIMESTAMP.tar.gz}"

echo "Authenticating with Portainer at $PORTAINER_API_URL..."

# Get auth token
AUTH_TOKEN=$(curl -sSf -X POST \
  -H "Content-Type: application/json" \
  -d "{\"Username\":\"$PORTAINER_USERNAME\",\"Password\":\"$PORTAINER_PASSWORD\"}" \
  "$PORTAINER_API_URL/auth" 2>/dev/null | jq -r '.jwt // empty')

if [[ -z "$AUTH_TOKEN" ]]; then
  echo "Error: Authentication failed" >&2
  exit 1
fi

echo "Downloading backup..."

# Download backup
curl -sSf -X POST \
  -H "Authorization: Bearer $AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{}' \
  -o "$OUTPUT_FILE" \
  "$PORTAINER_API_URL/backup"

# Logout (best effort)
curl -s -X POST "$PORTAINER_API_URL/auth/logout" -H "Authorization: Bearer $AUTH_TOKEN" >/dev/null 2>&1 || true

# Verify file exists and has content
if [[ ! -s "$OUTPUT_FILE" ]]; then
  echo "Error: Backup file is empty or missing" >&2
  rm -f "$OUTPUT_FILE"
  exit 1
fi

echo "Backup saved: $OUTPUT_FILE"
