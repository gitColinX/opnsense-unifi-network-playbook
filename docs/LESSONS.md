# Lessons and surprises

Short version of the things worth knowing before you do this yourself.

**Hardware and links**
- Check the *port*, not just the plan. The desktop sat on a 1 GbE port next to an unused 2.5GbE one.
- Realtek 2.5G NICs ship with EEE, "Green Ethernet", "Power Saving" and "Gigabit Lite" on. Turn
  them off on a desktop.
- Realtek "Priority & VLAN" accepts tagged frames, so a switch that passes all VLANs to every port
  leaks multicast into the desktop. Lock endpoint ports to their native VLAN.
- WAN flapping that comes in bursts with zero CRC errors is the modem restarting, not your router.

**UniFi**
- Legacy Network app and UniFi OS Server fight over the same ports. Stop one before starting the other.
- A device stuck "adopting" may just be asking DNS for `unifi`. A DNS host override fixes it.
- Moving an SSID to a new VLAN keeps the name and password, so devices follow on their own, except
  the ones that never re-DHCP. Power-cycle those.
- Private MACs are per SSID: one phone, two "devices".

**OPNsense**
- ZFS boot environments make a major upgrade nearly risk-free.
- `add_forward` vs `add_dot` in the Unbound API: one is plain, one is TLS. Read the generated config.
- Some plugins (microcode) can break a major-version boot. Read the release notes' migration section.
- Interface assignment has no API. OPNsense's own PHP functions over SSH do the same thing as the GUI.
- User cron jobs live in `/var/cron/tabs/nobody`.
- The Unbound reporting database keeps 7 days. Syslog query logging is how you get a year.
- ISC and dnsmasq both "enabled" means one silently fails every time a link comes up.

**Measuring**
- Test from the router itself to separate the line from Wi-Fi and VPN effects.
- Use several servers in parallel for multi-gig, and steady-state counters instead of averages.
- Shape only the direction that bloats.
- Benchmark DNS resolvers from your own connection. Anycast routing decides who's "nearby", and it
  surprised me.

**Working with an AI operator**
- Make it back up first, test after, and write down the result, every time.
- Keep secrets out of the conversation entirely; it can read env vars and DPAPI files.
- Ask for the honest number when a prediction misses. The Quad9 result changed the final choice.
