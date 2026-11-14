# Paperless environment

The Portainer stack must supply a non-empty `PAPERLESS_SECRET_KEY` before
Compose can deploy this service. Paperless 3.2.0 rejects a missing or default
key at startup; without the interpolation check, an empty stack variable can
produce a persistent restart loop instead of a failed deployment.

Reuse the original deployment key. Its source was not recovered in the
2026-10-17 review; do not automatically replace it, print it in a command, or
commit it. Rotation can invalidate signed application state and needs an
explicit account-owner decision. The stack also needs its intended
`PAPERLESS_URL`, currently `https://paperless.lan.diegoa.ca`.

This source check does not repair an already-running failed container or
populate Portainer's environment. After restoring the environment and an
authorized redeploy, verify the container stays up, the missing-key error
stops, the proxy serves the application, and the HA integration reconnects.
Keep the database and document volumes intact.
