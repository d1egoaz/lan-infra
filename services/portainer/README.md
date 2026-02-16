# Portainer Backup Service

Automated, tiered backups of Portainer via API. Runs in a lightweight Alpine container with cron.

## Architecture

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────────┐
│   Portainer EE  │     │  Backup Container│     │  NAS (RAID 1)       │
│   (portainer:9443)◄────┤  (dcron + curl)  ├────►│  /srv/data/backups/ │
│                 │     │                  │     │  portainer/         │
└─────────────────┘     └──────────────────┘     └─────────────────────┘
```

## Why This Approach?

- **API-based backups** — Uses Portainer's native `/api/backup` endpoint (locks DB during backup)
- **Standard cron** (`dcron`) — Not a custom sleep-loop
- **Non-root** — Runs as `backup` user inside container
- **Atomic writes** — `.tmp` → rename on success
- **Magic byte validation** — Verifies gzip integrity
- **mtime-based cleanup** — Retention by actual file age, not name parsing
- **JSON output** — Parseable for monitoring/alerting
- **Pre/post hooks** — Easy integration with ntfy/Apprise/etc

## Backup Strategy

| Type | Trigger | Retention | Max On Disk |
|------|---------|-----------|-------------|
| **Daily** | Every day @ 3 AM | 7 days | 7 |
| **Weekly** | Every Sunday | 28 days | 4 |
| **Monthly** | 1st of month | 90 days (~3 months) | 3 |

**Total: ~14 backups max** (~500MB-2GB depending on your Portainer data)

### Naming Convention
```
portainer_daily_20250215_030012.tar.gz
portainer_weekly_20250209_030015.tar.gz
portainer_monthly_20250201_030008.tar.gz
```

## Quick Start

```bash
cd lan-infra/services/portainer

# 1. Configure
cp .env.example .env
# Edit .env: add your PORTAINER_API_KEY

# 2. Deploy
docker compose up -d

# 3. Test (runs immediately)
FIRST_RUN=true docker compose up backup
```

### Permissions

Ensure the host directory `/srv/data/backups/portainer` is writable by the container's `backup` user (UID 1000). If permissions are incorrect, adjust with:

```bash
sudo chown -R 1000:1000 /srv/data/backups/portainer
```



## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PORTAINER_API_KEY` | *required* | From Portainer UI → My Account → API access |
| `PORTAINER_URL` | `https://portainer:9443` | Internal Docker network URL |
| `SSL_VERIFY` | `false` | Enable SSL certificate verification (set to `true` to verify) |
| `BACKUP_SCHEDULE` | `0 3 * * *` | Cron expression (3 AM daily) |
| `TZ` | `America/Vancouver` | Timezone |
| `FIRST_RUN` | `false` | Run once immediately on start |
| `RETENTION_DAILY` | `7` | Days to keep daily backups |
| `RETENTION_WEEKLY` | `28` | Days to keep weekly backups |
| `RETENTION_MONTHLY` | `90` | Days to keep monthly backups |
| `PRE_BACKUP_HOOK` | `` | Command to run before backup |
| `POST_BACKUP_HOOK` | `` | Command to run after backup |

## Manual Backup

```bash
docker exec portainer-backup /scripts/backup.sh
```

## Restore

```bash
# List available backups
ls -lt /srv/data/backups/portainer/

# Restore via Portainer UI:
# Settings → Backup & Restore → Restore from file
# Or use the restore.sh helper:
./restore.sh /srv/data/backups/portainer/portainer_daily_20250215_030012.tar.gz
```

## Monitoring

### JSON Output (parseable)
```json
{"ts":"2025-02-15T03:00:12-08:00","status":"ok","type":"daily","file":"portainer_daily_20250215_030012.tar.gz","size_mb":42,"retained":{"daily":7,"weekly":4,"monthly":2}}
```

### Logs
```bash
# Container logs
docker logs portainer-backup --tail 50

# Backup operation log
tail -f /srv/data/backups/portainer/backup.log
```

### Health Check
The container includes a healthcheck that verifies `crond` is running:
```bash
docker inspect --format='{{.State.Health.Status}}' portainer-backup
```

## Notification Example (ntfy)

Add to `.env`:
```bash
POST_BACKUP_HOOK='curl -s -d "Portainer backup: $(date +%H:%M) completed" https://ntfy.sh/your-topic'
```

## File Locations

| Path | Description |
|------|-------------|
| `/srv/data/backups/portainer/` | NAS mount (RAID 1) |
| `/srv/data/backups/portainer/backup.log` | Rotation log |
| `/srv/data/backups/portainer/portainer_*.tar.gz` | Backup archives |

## Troubleshooting

| Issue | Fix |
|-------|-----|
| `Cannot write to /backups` | Check NAS mount: `ls -la /srv/data/backups/portainer` |
| `API returned HTTP 401` | Regenerate API key in Portainer UI |
| `Low disk space` | Reduce retention or expand NAS |
| `gzip: invalid magic` | Delete corrupted backup, re-run |
