# lan-infra

Infrastructure services for home/lab workloads managed with Docker Compose + Portainer + GitOps.

## Architecture (high-level)

```mermaid
flowchart TB
  %% Zones
  subgraph OUTSIDE[Outside network clients]
    Internet[Remote users / Internet]
  end

  subgraph DMZ[DMZ / Edge zone]
    Cloudflared[cloudflared]
    NPM[nginx-proxy-manager]
    Tailscale[tailscale-subnet-router]
    Host[macmini4 host]
  end

  subgraph CONTROL[Control plane]
    GitHub[GitHub repo + PR workflow]
    Portainer1[Portainer #1]
    Portainer2[Portainer #2]
  end

  subgraph COMMON[Common services layer]
    Redis[redis]
    Postgres[postgres]
    Mosquitto[mosquitto]
    SignalRPC[signal-cli-rpc]
    Adguard[adguard]
  end

  subgraph INSIDE[Inside LAN apps]
    HA[Home Assistant]
    Avahi[avahi-reflector]
    SignalREST[signal-cli-rest-api]
    Plex[plex]
    Immich[immich]
    OpenClaw[openclaw]
  end

  %% Exposure path
  Internet --> Cloudflared --> NPM

  %% Edge and control
  Tailscale --> NPM
  Host --> Portainer1
  Host --> Portainer2
  GitHub --> Portainer1
  GitHub --> Portainer2

  %% Portainer ownership split
  Portainer1 --> SignalREST
  Portainer2 --> SignalRPC

  %% Shared services dependencies
  HA --> Mosquitto
  HA -. mDNS .- Avahi
  OpenClaw --> HA
  OpenClaw --> SignalRPC
  SignalREST --> SignalRPC
  Paperless[paperless-ngx] --> Redis
  Paperless --> Postgres
  Immich --> Redis
  Immich --> Postgres
  Nextcloud[nextcloud] --> Postgres

  %% Access to internal apps
  NPM --> HA
  NPM --> Plex
```

## Notes

- This diagram is intentionally high-level, not an exhaustive dependency graph.
- HomeKit bridge mode relies on:
  - published HomeKit ports in `services/home-assistant/compose.yaml`
  - `avahi-reflector` for mDNS reflection in network-isolated setups
