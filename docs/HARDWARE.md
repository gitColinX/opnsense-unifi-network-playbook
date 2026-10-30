# The hardware

| Role | Device | Notes |
|---|---|---|
| Router/firewall | Lenovo ThinkCentre M920q Tiny (used), Intel Core i9-9900T (8C/16T, 35 W), 64 GB DDR4 SO-DIMM, 1 TB NVMe, two Intel I226-V 2.5GbE ports (WAN + LAN), onboard I219-LM 1 GbE spare | OPNsense on ZFS |
| Wi-Fi | UniFi U7 Pro XG (Wi-Fi 7, 2.5GbE uplink) | One AP, 2.4/5/6 GHz |
| Switch | UniFi USW Flex 2.5G 5 | Router uplink, AP, desktop, dock |
| Controller | UniFi OS Server on the desktop (Windows, WSL2/podman) | No cloud key needed |
| Internet | ~2 Gbps down / ~300 Mbps up cable | Modem in bridge mode |

## Why a used mini PC is enough

With **every** feature on (IDS on the LAN, CrowdSec, 2M-entry DNS blocklist, upload shaping,
NetFlow, ntopng, Tailscale), the router moved ~2 Gbps at **~90% idle CPU** and used ~4 GB of its
64 GB RAM. Enterprise next-gen firewalls with comparable throughput and IPS cost several times
more, and usually add yearly subscriptions. What they add on top is vendor threat intelligence, TLS
inspection, HA pairs and support, and none of those is needed for a home.

## Where the headroom goes next

- Suricata in **IPS** mode (inline): measure the throughput cost first.
- A full SIEM (Wazuh/Graylog) needs a separate box with 8+ GB of RAM, or running OPNsense as a VM
  under Proxmox on this same machine.
- The BIOS still had an update pending at the time of writing; it ships newer CPU microcode.
