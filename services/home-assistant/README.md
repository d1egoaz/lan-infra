# Home Assistant

This stack runs Home Assistant behind Docker bridge networking and publishes
HomeKit services through an mDNS reflector. The Compose file exposes the
HomeKit TCP port range, but each HomeKit bridge must also advertise an address
that HomeKit clients can route to.

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

Use a unique TCP port for each bridge or accessory, and publish that port from
the container. This stack reserves `21063-21084` for HomeKit.

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

## Keep the published HomeKit ports reachable

HomeKit clients connect to the Docker host's LAN address, so the published
`21063-21084` range has to be reachable there. Listening inside the container
is not enough.

Do not attach this container to an L2 LAN network (`ipvlan` or `macvlan`) while
HomeKit is advertised that way. With an L2 LAN interface the container answers
LAN clients directly instead of through the Docker host, so the published ports
time out from the LAN while the same ports still answer on the container's own
LAN address:

```sh
nc -vz <DOCKER_HOST_LAN_IP> <HOMEKIT_PORT>   # times out
nc -vz <CONTAINER_LAN_IP> <HOMEKIT_PORT>     # succeeds
```

Adding the L2 LAN interface and moving the advertisement are one change, not
two. Attach the LAN network first: the adapter only exists inside the container
after the network is attached, so it cannot be enabled before that.

1. Attach the L2 LAN network to this stack and start the container.
2. Enable that adapter in the Network panel (Settings > System > Network).
   Addresses of enabled adapters are announced by UI-created bridges, and a
   UI-created bridge cannot set `advertise_ip` itself; it can only announce
   addresses that exist on the container.
3. Set `advertise_ip` to the container's LAN address on every YAML-managed
   bridge, then reload the HomeKit integration or restart Home Assistant.
4. Confirm `dns-sd -G v4 <uuid>-hap.local` resolves to the container's LAN
   address and that HomeKit answers from a phone on the LAN. Allow one reload
   for the previous address to clear.

Going back is the mirror image: detach the L2 LAN network first, then point
`advertise_ip` back at the Docker host LAN address, then reload. The
host-published ports are unreachable while the L2 LAN interface is attached,
and the container's LAN address leaves the advertisement as soon as it is
detached.

Leaving those two states out of step is what breaks HomeKit: every bridge keeps
advertising an address that nothing answers on, so discovery works and every
connection times out.

This stack currently keeps Home Assistant off the LAN network on purpose, see
the ports comment in `compose.yaml`. The AirPlay LAN source address added for
the Home Assistant TTS path is parked until the advertisement above moves; both
changes land together.

## State and backups

The `homeassistant-data` volume is external and mounted at `/config`. It holds
the runtime configuration and HomeKit pairing state; those files are not part
of this public repository. Back up the volume separately before migrating the
stack or deleting Docker volumes.
