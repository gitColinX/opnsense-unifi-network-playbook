# The full guide

Every step has the same shape: **why**, **what was done**, **how it was tested**, and
**what went wrong** (if anything). Addresses are placeholders:

| Network | Placeholder | VLAN |
|---|---|---|
| Main (PCs, phones) | `10.0.10.0/24`, router `10.0.10.1` | untagged |
| IoT | `10.0.20.0/24` | 20 |
| Guest | `10.0.30.0/24` | 30 |
| UniFi OS Server host (the desktop) | `10.0.10.10` | – |

**Ground rule for every step:** download a config backup from the router first
(`/api/core/backup/download/this`), change one thing, test it, write it down. Before the major
upgrade, also take a ZFS boot-environment snapshot.

---

## 1. UniFi OS Server instead of the legacy Network app

**Why.** The legacy UniFi Network Application nagged to migrate, and only UniFi OS issues API keys.

**What.** The new UniFi OS Server failed at startup with `Failed to bind to port 6789`
(`EACCES`). Cause: the legacy app was still running and holding 6789, 8080 and 3478. Both
can't run at once. Stopped the legacy app cleanly (`java -jar lib\ace.jar stop`), started
OS Server, updated its bundled Network app to match the backup's version, then restored the
legacy `.unf` backup. Uninstalled the legacy app afterwards, backups copied off first.

**Test.** Access point online on the new server, Wi-Fi networks and clients restored.

**Gotchas.**
- A backup only restores into the same or a newer Network version. OS Server shipped an older
  one, so update first.
- The switch had been stuck "adopting" since months earlier. Root cause found later (step 9):
  it was asking DNS for the default controller name `unifi`, which didn't exist. One DNS host
  override pointing `unifi` at the server fixed it. No factory reset needed.

## 2. Access for the agent: API keys and SSH keys

**Why.** Clicking through four web UIs is slow and error-prone. APIs are precise and let every
change be read back.

**What.**
- OPNsense: a dedicated API user; key+secret stored DPAPI-encrypted on the PC (`Export-Clixml`).
- UniFi OS: an Integration API key (also works on the classic `/proxy/network/api/s/default/...`
  endpoints for things like renaming clients and editing Wi-Fi networks).
- Router SSH: root, **key-only, LAN-only**, a dedicated ed25519 key.
- UniFi device SSH: the same idea, public key added in "Device SSH Settings". Password login was
  turned off later (step 15).
- ntopng REST token and a short-lived (7-day) Tailscale API token, added when those steps came up.

Every key was created by me in the vendor UI and saved straight from the clipboard:

```powershell
[Environment]::SetEnvironmentVariable('UNIFI_API_KEY', (Get-Clipboard).Trim(), 'User')
Set-Clipboard -Value ' '   # then delete it from the clipboard manager's history too
```

## 3. Major OPNsense upgrade

**Why.** The installed series was end-of-life (no more updates).

**What.** Config backup, ZFS boot-environment snapshot (`/api/core/snapshots/add`), removed the
Intel microcode plugin (the release notes warned it can hang boot on this release), then ran the
major upgrade through the API. About 6 minutes of downtime.

**Test.** Interfaces, gateways, DNS, DHCP up. Config diff against the pre-upgrade backup: identical.

**Note.** "Import config + reinstall" is only needed to change filesystem or start clean. On ZFS,
upgrade in place.

## 4. DHCP: ISC to dnsmasq

**Why.** ISC DHCP is end-of-life upstream. dnsmasq is OPNsense's default for small networks, and
it hands hostnames to DNS. A disabled-but-configured dnsmasq had also been failing to bind every
time a link came up, which filled the log with errors.

**What.** Same address range, `authoritative`, reservations for the router-adjacent gear and the
UniFi server host, dnsmasq DNS on a side port (53053) for local names only, and Unbound forwarding
the local domain and reverse zones to it. Stopped ISC, started dnsmasq, verified renewals, *then*
removed the ISC plugin.

**Gotcha.** Moving a reservation between two NICs on the same PC: Windows declined the address on
the new NIC because the unplugged old NIC still held a stale copy. Disabling the old NIC fixed it.

