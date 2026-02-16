# Portainer Backup (Restic)

Simple Portainer backup using the API and restic for storage.

Much lighter than the full containerized backup solution — just 3 shell scripts.

## Scripts

| Script | Purpose |
|--------|---------|
| `portainer-backup.sh` | Downloads backup from Portainer API to a file |
| `portainer-backup-restic.sh` | Downloads backup and stores it in restic |
| `portainer-backup-forget.sh` | Applies restic retention policy and prunes old backups |

## Setup

### 1. Install restic

```bash
# macOS
brew install restic

# Debian/Ubuntu
apt install restic

# Or download from https://github.com/restic/restic/releases
```

### 2. Configure restic repository

```bash
export RESTIC_REPOSITORY="/srv/backups/portainer"
export RESTIC_PASSWORD="your-secure-password"

# Or use S3/B2/etc:
# export RESTIC_REPOSITORY="s3:s3.amazonaws.com/bucket-name"
# export AWS_ACCESS_KEY_ID=xxx
# export AWS_SECRET_ACCESS_KEY=xxx
```

### 3. Configure Portainer access

```bash
export PORTAINER_API_URL="https://portainer.example.com/api"
export PORTAINER_USERNAME="admin"
export PORTAINER_PASSWORD="your-password"
```

### 4. Run backup

```bash
./scripts/portainer-backup-restic.sh
```

### 5. Schedule with cron/systemd

**Cron example:**

```bash
# /etc/cron.d/portainer-backup
# Daily at 3am
0 3 * * * root cd /opt/lan-infra && RESTIC_REPOSITORY=/srv/backups/portainer RESTIC_PASSWORD=xxx PORTAINER_API_URL=xxx PORTAINER_USERNAME=xxx PORTAINER_PASSWORD=xxx ./scripts/portainer-backup-restic.sh >> /var/log/portainer-backup.log 2>&1

# Weekly cleanup (Sundays at 4am)
0 4 * * 0 root cd /opt/lan-infra && RESTIC_REPOSITORY=/srv/backups/portainer RESTIC_PASSWORD=xxx KEEP_DAILY=7 KEEP_WEEKLY=4 KEEP_MONTHLY=3 ./scripts/portainer-backup-forget.sh >> /var/log/portainer-backup.log 2>&1
```

## Retention

Default policy (adjust via env vars):
- Keep last 7 daily snapshots
- Keep last 4 weekly snapshots  
- Keep last 3 monthly snapshots

## Restore

```bash
# List snapshots
restic snapshots --tag portainer

# Restore latest to current directory
restic restore latest --tag portainer --target .

# Restore specific snapshot
restic restore abc12345 --target .
```

## Comparison to PR #75

| | PR #75 (Overengineered) | This Approach |
|--|------------------------|---------------|
| **Code** | Dockerfile, entrypoint, backup script, compose | 3 shell scripts |
| **Containers** | Sidecar container with cron | None (run on host or existing container) |
| **Retention** | Custom mtime-based shell logic | Restic's built-in `forget` |
| **Deduplication** | None | Restic handles it |
| **Encryption** | None | Restic encrypts |
| **Logging** | JSON structured logs | Simple stdout |
| **Features** | Hooks, healthchecks, locking, disk checks | Just backup + restic |

This approach leverages restic instead of reinventing backup management.
