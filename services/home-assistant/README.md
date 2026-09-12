# Home Assistant

This stack keeps Home Assistant on its Docker bridge networks and also attaches
it to a dedicated LAN IPvlan network. AirPlay and HomeKit use the container's
stable IPvlan address; an mDNS reflector makes discovery available across the
required network segments.

## HomeKit on the LAN IPvlan address

Do not advertise the Docker host address for HomeKit after attaching Home
Assistant to IPvlan. A connection received through a Docker-published host port
can return directly through IPvlan, bypassing Docker's reverse-NAT path and
timing out. The HomeKit service remains reachable directly on the container's
stable LAN address.

Configure every HomeKit bridge with the Home Assistant container's stable LAN
address:

```yaml
homekit:
  - name: "Example Camera"
    port: 21070
    mode: accessory
    advertise_ip: "<HOME_ASSISTANT_LAN_IP>"
    filter:
      include_entities:
        - camera.example_camera
    entity_config:
      camera.example_camera:
        stream_address: "<HOME_ASSISTANT_LAN_IP>"
```

Use a unique TCP port for each bridge or accessory. This deployment uses ports
in the `21063-21084` range, but it does not publish them through the Docker
host; clients connect to those ports directly on `<HOME_ASSISTANT_LAN_IP>`.

The `advertise_ip` option is part of the HomeKit YAML configuration. A HomeKit
bridge created through the Home Assistant UI does not inherit options from an
unrelated YAML entry. When migrating an already-paired bridge, preserve the
HomeKit pairing files in `/config/.storage` and update the bridge's stored
advertisement address rather than deleting and re-pairing it.

For cameras, also set `stream_address` to the IPvlan address so RTP uses the
same routable interface as the HomeKit control connection.

After changing the configuration:

1. Validate the Home Assistant configuration.
2. Restart Home Assistant.
3. Confirm the configured TCP port is listening on the container LAN address
   from a separate LAN client. IPvlan host isolation may prevent the Docker
   host itself from reaching the container address.
4. Browse `_hap._tcp.local.` and resolve the new HomeKit service.
5. Verify that the service hostname resolves to `<HOME_ASSISTANT_LAN_IP>` before
   testing it in Apple Home.

Example verification on macOS:

```sh
dns-sd -B _hap._tcp local.
dns-sd -L '<HOMEKIT_INSTANCE_NAME>' _hap._tcp local.
dns-sd -G v4 '<ADVERTISED_HOSTNAME>'
nc -vz <HOME_ASSISTANT_LAN_IP> <HOMEKIT_PORT>
```

Pass `<ADVERTISED_HOSTNAME>` exactly as reported by `dns-sd -L`, including its
trailing `.local.` suffix.

The address list must include the routable IPvlan address. Docker-only addresses
and an unreachable Docker-host publication are not valid HomeKit paths.

If discovery works but pairing remains on **Setting Up** until it times out,
check the resolved address first. Opening more ports will not fix an
advertisement that points to the wrong interface.

For clients on another VLAN, reflect UDP `5353` discovery and permit the
required HomeKit control and camera traffic to `<HOME_ASSISTANT_LAN_IP>`.

See the upstream Home Assistant documentation for
[`advertise_ip` and Docker network isolation](https://www.home-assistant.io/integrations/homekit/#docker-network-isolation).

## State and backups

The `homeassistant-data` volume is external and mounted at `/config`. It holds
the runtime configuration and HomeKit pairing state; those files are not part
of this public repository. Back up the volume separately before migrating the
stack or deleting Docker volumes.