## 5. DNS blocklists (Unbound)

**Why.** Blocking ads, trackers and malware at DNS covers every device, including TVs and speakers.

**What.** Unbound blocklist policy: HaGeZi PRO + HaGeZi Threat Intelligence + Fake + Pop-up
(~2 million domains). The DoH/VPN-bypass list was left off because a desktop VPN client needs it.

**Test.** 20 known ad/tracker domains before vs after, plus 15 must-work services. Went from 0/20
to 13/20 blocked with 15/15 working. The rest are allowed *on purpose* by HaGeZi PRO (Google and
Amazon ad-click domains break sponsored links if blocked). RAM +1 GB. No throughput impact.

**Gotcha.** Test a minute *after* reloading. The first test ran while 2M entries were still loading.

## 6. Smart queuing (FQ-CoDel), measured first

**Why.** Bufferbloat: lag spikes when a link is saturated.

**What.** Measured from the router itself (no Wi-Fi or VPN in the way): ping under full download
and full upload. Download added +4 ms (fine). Upload spiked to 121 ms with 2.5% loss. So I shaped
**upload only**: pipe at ~97% of the measured line rate, FQ-CoDel, ECN.

**Test.** Upload lag 23 → 13 ms average, 121 → 24 ms worst, 0% loss. Download untouched.

## 7. Visibility: per-device history

**What.**
- Unbound query reporting was already on, but its built-in database keeps **7 days**. Turned on
  per-query logging to syslog and raised syslog retention to **365 days** (about 6 GB a year of
  DNS logs).
