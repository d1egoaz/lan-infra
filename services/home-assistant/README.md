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
  - advertise_ip: "<DOCKER_HOST_LAN_IP>"
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
5. Verify that the service hostname includes `<DOCKER_HOST_LAN_IP>` before
   pairing it in Apple Home.

Example verification on macOS:

```sh
dns-sd -B _hap._tcp local.
dns-sd -L '<HOMEKIT_INSTANCE_NAME>' _hap._tcp local.
dns-sd -G v4 '<ADVERTISED_HOSTNAME>.local.'
nc -vz <DOCKER_HOST_LAN_IP> <HOMEKIT_PORT>
```

The address list may also contain a Docker address. That is acceptable as long
as it includes the routable host LAN address and the published host port is
reachable from the HomeKit client's network.

If discovery works but pairing remains on **Setting Up** until it times out,
check the resolved address first. Opening more ports will not fix an
advertisement that points exclusively to an unreachable container address.

See the upstream Home Assistant documentation for
[`advertise_ip` and Docker network isolation](https://www.home-assistant.io/integrations/homekit/#docker-network-isolation).

## State and backups

The `homeassistant-data` volume is external and mounted at `/config`. It holds
the runtime configuration and HomeKit pairing state; those files are not part
of this public repository. Back up the volume separately before migrating the
stack or deleting Docker volumes.
