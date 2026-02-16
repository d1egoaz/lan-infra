#!/bin/bash
# Portainer backup to restic repository
# Combines simple Portainer API backup with restic for deduplication & retention
#
# Requires: restic, curl, jq
# Environment variables:
#   PORTAINER_API_URL, PORTAINER_USERNAME, PORTAINER_PASSWORD - Portainer auth
#   RESTIC_REPOSITORY, RESTIC_PASSWORD - Restic config
#   RESTIC_HOST - (optional) hostname for snapshot tagging
#
# Usage: ./portainer-backup-restic.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# Check restic is configured
if [[ -z "${RESTIC_REPOSITORY:-}" || -z "${RESTIC_PASSWORD:-}" ]]; then
  echo "Error: RESTIC_REPOSITORY and RESTIC_PASSWORD must be set" >&2
  exit 1
fi

# Check restic repo exists, init if not
if ! restic snapshots >/dev/null 2>&1; then
  echo "Initializing restic repository..."
  restic init
fi

echo "Creating Portainer backup..."
BACKUP_FILE="$TEMP_DIR/portainer_backup.tar.gz"
"$SCRIPT_DIR/portainer-backup.sh" "$BACKUP_FILE"

echo "Backing up to restic..."
restic backup "$BACKUP_FILE" \
  --tag portainer \
  --tag "host:${RESTIC_HOST:-$(hostname)}" \
  --stdin-filename "portainer_backup.tar.gz"

echo "Backup complete!"
echo ""
echo "Recent snapshots:"
restic snapshots --tag portainer --latest 5
