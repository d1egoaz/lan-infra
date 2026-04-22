# lan-infra

GitOps-driven homelab infrastructure. Docker Compose stacks deployed via [Portainer](https://portainer.io/) with automated dependency updates through [Renovate](https://github.com/renovatebot/renovate).

## Architecture

Each service lives in its own directory under `services/` with a `compose.yaml`. Portainer watches this repo and auto-deploys on merge to `main`.

```
services/
├── adguard/              # DNS filtering (AdGuard Home)
├── cloudflared/          # Cloudflare tunnel ingress
├── govee2mqtt/           # Govee lights → MQTT bridge
├── hello/                # Health check / connectivity test (nginx hello)
├── home-assistant/       # Home automation (HA + Music Assistant + Avahi)
├── immich/               # Self-hosted photo/video backup (server + ML + Valkey)
├── litellm/              # LLM proxy gateway
├── matter/               # Matter protocol server (HA integration)
├── mosquitto/            # MQTT broker
├── music-assistant-alexa-api/  # Music Assistant → Alexa bridge
├── nextcloud/            # File sync / collaboration
├── nginxproxymanager/    # Reverse proxy (NPM)
├── openclaw/             # AI assistant (OpenClaw + Signal CLI)
├── paperless-ai/         # OCR document tagging (companion to Paperless-ngx)
├── paperless-ngx/        # Document management (Paperless + Postgres + Redis + Gotenberg + Tika)
├── plex/                 # Media server
├── portainer/            # Container orchestration UI
├── postgres/             # Shared Postgres + pgAdmin
├── redis/                # Shared Valkey (Redis-compatible)
├── signal-cli-rest-api/  # Signal messaging REST API
├── signal-cli-rpc/       # Signal CLI daemon
├── tailscale-subnet-router/  # Tailscale subnet router for LAN access
└── uhf-server/           # UHF RFID tag reader server
```

## Workflow

### Making Changes

1. **Branch off `main`**
2. Edit the service's `compose.yaml`
3. Open a PR — **no direct pushes to `main`**
4. Merge triggers Portainer's GitOps sync (15-minute interval)

### Commit Convention

```
type(scope): description
```

Examples:
- `feat(home-assistant): add Zigbee coordinator USB mapping`
- `fix(nginxproxymanager): bump proxy timeouts for slow backends`
- `chore(renovate): update config`

### Image Pinning

All Docker images are pinned with **version tags + SHA256 digests**:
```yaml
image: nginx:1.29.7@sha256:eb37f58646a901dc7727cf448cae36daaefaba79de33b5058dab79aa4c04aefb
```

No `latest` tags. Digests make every update auditable.

## Dependency Updates

Renovate runs weekly (Mondays before 6am PT) and opens PRs for image updates.

### Key Policies

| Rule | Setting |
|------|---------|
| Minimum release age | **14 days** — new tags must bake for 2 weeks before a PR is created |
| Major DB upgrades | Disabled (postgres, redis, valkey) |
| Portainer | Pinned to 2.39.x LTS line |
| PR concurrency | Max 5 open, max 2/hour |
| Labels | `dependencies`, `docker` |

The 14-day minimum release age reduces risk from freshly-pushed images that may contain bugs or breaking changes.

## Deployment

- **Platform:** Portainer (Docker Compose)
- **GitOps sync:** Every 15 minutes
- **Host:** Intel NUC, Proxmox LXC

## Repo Structure

```
.
├── .github/workflows/       # GitHub Actions (Portainer deploy helpers)
├── services/                # One directory per Docker Compose stack
│   └── <service>/compose.yaml
├── renovate.json            # Renovate bot configuration
└── README.md
```
