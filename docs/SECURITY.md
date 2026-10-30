# Security model

## Layers

| Layer | What it stops |
|---|---|
| Default-deny WAN, only Tailscale UDP 41641 open | Unsolicited inbound traffic |
| CrowdSec (in + out) | Known attackers reaching you, and your devices reaching them |
| Suricata IDS (watch mode) | Known malware, C2 and exploit traffic patterns (alerts to phone) |
| DNS blocklists + malware-filtering upstream | Ads, trackers, phishing and malware domains |
| DNS-over-TLS upstream | ISP reading or tampering with DNS |
| DNSSEC validation | Forged DNS answers |
| Forced DNS on IoT/Guest (+ blocked port 853) | Gadgets bypassing the filter with hard-coded resolvers |
| IoT VLAN | A compromised camera or plug reaching PCs and phones |
| Guest VLAN + client isolation | Visitors seeing your devices, or each other |
| Endpoint switch ports native-only | VLAN traffic leaking to desktops |
| Key-only SSH, LAN-only router SSH | Password guessing; remote admin exposure |
| New-device alerts | Someone using a leaked Wi-Fi password |

## Decisions and trade-offs

- **IDS before IPS.** Watch for a week, review false positives, *then* decide on blocking mode.
  Inline IPS costs throughput, so measure it first.
- **One camera stays on Main.** It's a flaky device that's painful to re-pair. It's a known,
  documented exception rather than an hour of frustration.
- **Casting targets on Main.** Cross-VLAN casting works with relays, but not reliably. The streaming
  box and TV live on Main.
- **No TLS interception.** Full-URL visibility would mean installing a CA on every device, and pinned
  apps would break. Domain-level history (DNS + SNI) is the practical ceiling for a home.
- **Upstream DNS resolver.** Encryption hides queries from the ISP but trusts the resolver. Pick one
  with a clear no-logging policy, and measure latency from *your* connection.
- **Exit node off by default.** Ad blocking follows the phone anyway (tailnet DNS); the exit node is
  for untrusted Wi-Fi.

## Secrets

- API keys: per-user environment variables or DPAPI files on one PC. Short-lived where the vendor
  allows it (7-day Tailscale token).
- No secrets in notes, repos or chat. The notification channel name is treated as a secret.
- Config backups contain password hashes and keys. They go to private storage, never a repo.

## What to check monthly

1. The weekly report: new devices, IDS hits, outbound CrowdSec blocks (should be 0).
2. Firmware: OPNsense, AP, switch, UniFi OS.
3. Blocklist false positives (anything someone says "stopped working").
4. WAN link-flap bursts in the system log (a modem or ISP problem shows up there first).
