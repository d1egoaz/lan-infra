#!/bin/bash
# Clean old Portainer backups using restic's retention policy
#
# Environment variables:
#   RESTIC_REPOSITORY, RESTIC_PASSWORD - Restic config
#   KEEP_DAILY, KEEP_WEEKLY, KEEP_MONTHLY - Retention (defaults: 7, 4, 3)
#
# Usage: ./portainer-backup-forget.sh

set -euo pipefail

if [[ -z "${RESTIC_REPOSITORY:-}" || -z "${RESTIC_PASSWORD:-}" ]]; then
  echo "Error: RESTIC_REPOSITORY and RESTIC_PASSWORD must be set" >&2
  exit 1
fi

echo "Applying retention policy..."
echo "  Keep daily: ${KEEP_DAILY:-7}"
echo "  Keep weekly: ${KEEP_WEEKLY:-4}"
echo "  Keep monthly: ${KEEP_MONTHLY:-3}"

restic forget \
  --tag portainer \
  --keep-daily "${KEEP_DAILY:-7}" \
  --keep-weekly "${KEEP_WEEKLY:-4}" \
  --keep-monthly "${KEEP_MONTHLY:-3}" \
  --prune

echo "Cleanup complete!"
