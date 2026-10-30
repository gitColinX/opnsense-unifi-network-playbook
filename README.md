# OPNsense + UniFi home network, rebuilt end to end with Claude Code

A used Lenovo ThinkCentre Tiny running OPNsense, a UniFi Wi-Fi 7 access point and a 2.5GbE
UniFi switch, retuned in one long session from the router's NIC down to the desktop's NIC.
Faster, quieter, segmented, monitored and encrypted, on hardware that costs a fraction of an
enterprise firewall.

Done in October 2026 with Claude Code as the operator over SSH and REST APIs, with me approving
each step. Everything here is what actually ran, including the mistakes and how they were caught.

## Results

| | Before | After |
|---|---|---|
| Desktop download (2.1 Gbps plan) | ~940 Mbps (wrong NIC port) | **2,362 Mbps** (Ookla) |
| Worst lag during a full upload | 121 ms, 2.5% loss | **24 ms, 0% loss** |
| Ads/trackers/malware domains blocked | 0 | **~2 million**, every device, at home and away |
| Known attacker IPs blocked | 0 | **~15,000** (CrowdSec, refreshed automatically) |
| IoT devices able to reach my PCs | all of them | **none** (own VLAN, own firewall rules) |
| DNS readable by the ISP | yes | **no** (DNS-over-TLS, malware-filtering resolver) |
| Log history | 31 days, router only | **365 days**, nightly copy to cloud storage |
| Phone alerts | none | new device, IDS hit, outbound attacker contact, service down, weekly report |
| Router CPU at full 2+ Gbps with IDS on | – | **~90% idle** |

## The steps, and why

| # | Step | Why |
|---|---|---|
| 1 | Replace the legacy UniFi Network app with UniFi OS Server, restore the backup | The old app held the same ports and couldn't issue API keys. OS Server can. |
| 2 | API keys and SSH keys for everything (router, UniFi, ntopng, Tailscale) | So an agent can read and change config precisely, with every secret kept out of the chat. |
| 3 | Major OPNsense upgrade (snapshot + config backup first) | The old series was end-of-life. A ZFS boot environment makes rollback a reboot. |
| 4 | Move DHCP from ISC to dnsmasq, reserve key addresses | ISC DHCP is end-of-life. dnsmasq also feeds hostnames into DNS. |
| 5 | DNS blocklists in Unbound | Pi-hole-style ad and malware blocking for every device, at zero throughput cost. |
| 6 | Upload-only FQ-CoDel smart queuing | Download didn't bloat. Upload did. Shaping only upload fixed lag without touching download speed. |
| 7 | 365-day DNS and firewall logs, ntopng, NetFlow | Per-device "what talked to what", a year back, for audits or an AI review. |
| 8 | CrowdSec | Community blocklist of active attackers. Negligible cost, checked for false positives. |
| 9 | Name every device, fixed IPs | You can't secure what shows up as a random MAC. Also the prerequisite for VLANs. |
| 10 | Suricata IDS (watch mode first) | Threat detection with ~30k rules. Measured drops and throughput before trusting it. |
| 11 | IoT and Guest VLANs, forced DNS, mDNS relay | Cheap gadgets can't reach PCs. Printing and casting still work. |
| 12 | Phone alerts via ntfy | New devices, IDS hits, services going down, weekly summary. |
| 13 | Tailscale on the router | Whole home network from anywhere, plus ad blocking on the phone away from home. |
| 14 | Log retention + nightly off-router copy | The router isn't the only place the evidence lives. |
| 15 | Final tuning pass, router NIC to desktop NIC | Power-saving and flow-control quirks off, bigger rings, bigger DNS cache, encrypted DNS. |

Each step, with the commands, the test and what went wrong, is in **[docs/GUIDE.md](docs/GUIDE.md)**.

## How Claude Code did it

Two kinds of access, each used for what it's good at:

- **REST APIs** (OPNsense, UniFi, ntopng, Tailscale) for configuration. The same changes the web UI
  makes, applied precisely and readable back to confirm.
- **SSH** (router and access point, key-only) for what no API exposes: hardware and BIOS info,
  logs, firewall state counters, packet captures, live speed and lag tests run *from* the router,
  and the handful of settings the API can't reach.

Secrets never went through the chat. I created each key in the vendor's UI and saved it straight
from the clipboard into a Windows user variable or a DPAPI-encrypted file, and Claude read it from
there. Sign-ins and Wi-Fi passwords stayed with me. More in **[docs/CLAUDE-CODE.md](docs/CLAUDE-CODE.md)**.

## More

- [docs/GUIDE.md](docs/GUIDE.md): the full step-by-step
- [docs/TESTING.md](docs/TESTING.md): how each change was measured, with before and after numbers
- [docs/SECURITY.md](docs/SECURITY.md): the security model and the trade-offs
- [docs/LESSONS.md](docs/LESSONS.md): the surprising things this turned up
- [docs/HARDWARE.md](docs/HARDWARE.md): the box, the parts and why they're enough
- [scripts/](scripts/): the watcher, the test scripts and the tuning scripts, sanitized

Addresses, names and identifiers in this repo are placeholders, not my real network.

## License

MIT
