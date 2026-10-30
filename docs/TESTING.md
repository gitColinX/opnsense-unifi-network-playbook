# How things were measured

Every change got a test. The tools are in [`scripts/`](../scripts/).

## Throughput

| Test | How | Why this way |
|---|---|---|
| Router WAN rate | `dl.sh` on the router: parallel `curl` from public speed-test files on several servers, WAN byte counter over a 5-second steady window | Distant single servers under-report a 2 Gbps line; the counter shows the real rate |
| Through the router to the desktop | `lan-dl.ps1`: 12–16 parallel downloads on the desktop, NIC byte counter, router CPU sampled over SSH at the same time | Exercises the LAN, firewall, IDS and NAT path |
| Real-world | Ookla to a nearby server | The number that matches what you pay for |

**Lesson:** the first "1.3 Gbps" reading was the test, not the network. Far-away servers and TCP
ramp-up undercounted. With more servers in parallel, the WAN showed 2.1–2.4 Gbps.

**Lesson:** the desktop's real bottleneck was a 1 GbE port. The motherboard had an unused 2.5GbE port.

## Lag under load (bufferbloat)

`bloat.sh` on the router: 40 pings to a public resolver while idle, during a full download, and
during a full upload.

| | Avg | Worst | Loss |
|---|---|---|---|
| Upload, before shaping | 23 ms | 121 ms | 2.5% |
| Upload, FQ-CoDel at ~97% of line | 13 ms | 24 ms | 0% |
| Download (never shaped) | +4 ms over idle | – | 0% |

## DNS

- **Blocklist:** `dnsbl-test.ps1` resolves 20 ad/tracker domains and 15 must-work domains from a LAN
  client (the access point over SSH).
- **Uncached speed:** `dnsbench.sh` flushes 20 names from Unbound's cache and times each lookup.

| Upstream | Uncached average |
|---|---|
| Full recursion | 79–112 ms |
| Resolver A over TLS (nearest node 40 ms away) | 84–172 ms |
| Resolver B over TLS (local node, 12 ms) | **44–88 ms** |

- **Encryption check:** packet capture on WAN, counting port 53 (plain) vs 853 (TLS) packets: 0 vs 120.
- **DNSSEC check:** `dnssec-failed.org` must SERVFAIL, `isc.org` must resolve.

## Security features

| Feature | Check |
|---|---|
| CrowdSec | 81 IPs behind 30 everyday services checked against the blocklist table (0 listed); a known-listed IP confirmed as listed; A/B throughput with rules on and off |
| Suricata | Capture drop counter after 8.26M packets at ~1.7 Gbps: 347 drops (0.004%) |
| VLAN isolation | Firewall log showed IoT → Main attempts blocked; Main → IoT printer ports reachable; mDNS printer discovery via the relay only (not directly) |
| Alerts | Simulated unknown device; stopped a service for 2 minutes |
| Tailscale | Phone on cellular: router UI, exit node showing the home IP, remote DNS blocking counted on the router |
