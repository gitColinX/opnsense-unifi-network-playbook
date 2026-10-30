# How Claude Code ran this

Claude Code (in the desktop app, PowerShell on Windows) acted as the operator. I approved each
phase, did every sign-in and password myself, and made the physical moves (power-cycling a camera,
moving a cable). Everything else went through APIs and SSH.

## API vs SSH: who did what

| Channel | Auth | Used for | Why this channel |
|---|---|---|---|
| **OPNsense REST API** | API key+secret (dedicated user), DPAPI-encrypted on the PC | Firmware/plugins, DHCP (dnsmasq), DNS (Unbound, blocklists, DoT), firewall rules + NAT, shaper, IDS, CrowdSec, cron, tunables, NetFlow, Tailscale plugin, config backups | It's what the GUI uses: validated, atomic, and every change can be read back |
| **OPNsense SSH** | root, ed25519 key, LAN only, no password | BIOS/NIC/CPU facts, logs, `pfctl` states and counters, `tcpdump`, speed and lag tests *from* the router, interface assignment through OPNsense's own PHP functions, `tailscale up`, ntopng prefs in redis, the custom watcher | Things no API exposes, and tests that need a vantage point outside Wi-Fi and the desktop's VPN |
| **UniFi Integration API** | `X-API-KEY` | Devices, clients, states | Clean, read-mostly inventory |
| **UniFi classic API** (same key) | `X-API-KEY` | Rename clients, create VLAN networks, map SSIDs, switch port overrides, settings | Where the configuration actually lives |
| **UniFi device SSH** | key-only | AP diagnostics: inform URL, DHCP renew, DNS lookups as a LAN client | A trustworthy client on the LAN for testing |
| **ntopng REST** | token | Host labels, alert review | Labels and checks without clicking |
| **Tailscale API** | 7-day access token | One-time join key, approve routes and exit node, disable key expiry, tailnet DNS | The whole admin-console part, scripted, and the token expires by itself |

## Secrets handling

- I created every key in the vendor's own UI. It went from the clipboard into a Windows *user*
  environment variable or a DPAPI file (`Export-Clixml`), then got wiped from the clipboard and the
  clipboard manager. **No key was ever pasted into the chat.**
- Claude didn't type passwords or complete sign-ins. Where a password was needed (Wi-Fi PSKs,
  ntopng's first login, Tailscale sign-in), I did it.
- One SSH password did end up visible in a screenshot. Fix: device SSH switched to **key-only**,
  so the exposed password stopped mattering.
- The ntfy channel name works like a capability URL. It lives on the router, root-only, not in notes.

## Working rules that made it safe

1. **Backup before every change.** A config download before each step, plus a ZFS boot environment
   before the major upgrade. Rollback was always one action away.
2. **One change, one test, one note.** Every step ended with a measurement, not "should be fine".
3. **Plan before disruptive work.** VLANs, DHCP swap, DNS changes: plan, then approval, then execution.
4. **Shared notes.** Facts and decisions went into a Markdown notes folder after every step, so a
   later session (or another AI tool) starts from the truth instead of re-discovering it.
5. **Report mistakes plainly.** They're listed below because they're the useful part.

## Mistakes caught along the way

| What happened | How it was caught | Fix |
|---|---|---|
| Added DoT resolvers through `add_forward`, which forces plain forwarding (port 853, no TLS); new-site DNS broke for ~2 minutes | Read the rendered `dot.conf`; no `forward-tls-upstream` | Use the `add_dot` endpoint |
| Predicted Quad9 would be faster; it was slower (nearest node 40 ms away via the ISP's routing) | Benchmarked 20 uncached lookups before and after | Measured alternatives, switched to the one with a local node |
| Two camera labels swapped | Camera app showed which SSID each used | Swapped names in all three systems |
| Weekly report double-counted bandwidth (router sees each flow on two interfaces) | Total looked impossible; checked raw NetFlow rows | Count each flow once, on inside interfaces |
| "Cron jobs vanished" false alarm | Looked in `/var/cron/tabs/root`; OPNsense keeps user jobs in `/var/cron/tabs/nobody` | No fix needed; noted for next time |
| A `grep` over a 200 MB JSON blocklist kept running in the background and burned a core | Spotted it in `ps` | Killed it; scan big files with Python, not regex grep |
| Reported "0 hits" on Tailscale firewall rules as a possible failure | My phone tests worked anyway | Learned that FreeBSD tailscaled forwards in userspace |

## Prompting style that worked

- State the outcome and the constraint ("full speed, nothing I use gets blocked, ask before
  disruptive changes"), not the clicks.
- Ask for **before/after numbers** on every change.
- Ask "what would break?" before each step. That's how the casting and printing problems were
  designed around before the VLANs went in.
