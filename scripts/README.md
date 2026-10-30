# Scripts

Sanitized copies of what ran. Addresses use the placeholder ranges from the guide
(`10.0.10.0/24` Main, `10.0.20.0/24` IoT, `10.0.30.0/24` Guest). Interface names (`igc0` WAN,
`igc1` LAN, `vlan0.20`, `vlan0.30`) match an Intel I226 box. Adjust both for yours.

## Router (OPNsense, run as root over SSH)

| Script | What it does |
|---|---|
| [`router/netwatch.py`](router/netwatch.py) | Phone alerts via [ntfy](https://ntfy.sh): new MACs on any network, new Suricata alerts, CrowdSec **outbound** blocks, services down/recovered, and a weekly digest. State lives in `/root/netwatch/`; the ntfy topic sits in `/root/netwatch/topic` (treat it like a secret). Commands: `run`, `digest`, `seed`, `test`, `approve <mac>`. |
| [`router/export-day.sh`](router/export-day.sh) | Streams one day's logs (`/var/log/*/*_YYYYMMDD.log` + Suricata alerts) as `tar.gz` on stdout, for the nightly off-router copy. |
| [`router/bloat.sh`](router/bloat.sh) | Bufferbloat test from the router: ping idle, under full download, under full upload. |
| [`router/dl.sh`](router/dl.sh) | Multi-server download test with a steady-state WAN counter and CPU sample. |
| [`router/dnsbench.sh`](router/dnsbench.sh) | Times 20 uncached DNS lookups (flushes Unbound's cache for each). |
| [`router/add-vlan-ifs.php`](router/add-vlan-ifs.php) | Assigns VLAN devices as OPNsense interfaces with static IPs using OPNsense's own PHP functions (no API exists for this). |
| [`router/add-ts-if.php`](router/add-ts-if.php) | Assigns `tailscale0` as an interface so it can have firewall rules. |

### Scheduling netwatch the OPNsense way

Custom cron entries get overwritten, so register a configd action and schedule it under
**System > Settings > Cron** (or `/api/cron/settings/addJob`):

```ini
# /usr/local/opnsense/service/conf/actions.d/actions_netwatch.conf
[run]
command:/usr/local/bin/python3 /root/netwatch/netwatch.py run
parameters:
type:script
message:netwatch check
description:Netwatch new-device and security alerts

[digest]
command:/usr/local/bin/python3 /root/netwatch/netwatch.py digest
parameters:
type:script
message:netwatch weekly digest
description:Netwatch weekly network report
```

Then `service configd restart`, and add cron jobs for `netwatch run` (every minute) and
`netwatch digest` (weekly).

## Windows

| Script | What it does |
|---|---|
| [`windows/Sync-OPNsenseLogs.ps1`](windows/Sync-OPNsenseLogs.ps1) | Nightly: pulls missed days of router logs and a config backup into cloud-synced storage. Runs as a regular-user scheduled task with "run when available". |
| [`windows/lan-dl.ps1`](windows/lan-dl.ps1) | Download test from the desktop *through* the router, reading the NIC byte counter while sampling router CPU over SSH. |
| [`windows/dnsbl-test.ps1`](windows/dnsbl-test.ps1) | Before/after blocklist test: 20 ad/tracker and 15 must-work domains, resolved from a LAN client (the AP over SSH). |
| [`windows/nic-tune.ps1`](windows/nic-tune.ps1) | Realtek 2.5GbE desktop tuning (run elevated): power-saving features off, flow control off, VLAN tagging off, 4096 buffers, no NIC power-down. |

All Windows scripts expect an SSH config with `Host opnsense` (and `Host unifi-ap` for the DNS
test) using key auth, and an OPNsense API key stored with `Export-Clixml` at
`%USERPROFILE%\.secrets\opnsense-api.xml`.
