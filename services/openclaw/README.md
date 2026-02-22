# OpenClaw Service

This stack keeps OpenClaw config in git with `${VAR}` placeholders and expects private values from Portainer Stack environment variables.

## Files

- `compose.yaml`: OpenClaw gateway + Signal RPC sidecar
- `config/openclaw.json`: git-tracked config with `${VAR}` placeholders
- `.env.example`: variable reference for Portainer values

## Portainer Setup

1. Deploy this folder as a Portainer stack (recommended: from Git).
2. In Stack environment variables, define required keys from `.env.example`:
   - `OPENAI_BASE_URL`
   - `OPENAI_API_KEY`
   - `OPENCLAW_PERPLEXITY_API_KEY`
   - `OPENCLAW_PERPLEXITY_MODEL`
   - `OPENCLAW_SIGNAL_HTTP_URL`
   - `OPENCLAW_GATEWAY_TOKEN`
   - `OPENCLAW_GATEWAY_PORT` (optional, default `18789`)
   - `TZ` (optional)
3. Deploy services:
   - `openclaw-gateway`
   - `signal-rpc`
   - `openclaw-cli` only when you need ad-hoc maintenance tasks

## Env Substitution Rules

- Only uppercase names matched: `[A-Z_][A-Z0-9_]*`
- Missing or empty vars throw an error at load time
- Escape with `$${VAR}` for literal output
- Works inside `$include` files
- Inline substitution supported: `"${BASE}/v1"`

## Precedence (highest to lowest)

1. Process environment (what the gateway process already has from the parent shell or daemon).
2. `.env` in the current working directory (dotenv default; does not override).
3. Global `.env` at `~/.openclaw/.env` (aka `$OPENCLAW_STATE_DIR/.env`; does not override).
4. Config `env` block in `~/.openclaw/openclaw.json` (applied only if missing).
5. Optional login-shell import (`env.shellEnv.enabled` or `OPENCLAW_LOAD_SHELL_ENV=1`), applied only for missing expected keys.

## Security Notes

- `openclaw-gateway` is bound to loopback only: `127.0.0.1:${OPENCLAW_GATEWAY_PORT}`.
- No Signal RPC host port is published. It is reachable only on Docker networks.
- `cap_drop: [ALL]` and `no-new-privileges` are enabled for OpenClaw services.
- Never commit real secrets in git.
- OpenClaw image is pinned directly in `compose.yaml`, which lets Renovate update it in git.

## Permissions Gotcha

OpenClaw writes media files with restrictive permissions. If `signal-rpc` needs to read those files and cannot:

- run `signal-rpc` as root, or
- run both services with the same UID/GID, or
- align ownership/mode on shared volume paths.

Shared media mount in `compose.yaml` (enabled by default):

```yaml
- openclaw_state:/home/node/.openclaw:ro
```

If you do not want `signal-rpc` to read OpenClaw media, comment out that line in `services/openclaw/compose.yaml`.

## References

- https://docs.openclaw.ai/install/docker
- https://docs.openclaw.ai/channels/signal
- https://docs.openclaw.ai/nodes

## Troubleshooting

If you see `EISDIR` for `~/.openclaw/openclaw.json`, a previous bind mount likely created a directory at that path in `openclaw_state`.

One-time cleanup:

```bash
docker run --rm -v openclaw_state:/state alpine sh -lc 'rm -rf /state/openclaw.json'
```
