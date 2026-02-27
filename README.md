# lan-infra

Infrastructure services for home/lab workloads managed with Docker Compose + Portainer + GitOps.

## Architecture (high-level)

```mermaid
flowchart LR
  subgraph Users[Clients]
    iPhone[iPhone / Apple Home]
    Browser[Browsers / LAN clients]
    TV[Media clients]
  end

  subgraph Edge[Edge & Access]
    CF[cloudflared]
    NPM[nginx-proxy-manager]
    TS[tailscale-subnet-router]
  end

  subgraph Control[Control Plane]
    Portainer[Portainer]
    GH[GitHub repo + PR workflow]
  end

  subgraph Core[Core Services]
    HA[Home Assistant]
    Avahi[avahi-reflector]
    Mosquitto[mosquitto]
    Redis[redis]
    Postgres[postgres]
  end

  subgraph Apps[App Services]
    Nextcloud[nextcloud]
    Paperless[paperless-ngx]
    Immich[immich]
    Plex[plex]
    Adguard[adguard]
    SignalRpc[signal-cli-rpc]
    SignalRest[signal-cli-rest-api]
    OpenClaw[openclaw]
  end

  GH --> Portainer
  Portainer --> Core
  Portainer --> Apps

  iPhone --> HA
  Browser --> NPM
  TV --> Plex

  CF --> NPM
  TS --> NPM

  HA --- Avahi
  HA --> Mosquitto
  HA --> SignalRpc

  OpenClaw --> HA
  OpenClaw --> SignalRpc
  SignalRest --> SignalRpc

  Nextcloud --> Postgres
  Paperless --> Redis
  Paperless --> Postgres
  Immich --> Redis
  Immich --> Postgres
```

## Notes

- This diagram is intentionally high-level, not an exhaustive dependency graph.
- HomeKit bridge mode relies on:
  - published HomeKit ports in `services/home-assistant/compose.yaml`
  - `avahi-reflector` for mDNS reflection in network-isolated setups
