# Portainer Backup

Simple sidecar container that backs up Portainer to a local restic repository on a schedule.

Backups are stored on the host at `/srv/data/backups/portainer` (RAID1).

## Setup

1. Create an API key in Portainer:
   - My Account → API Keys → Add API Key

2. Copy `.env.example` to `.env` and add your API key:

```bash
cp .env.example .env
# Edit .env
```

3. Ensure backup directory exists on host:

```bash
mkdir -p /srv/data/backups/portainer
```

4. Deploy:

```bash
docker compose up -d
```

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `PORTAINER_API_KEY` | - | **Required.** Portainer API key |
| `RESTIC_REPOSITORY` | `/backups` | Restic repository path (container path) |
| `BACKUP_SCHEDULE` | `0 3 * * *` | Cron schedule for backups |
| `KEEP_DAILY` | `7` | Daily snapshots to keep |
| `KEEP_WEEKLY` | `4` | Weekly snapshots to keep |
| `KEEP_MONTHLY` | `3` | Monthly snapshots to keep |

## Viewing Backups

```bash
# List snapshots
docker exec portainer-backup restic snapshots --insecure-no-password

# Restore latest backup
docker exec portainer-backup restic restore latest --target /tmp/restore --insecure-no-password

# Check repository
docker exec portainer-backup restic check --insecure-no-password
```

## Logs

```bash
# View backup logs (cron output goes to container stdout)
docker logs portainer-backup

# View backup history from restic
docker exec portainer-backup restic snapshots --insecure-no-password
```

## Notes

- No password is used for the restic repository (local RAID1 storage)
- All `restic` commands require `--insecure-no-password` flag
