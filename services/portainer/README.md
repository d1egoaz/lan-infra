# Portainer Backup with Restic

Simple, deduplicated backups of Portainer using the official API and Restic.

## Why This Approach?

- **Simple** – One container, one script, no complex retention logic
- **Deduplicated** – Restic handles deduplication across backups
- **Encrypted** – All backups are encrypted at rest
- **Flexible storage** – Use local filesystem, S3, B2, or any Restic backend
- **Built‑in retention** – Restic's `forget` policy keeps daily/weekly/monthly snapshots
- **No side‑effects** – Backups are streamed directly to Restic, no intermediate files

## Architecture

```
┌─────────────────┐     ┌─────────────────────────┐     ┌─────────────────┐
│   Portainer EE  │     │  Restic Backup Container│     │  Restic Repo    │
│   (portainer:9443)◄────┤  (cron + curl + restic) ├────►│  (local/S3/B2) │
│                 │     │                         │     │                 │
└─────────────────┘     └─────────────────────────┘     └─────────────────┘
```

## Quick Start

1. **Configure environment**
   ```bash
   cd services/portainer
   cp .env.example .env
   # Edit .env and set at least:
   #   PORTAINER_API_KEY (from Portainer UI → My Account → API access)
   #   RESTIC_REPOSITORY (e.g., /backups for local, or S3/B2 URL)
   #   RESTIC_PASSWORD   (choose a strong password)
   ```

2. **Create external volume (if using local repository)**
   ```bash
   docker volume create portainer_backups
   ```

3. **Deploy**
   ```bash
   docker compose up -d portainer-backup
   ```

4. **Test (run backup immediately)**
   ```bash
   FIRST_RUN=true docker compose up portainer-backup
   ```

## Authentication

You can authenticate either with an API key (recommended) or with username/password.

**API Key** (preferred):
- Generate in Portainer UI: **My Account → API access**
- Set `PORTAINER_API_KEY` in `.env`

**Username/Password**:
- Set `PORTAINER_USERNAME` and `PORTAINER_PASSWORD` in `.env`

## Restic Repository

Restic supports many backends. The container expects `RESTIC_REPOSITORY` and `RESTIC_PASSWORD` to be set.

**Local filesystem** (default):
```
RESTIC_REPOSITORY=/backups
```
Mount a volume to `/backups` (see `compose.yaml`).

**S3**:
```
RESTIC_REPOSITORY=s3:s3.amazonaws.com/bucket-name
```
Set additional environment variables for AWS credentials (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`).

**Backblaze B2**:
```
RESTIC_REPOSITORY=b2:bucket-name:path
```
Set `B2_ACCOUNT_ID` and `B2_ACCOUNT_KEY`.

See [Restic documentation](https://restic.readthedocs.io/en/stable/030_preparing_a_new_repo.html) for other backends.

## Retention

By default, the backup keeps:
- **7** daily snapshots
- **4** weekly snapshots  
- **3** monthly snapshots

Adjust with `RESTIC_KEEP_DAILY`, `RESTIC_KEEP_WEEKLY`, `RESTIC_KEEP_MONTHLY`.

Retention is applied after each successful backup.

## Manual Backup

Run the backup script manually inside the container:
```bash
docker exec portainer-backup backup-restic.sh
```

## Restore

1. List available snapshots:
   ```bash
   docker exec portainer-backup restic snapshots --tag portainer
   ```

2. Restore a snapshot to a local directory:
   ```bash
   docker exec portainer-backup restic restore latest --target /tmp/restore --tag portainer
   ```

3. Use the restored `.tar.gz` file in Portainer UI: **Settings → Backup & Restore → Restore from file**.

## Monitoring

The container logs to stdout (view with `docker logs portainer-backup`). Each backup run logs start/end times and any errors.

## Troubleshooting

**Permission denied on /backups**  
Ensure the external volume exists (`docker volume create portainer_backups`).

**Restic repository not initialized**  
The container will auto‑initialize the repository on first run if it doesn't exist.

**Authentication failures**  
Check that your API key or username/password are correct and that the container can reach `PORTAINER_URL`.

**Backup fails with curl error**  
Verify Portainer is running and accessible from the backup container (`docker compose exec portainer-backup curl -k $PORTAINER_URL/api/status`).