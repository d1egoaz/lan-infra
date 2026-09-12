# Home Assistant

This stack runs Home Assistant behind Docker bridge networking and publishes
HomeKit services through an mDNS reflector. The Compose file exposes the
HomeKit TCP port range through a bridge-only proxy, while Home Assistant keeps
a separate LAN address for AirPlay.

## HomeKit behind Docker bridge networking

When Home Assistant runs on a Docker bridge, automatic discovery can publish a
container-only address such as `172.18.0.2`. A phone or computer on the LAN may
then discover the bridge but time out during pairing because it cannot connect
to that address.

Configure YAML-managed HomeKit bridges with the Docker host's stable LAN
address:

```yaml
homekit:
  - name: "Example Camera"
    port: 21070
    mode: accessory
    advertise_ip: "<DOCKER_HOST_LAN_IP>"
    filter:
      include_entities:
        - camera.example_camera
```

Use a unique TCP port for each bridge or accessory. This stack reserves and
publishes `21063-21084` through `homekit-port-proxy`.

The `advertise_ip` option is part of the HomeKit YAML configuration. A HomeKit
bridge created through the Home Assistant UI does not inherit options from an
unrelated YAML entry. If a UI-created bridge advertises its Docker address,
remove that unpaired entry and recreate it as a YAML-managed entry.

After changing the configuration:

1. Validate the Home Assistant configuration.
2. Restart Home Assistant.
3. Confirm the configured TCP port is listening on the Docker host.
4. Browse `_hap._tcp.local.` and resolve the new HomeKit service.
5. Verify that the service hostname resolves to `<DOCKER_HOST_LAN_IP>` before
   pairing it in Apple Home.

Example verification on macOS:

```sh
dns-sd -B _hap._tcp local.
dns-sd -L '<HOMEKIT_INSTANCE_NAME>' _hap._tcp local.
dns-sd -G v4 '<ADVERTISED_HOSTNAME>'
nc -vz <DOCKER_HOST_LAN_IP> <HOMEKIT_PORT>
```

Pass `<ADVERTISED_HOSTNAME>` exactly as reported by `dns-sd -L`, including its
trailing `.local.` suffix.

The address list may also contain a Docker address. That is acceptable as long
as it includes the routable host LAN address and the published host port is
reachable from the HomeKit client's network.

If discovery works but pairing remains on **Setting Up** until it times out,
check the resolved address first. Opening more ports will not fix an
advertisement that points exclusively to an unreachable container address.

See the upstream Home Assistant documentation for
[`advertise_ip` and Docker network isolation](https://www.home-assistant.io/integrations/homekit/#docker-network-isolation).

## Why HomeKit uses a bridge-only proxy

Home Assistant also has the reserved LAN address `192.168.42.80` on the
external `homeassistant_lan` IPvlan network. `pyatv` needs that routable source
address for HomePod AirPlay and TTS return traffic.

The IPvlan interface changes the return path for connections published directly
from the Home Assistant container. A LAN client can reach a HomeKit port on the
container's own LAN address, but a connection to the same port on the Docker
host address times out because the reply leaves through IPvlan instead of
returning through Docker's published-port path.

`homekit-port-proxy` avoids that asymmetric path without changing existing
HomeKit advertisements or pairings:

1. The HomeKit client connects to the advertised Docker host LAN address.
2. Docker publishes `21063-21084` from the bridge-only proxy.
3. The proxy opens a separate connection to `homeassistant` on the same Docker
   bridge and destination port.
4. Home Assistant returns that connection over the Docker bridge while keeping
   its IPvlan address available for AirPlay.

The proxy deliberately joins only the `homeassistant` Docker bridge. Do not
attach it to `homeassistant_lan`, or it can acquire the same asymmetric return
path it exists to avoid.

HAProxy preserves the frontend destination port when its backend server has no
port configured, so one frontend range covers every reserved HomeKit port. Its
Docker DNS resolver and TCP health check follow Home Assistant container address
changes after restarts.

After deploying, verify both paths independently:

```sh
# Existing HomeKit path through the Docker host and bridge-only proxy
nc -vz <DOCKER_HOST_LAN_IP> 21063
nc -vz <DOCKER_HOST_LAN_IP> 21070
nc -vz <DOCKER_HOST_LAN_IP> 21073

# Direct LAN path retained for Home Assistant and AirPlay
nc -vz 192.168.42.80 8123
```

Then control an accessory from Apple Home and run a Home Assistant `tts.speak`
action against a HomePod. Compose validation alone cannot verify either runtime
path.

## State and backups

The `homeassistant-data` volume is external and mounted at `/config`. It holds
the runtime configuration and HomeKit pairing state; those files are not part
of this public repository. Back up the volume separately before migrating the
stack or deleting Docker volumes.
