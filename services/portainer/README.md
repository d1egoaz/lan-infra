# Portainer Backup

Simple sidecar container that backs up Portainer to a restic repository on a schedule.

## How It Works

- Sidecar container runs alongside Portainer
- Uses `dcron` to run backups on a schedule (default: daily at 3am)
- Downloads backup via Portainer API (user/password auth)
- Stores in restic repository with deduplication and encryption
- Automatically applies retention policy after each backup

## Setup

1. Copy `.env.example` to `.env` and configure:

```bash
cp .env.example .env
# Edit .env with your credentials
```

2. Ensure backup volume exists:

```bash
docker volume create portainer_backups
```

3. Deploy:

```bash
docker compose up -d
```

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `PORTAINER_API_URL` | `http://portainer:9000/api` | Portainer API endpoint |
| `PORTAINER_USERNAME` | - | Portainer admin username |
| `PORTAINER_PASSWORD` | - | Portainer admin password |
| `RESTIC_REPOSITORY` | `/backups` | Restic repo path (in container) |
| `RESTIC_PASSWORD` | - | Restic encryption password |
| `BACKUP_SCHEDULE` | `0 3 * * *` | Cron schedule for backups |
| `KEEP_DAILY` | `7` | Daily snapshots to keep |
| `KEEP_WEEKLY` | `4` | Weekly snapshots to keep |
| `KEEP_MONTHLY` | `3` | Monthly snapshots to keep |

## Viewing Backups

```bash
# List snapshots
docker exec portainer-backup restic snapshots

# Restore latest backup
docker exec portainer-backup restic restore latest --target /tmp/restore

# Check repository
docker exec portainer-backup restic check
```

## Logs

```bash
# View backup logs
docker logs portainer-backup

# View cron logs
docker exec portainer-backup cat /var/log/cron.log
```

## Files

- `backup.Dockerfile` - Alpine-based image with restic, curl, jq, cron
- `backup.sh` - Performs the backup (auth → download → restic → retention)
- `entrypoint.sh` - Sets up cron and runs initial backup
- `compose.yaml` - Service definition
