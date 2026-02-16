#!/bin/bash
#
# Portainer Restore Script
# Usage: ./restore.sh <backup-file.tar.gz>
#

set -euo pipefail

BACKUP_FILE="${1:-}"
PORTAINER_DATA="${PORTAINER_DATA:-/var/lib/docker/volumes/portainer_data/_data}"

if [[ -z "$BACKUP_FILE" ]]; then
    echo "Usage: $0 <backup-file.tar.gz>"
    echo ""
    echo "Available backups:"
    ls -1t /srv/data/backups/portainer/portainer_*.tar.gz 2>/dev/null | head -10 || echo "  (none found)"
    exit 1
fi

if [[ ! -f "$BACKUP_FILE" ]]; then
    echo "ERROR: Backup file not found: $BACKUP_FILE"
    exit 1
fi

echo "========================================="
echo "Portainer Restore"
echo "========================================="
echo "Backup: $BACKUP_FILE"
echo "Target: $PORTAINER_DATA"
echo ""
echo "WARNING: This will OVERWRITE current Portainer data!"
echo "Make sure Portainer is stopped: docker stop portainer"
echo ""
read -p "Continue? (yes/no): " confirm

if [[ "$confirm" != "yes" ]]; then
    echo "Aborted."
    exit 0
fi

echo ""
echo "Restoring..."

# Stop portainer if running
if docker ps -q --filter "name=portainer" | grep -q .; then
    echo "Stopping Portainer container..."
    docker stop portainer
fi

# Clear existing data
echo "Clearing existing data..."
rm -rf "${PORTAINER_DATA:?}"/*

# Extract backup
echo "Extracting backup..."
tar -xzf "$BACKUP_FILE" -C "$PORTAINER_DATA"

# Fix permissions
chown -R 0:0 "$PORTAINER_DATA"

echo ""
echo "Restore complete. Start Portainer with: docker start portainer"
echo "Or: docker compose up -d (from lan-infra/services/portainer/)"