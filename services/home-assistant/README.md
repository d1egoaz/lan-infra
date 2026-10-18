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

## Reaching the web UI (published port 8123)

The stack publishes `8123:8123`, and that publish is load-bearing even though a
LAN client cannot use it. The container joins four networks, including the
`homeassistant_lan` IPvlan network with the stable address `192.168.42.80`, so
it is multi-homed. When a client on `192.168.42.0/24` connects to the Docker
host address `192.168.42.2:8123`, the reply leaves the container on the IPvlan
interface instead of the bridge, the host reverse-NAT path never sees it, and
the connection times out. Other published ports on the same host are unaffected
because those containers are not on an IPvlan network.

The two working entry points are:

| Client | Address | Carries |
|---|---|---|
| LAN clients | `http://192.168.42.80:8123` | direct on the IPvlan address |
| In-host consumers | `http://192.168.42.2:8123` (this publish) | the NPM proxy host for `ha.lan.diegoa.ca`, Home Assistant's own internal-URL self-fetch, and the Cloudflare tunnel |

So `192.168.42.2:8123` timing out from a LAN machine is expected, not a broken
publish. Removing the publish would break NPM and the `ha.lan.diegoa.ca` URL the
workspace helpers use. NPM could not reach the IPvlan address in the checked
topology. Keep the publish unless that routing is changed and verified first.

The `extra_hosts` entries for `ha.lan.diegoa.ca`, `adguard.lan.diegoa.ca`, and
`paperless.lan.diegoa.ca` route HA's HTTPS requests through the app-network
gateway at `172.24.0.1`, retaining the original hostname and TLS validation.
Without the two latter overrides, their DNS resolves to the parent host's LAN
address, which HA cannot reach through IPvlan. Paperless also needs its backend
startup failure repaired; a hostname override alone does not restore it.

## Privileged mode and device access

This source change removes `privileged: true`; the running container remains
privileged until it is recreated from the updated Compose file. ZHA's
coordinator remains explicitly granted:

```yaml
devices:
  - /dev/ttyUSB0:/dev/ttyUSB0
```

Home Assistant is configured against that path directly (`SMLIGHT SLZB-07`,
`ezsp`, `/dev/ttyUSB0`); `/dev/serial/by-id` does not exist in this image. The
`/run/dbus` bind mount stays read-only, and no capabilities are added. Dropping
privileged mode removes access to the entire host device tree and the extra
capabilities; the inspected configuration identified no need for them. That
inspection does not replace runtime verification after the recreate. The tradeoff is
that a new USB device must be listed under `devices:` by path, because it no
longer appears inside the container on its own.
Default seccomp and AppArmor confinement also return, so post-recreate
verification must cover the running integrations, not just the USB mapping.

## Logs and rotation

There are two independent logs.

Docker stdout/stderr is capped by the daemon: `json-file`, `max-size 10m`,
`max-file 3` (about 30 MB), set in `/etc/docker/daemon.json`. That is already in
place and does not cover the in-volume file.

`/config/home-assistant.log` is written inside the `homeassistant-data` volume,
that is `/home/docker/volumes/home-assistant_homeassistant-data/_data` on the
host. Home Assistant starts through s6 with no `--log-rotate-days`, so it rolls
this file only at startup and grows without bound during a session (~3 MB/day
observed). The compose `command:` key is deliberately not used to add the flag:
this image has `Entrypoint ["/init"]` with a null `Cmd`, and Home Assistant is
launched by `/etc/services.d/home-assistant/run`. A compose `command:` would
replace the argument handed to s6's `/init`, not Home Assistant's own argv, so
it cannot set the rotate flag and could disturb the s6 lifecycle.

The proposed host logrotate drop-in is `logrotate.conf` in this directory.
It is not installed yet and Portainer does not deploy it; install it by hand.

Install, from a checkout of this repository on the host:

```sh
sudo install -o root -g root -m 0644 services/home-assistant/logrotate.conf /etc/logrotate.d/home-assistant
```

Validate without changing anything (`-d` dry-runs: it parses the file, prints
what it would do, writes no state, and rotates nothing):

```sh
sudo logrotate -d /etc/logrotate.d/home-assistant
```

Do not use `-f`: a forced rotation runs out of schedule and is not a test.

Remove:

```sh
sudo rm -f /etc/logrotate.d/home-assistant
```

What the policy does, stated honestly:

- Rotation is time-based. `daily` with `rotate 7` keeps about a week of history,
  with size depending on log traffic and compression.
- `maxsize 25M` is a backstop, not a hard cap. logrotate evaluates it only when
  logrotate runs, and `logrotate.timer` fires once a day at 00:00 UTC, so a
  burst above 25 MB is not rotated until the next run. It is not a disk quota.
- `copytruncate` has a small race: Home Assistant keeps writing during the copy,
  and a line written between the copy and the truncate is lost. It is used
  because the running process cannot be asked to reopen the file.
- `dateext` names rotated files `home-assistant.log-YYYYMMDD[.gz]` so they do
  not collide with the `home-assistant.log.1` Home Assistant writes on startup.

Actual rotation is not yet verified. It can only be confirmed after the next
scheduled run, by a dated rotated file appearing next to a fresh, small
`home-assistant.log` while Home Assistant keeps appending.

## Deploying and verifying this change

The compose edit is deployed by Portainer GitOps (about 15 minutes) and needs a
container recreate. Verify after the recreate:

1. Privileged mode is off and the coordinator is still mapped:
   ```sh
   docker inspect --format '{{.HostConfig.Privileged}} {{json .HostConfig.Devices}}' homeassistant
   # false [{"PathOnHost":"/dev/ttyUSB0","PathInContainer":"/dev/ttyUSB0","CgroupPermissions":"rwm"}]
   ```
2. The capability set is the default and the extra device tree is gone:
   ```sh
   docker exec homeassistant grep CapEff /proc/self/status
   docker exec homeassistant ls /dev
   # no dm-*, dri, gpiochip*, i2c-*, hidraw*
   ```
3. Home Assistant reports `RUNNING`.
4. The ZHA integration is loaded and its Zigbee devices keep reporting fresh
   values (Settings > Devices & Services, then the device history).
5. No permission errors:
   `docker exec homeassistant grep -i 'permission denied' /config/home-assistant.log`
   No output and exit status 1 means no matching error; other failures need diagnosis.
6. One physical light on/off round trip. This last step changes real hardware
   and is done only on the owner's explicit request and confirmation.

The logrotate drop-in is independent and only takes effect at the next scheduled
run. Confirm it afterwards:

```sh
ls -l /home/docker/volumes/home-assistant_homeassistant-data/_data/home-assistant.log*
```

### Rollback

Compose: restore the `privileged: true` line in
`services/home-assistant/compose.yaml` and redeploy through Portainer. The
recreate touches no volume data.

Logrotate: remove the drop-in. Keep existing logs for diagnosis:

```sh
sudo rm -f /etc/logrotate.d/home-assistant
```

## State and backups

The `homeassistant-data` volume is external and mounted at `/config`. It holds
the runtime configuration and HomeKit pairing state; those files are not part
of this public repository. Back up the volume separately before migrating the
stack or deleting Docker volumes.