- ntopng (+ redis) on the LAN, configured over its REST API and redis prefs: track hosts by MAC,
  silence one noisy false positive (TV talking to its vendor's cloud), keep every security check.
- NetFlow (Insight) on all inside networks.

**Gotcha.** Logging "local actions" doubled the DNS log volume for no extra information. Turned it off.

## 8. CrowdSec

**What.** Plugin defaults: agent, local API, firewall bouncer, block in/out against the community
blocklist (~15k IPv4 attackers). Turned on rule logging so every hit is visible.

**Test.** 81 IPs behind 30 everyday services checked against the table: 0 listed. A/B upload test
with rules off/on: no difference. CPU unchanged.

## 9. Device inventory and naming

**Why.** Random MACs and blank hostnames make audits impossible, and you need the inventory to
decide what goes on the IoT VLAN.

**What.** Merged DHCP leases, ARP/NDP (with OUI vendor), the old ISC lease file, UniFi's known
clients, and 7 days of DNS per client (a device hitting one camera vendor's domain 6,000 times is
a camera). Named everything consistently, gave fixed IPs, and pushed the same names into the router,
UniFi and ntopng.

**Gotchas.**
- One phone showed up as two devices: private MACs are per Wi-Fi network.
- Two identical cameras were labeled backwards. The camera app showing which network each was on
  settled it.
- DHCP fingerprints (`MSFT 5.0`, `android-dhcp-17`) plus "talks to the same servers as my own
  devices" explained most past unknown devices.

## 10. Suricata IDS, watch mode first

**What.** IDS (pcap, passive) on the LAN interface, Hyperscan matcher (CPU has AVX2), 23
threat-focused rulesets (malware, C2, exploits, phishing, abuse.ch, coinminers). No policy or info
rules. Daily rule updates, alert logs kept 52 weeks.

**Test.** About 1.7 Gbps through the router with it on: no throughput change, 0.004% capture drops,
one core at ~25%.

## 11. IoT and Guest VLANs

**What.**
- Router: VLAN 20/30 on the LAN NIC, interfaces assigned, DHCP ranges, reservations moved.
- Firewall per VLAN: allow DNS/NTP/ping to its own gateway; block the router's admin side; block
  DNS-over-TLS (853); block all private ranges; allow internet. A NAT redirect forces hard-coded DNS
  (8.8.8.8 and friends) back to the router, so blocklists and logs cover IoT too.
- mDNS repeater Main ↔ IoT so printing (AirPrint/IPP) and discovery still work.
- UniFi: VLAN-only networks; the existing IoT SSID moved to VLAN 20 (same name and password, so
  nothing re-paired); a new Guest SSID with client isolation.
- Switch: endpoint ports locked to the native VLAN (see gotcha).

**Test.** IoT devices came back on the new range by themselves. IoT → Main blocked (and logged),
Main → IoT allowed, printer found from Main via the relay, desktop speed unchanged.

**Gotchas.**
- UniFi switch ports pass *all* VLANs by default, and a Realtek NIC with "Priority & VLAN" enabled
  accepted VLAN 20 multicast on the desktop. That's one-way, but not clean isolation. Fix: set
  endpoint ports to native-only (`tagged_vlan_mgmt: block_all`).
- Some cameras don't re-DHCP when their SSID moves VLAN. A power cycle fixed it.
- Keep the things you cast to (streaming box, TV) on Main, or plan for an SSDP/mDNS relay.

## 12. Phone alerts (ntfy)

**What.** A small Python watcher on the router ([`scripts/router/netwatch.py`](../scripts/router/netwatch.py)),
scheduled every minute through OPNsense's own cron/configd:
- **new MAC** on any VLAN not in the known list or reservations
- **new Suricata alert**
- **CrowdSec outbound block** (one of *my* devices contacting a known attacker)
- **key service down** for 2 minutes, and recovered
- **weekly digest**: new devices, IDS, CrowdSec in/out, DNS totals and top blocked, top bandwidth users

**Test.** A simulated new device, then a stopped ntopng. Both alerts arrived.

## 13. Tailscale on the router

**What.** Plugin installed, joined with a one-time pre-authorized key created through the Tailscale
API. Advertises the Main subnet and offers an exit node; routes approved and key expiry disabled via
the API. Tailnet DNS points at the router, so the phone gets ad blocking anywhere. A WAN rule for
UDP 41641 allows direct connections.

**Gotchas.**
- `tailscale0` is a real interface. Assign it, or pf's default deny eats it.
- On FreeBSD, subnet and exit traffic is forwarded by tailscaled's userspace stack, so those packets
  leave *the router itself*. Interface rules and the extra NAT barely see them. Tailscale ACLs and
  "which subnets are advertised" are the real access control.

## 14. Logs off the router

**What.** A router-side helper streams one day's logs as `tar.gz`
([`export-day.sh`](../scripts/router/export-day.sh)). A Windows scheduled task pulls missed days plus
a config backup into cloud-synced storage nightly
([`Sync-OPNsenseLogs.ps1`](../scripts/windows/Sync-OPNsenseLogs.ps1)). About 3 GB a year compressed.

## 15. Final tuning pass

| Area | Change | Why |
|---|---|---|
| Wi-Fi | Kept 2.4 GHz ch 1/20 MHz, 5 GHz 80 MHz, 6 GHz 160 MHz | Neighbor survey (200+ SSIDs) showed these were already the best choices |
| IoT SSID | 802.11v BSS transition off | Single AP; cheap IoT radios handle it badly |
| UniFi devices | SSH password login off, key-only | The password had been exposed; the key works |
| Router NICs | Flow control off; RX/TX rings 2048 (boot tunable) | Missed packets under burst; pause frames add latency |
| Unbound | 128 MB msg / 256 MB rrset cache, serve-expired, prefetch-key | 64 GB of RAM; instant answers for revisited sites |
| Upstream DNS | Full recursion → DNS-over-TLS to a malware-filtering resolver | ISP can't read DNS. Picked the resolver with a nearby node, by measurement |
| Desktop NIC (Realtek 2.5G) | EEE, Green Ethernet, Power Saving, Gigabit Lite off; flow control off; buffers 4096/4096; no NIC power-down | Known sources of lag spikes and link drops |

**Test.** Desktop download 1.4–2.0 Gbps through the router with every feature on, lag 12–17 ms
average under load, 0% loss, router ~90% idle.

**Found along the way.** The WAN link dropped in *bursts* (dozens of flaps in minutes, twice in a
month) with zero CRC errors: modem-side restarts, not the router. Worth knowing before blaming the box.
