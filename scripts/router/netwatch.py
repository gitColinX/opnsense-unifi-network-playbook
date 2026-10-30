#!/usr/local/bin/python3
"""netwatch: push alerts (ntfy) for
  1) never-seen devices on Main / IoT / Guest (ARP + dnsmasq leases vs. known list),
  2) new Suricata alerts (eve.json),
  3) CrowdSec OUTBOUND blocks (a LAN device contacting a known attacker IP).
Runs from cron via configd ("netwatch run"). State in /root/netwatch/.
  4) key services stopping/recovering (run), and a weekly summary (digest).
Usage: netwatch.py [run|seed|test|digest|approve <mac> [comment]]
"""
import csv, json, os, re, subprocess, sys, time, urllib.request

BASE = '/root/netwatch'
KNOWN = f'{BASE}/known_macs.txt'
STATE = f'{BASE}/state.json'
TOPIC = open(f'{BASE}/topic').read().strip()
NETS = {'igc1': 'Main', 'vlan0.20': 'IoT', 'vlan0.30': 'Guest'}
EVE = '/var/log/suricata/eve.json'
FILTER = '/var/log/filter/latest.log'
MAX_PER_RUN = 5


def sh(cmd):
    return subprocess.run(cmd, shell=True, capture_output=True, text=True).stdout


def send(title, msg, prio='high', tags='warning'):
    req = urllib.request.Request(f'https://ntfy.sh/{TOPIC}', data=msg.encode(), method='POST',
                                 headers={'Title': title, 'Priority': prio, 'Tags': tags})
    urllib.request.urlopen(req, timeout=15).read()
    sh(f"logger -t netwatch {json.dumps(title + ': ' + msg.replace(chr(10), ' | '))}")


def load_state():
    try:
        return json.load(open(STATE))
    except Exception:
        return {'alerted': {}, 'eve': None, 'filter': None}


def known_macs():
    macs = set()
    if os.path.exists(KNOWN):
        for line in open(KNOWN):
            m = line.split('#')[0].strip().lower()
            if m:
                macs.add(m)
    for line in open('/usr/local/etc/dnsmasq.conf'):
        if line.startswith('dhcp-host='):
            macs.update(re.findall(r'(?:[0-9a-f]{2}:){5}[0-9a-f]{2}', line.lower()))
    return macs


def present():
    """mac -> {ip, net, name} from ARP (authoritative for 'is here now') plus lease hostnames."""
    devs = {}
    for line in sh('arp -an').splitlines():
        m = re.match(r'\? \(([\d.]+)\) at ((?:[0-9a-f]{2}:){5}[0-9a-f]{2}) on (\S+)', line)
        if m and m.group(3) in NETS and 'permanent' not in line:
            devs[m.group(2)] = {'ip': m.group(1), 'net': NETS[m.group(3)], 'name': ''}
    names = {}
    if os.path.exists('/var/db/dnsmasq.leases'):
        for line in open('/var/db/dnsmasq.leases'):
            p = line.split()
            if len(p) >= 4:
                names[p[1].lower()] = '' if p[3] == '*' else p[3]
    for mac, d in devs.items():
        d['name'] = names.get(mac, '')
    return devs


_oui = None
def vendor(mac):
    global _oui
    if int(mac[:2], 16) & 2:
        return 'randomized (private) address - usually a phone/tablet/laptop'
    if _oui is None:
        _oui = {r[1].upper(): r[2] for r in csv.reader(open('/usr/local/opnsense/contrib/ieee/oui.csv', errors='ignore')) if len(r) > 2}
    return _oui.get(mac.replace(':', '')[:6].upper(), 'unknown maker')


def tail(path, key, state):
    """New lines since last run; first run starts at end (no backlog). Handles rotation."""
    try:
        real = os.path.realpath(path); st = os.stat(real)
    except FileNotFoundError:
        return []
    pos = state.get(key)
    if not pos or pos.get('ino') != st.st_ino or pos.get('off', 0) > st.st_size:
        state[key] = {'ino': st.st_ino, 'off': st.st_size if not pos else 0}
        if not pos:
            return []
    with open(real, errors='ignore') as f:
        f.seek(state[key]['off'])
        lines = f.readlines()
        state[key]['off'] = f.tell()
    return lines


def check_devices(state):
    known = known_macs()
    new = [(mac, d) for mac, d in present().items() if mac not in known and mac not in state['alerted']]
    for mac, d in new[:MAX_PER_RUN]:
        send(f"New device on {d['net']} network",
             f"IP {d['ip']}\nName: {d['name'] or '(none sent)'}\nMAC {mac}\nMaker: {vendor(mac)}\n"
             f"Seen {time.strftime('%Y-%m-%d %H:%M')}. Yours? Tell Claude to approve it; if not, block it.",
             tags='rotating_light')
        state['alerted'][mac] = int(time.time())


def check_suricata(state):
    hits = {}
    for line in tail(EVE, 'eve', state):
        try:
            e = json.loads(line)
        except ValueError:
            continue
        if e.get('event_type') == 'alert':
            a = e.get('alert', {})
            k = (a.get('signature', '?'), e.get('src_ip'), e.get('dest_ip'))
            hits[k] = hits.get(k, 0) + 1
    for (sig, src, dst), n in list(hits.items())[:MAX_PER_RUN]:
        send('Suricata alert', f"{sig}\n{src} -> {dst} ({n}x)", tags='shield')


def check_crowdsec_out(state):
    label = re.search(r'block drop out log quick inet from any to <crowdsec_blocklists> label "([0-9a-f]+)"', sh('pfctl -sr'))
    lines = tail(FILTER, 'filter', state)
    if not label:
        return
    hits = {}
    for line in lines:
        if label.group(1) not in line:
            continue
        f = line.split('] ')[-1].split(',')
        if len(f) > 21:
            k = (f[18], f[19], f[16], f[21])
            hits[k] = hits.get(k, 0) + 1
    for (src, dst, proto, port), n in list(hits.items())[:MAX_PER_RUN]:
        send('CrowdSec blocked an OUTBOUND connection',
             f"Device {src} tried to reach known-attacker IP {dst} ({proto}/{port}, {n}x).\n"
             f"Could be malware calling home - or a false positive. Ask Claude to check.", tags='no_entry')


SERVICES = {'Suricata (IDS)': 'suricata', 'CrowdSec': 'crowdsec', 'DNS (Unbound)': 'unbound',
            'DHCP (dnsmasq)': 'dnsmasq', 'Tailscale': 'tailscaled', 'ntopng': 'ntopng'}


def check_health(state):
    """Alert once when a key service stops, and once when it recovers.
    Needs 2 consecutive failed checks (2 min) so restarts during config changes don't alert."""
    down = state.setdefault('down', {})
    for label, proc in SERVICES.items():
        running = subprocess.run(['pgrep', '-x', proc], capture_output=True).returncode == 0
        if not running:
            down[label] = down.get(label, 0) + 1
            if down[label] == 2:
                send(f'{label} is DOWN', f"{label} has not been running for 2 minutes on the router.\nAsk Claude to check it.",
                     tags='red_circle')
        else:
            if down.get(label, 0) >= 2:
                send(f'{label} recovered', f'{label} is running again.', prio='default', tags='green_circle')
            down.pop(label, None)


def names_by_ip():
    names = {}
    for line in open('/usr/local/etc/dnsmasq.conf'):
        if line.startswith('dhcp-host='):
            parts = line.strip().split('=', 1)[1].split(',')
            ips = [p for p in parts if re.match(r'^\d+\.\d+\.\d+\.\d+$', p)]
            if ips and not re.match(r'^[0-9a-f:]{17}$', parts[-1]):
                names[ips[0]] = parts[-1]
    return names


def digest(state):
    """Weekly summary (Sunday). Each section is independent so one failure doesn't kill the report."""
    since = time.time() - 7 * 86400
    days = [time.strftime('%Y%m%d', time.localtime(time.time() - d * 86400)) for d in range(7)]
    names = names_by_ip()
    lines = []
    try:
        new = [m for m, t in state.get('alerted', {}).items() if t >= since]
        lines.append(f"New devices: {len(new)}" + (f" ({', '.join(new)})" if new else ' - none'))
    except Exception as ex:
        lines.append(f'New devices: error {ex}')
    try:
        sigs = {}
        for path in [EVE] + [f'{EVE}.{i}' for i in range(1, 3)]:
            if os.path.exists(path):
                for l in open(path, errors='ignore'):
                    if '"event_type":"alert"' in l:
                        e = json.loads(l)
                        ts = time.mktime(time.strptime(e['timestamp'][:19], '%Y-%m-%dT%H:%M:%S'))
                        if ts >= since:
                            s = e['alert']['signature']; sigs[s] = sigs.get(s, 0) + 1
        top = sorted(sigs.items(), key=lambda x: -x[1])[:3]
        lines.append(f"Suricata alerts: {sum(sigs.values())}" + (''.join(f"\n  - {s} ({n}x)" for s, n in top) if top else ' - clean'))
    except Exception as ex:
        lines.append(f'Suricata: error {ex}')
    try:
        rules = sh('pfctl -sr')
        lin = re.search(r'block drop in log quick inet from <crowdsec_blocklists> to any label "([0-9a-f]+)"', rules)
        lout = re.search(r'block drop out log quick inet from any to <crowdsec_blocklists> label "([0-9a-f]+)"', rules)
        files = ' '.join(f'/var/log/filter/filter_{d}.log' for d in days if os.path.exists(f'/var/log/filter/filter_{d}.log'))
        cin = sh(f"cat {files} | grep -c {lin.group(1)}").strip() if lin and files else '?'
        cout = sh(f"cat {files} | grep -c {lout.group(1)}").strip() if lout and files else '?'
        lines.append(f"CrowdSec: {cin} attacker connections blocked inbound, {cout} outbound from your devices"
                     + (' - investigate!' if cout not in ('0', '?') else ''))
    except Exception as ex:
        lines.append(f'CrowdSec: error {ex}')
    try:
        import duckdb, shutil
        shutil.copy('/var/unbound/data/unbound.duckdb', '/tmp/nw-ub.duckdb')
        con = duckdb.connect('/tmp/nw-ub.duckdb', read_only=True)
        t0 = int(since)  # 'time' is stored as epoch seconds (INTEGER)
        # action is an enum code: 0 = pass, anything else = blocked/dropped
        tot, blk = con.execute("select count(*), count(*) filter (where action <> 0) from query where time >= ?", [t0]).fetchone()
        top = con.execute("select domain, count(*) n from query where action <> 0 and time >= ? group by domain order by n desc limit 5", [t0]).fetchall()
        con.close(); os.remove('/tmp/nw-ub.duckdb')
        lines.append(f"DNS: {tot:,} lookups, {blk:,} blocked ({(blk / tot * 100 if tot else 0):.1f}%)"
                     + ''.join(f"\n  - {d.rstrip('.')} ({n})" for d, n in top))
    except Exception as ex:
        lines.append(f'DNS: error {ex}')
    try:
        import sqlite3
        db = sqlite3.connect('file:/var/netflow/src_addr_details_086400.sqlite?mode=ro', uri=True)
        start = time.strftime('%Y-%m-%d', time.localtime(since))
        # count each flow once, on the inside interface only (WAN sees the same bytes again);
        # 'in' on igc1 = the device uploading, 'out' = downloading, so the sum is its total
        rows = db.execute("select ip, sum(o) from ("
                          " select case when src_addr like '10.0.%' then src_addr else dst_addr end ip, octets o"
                          " from timeserie where mtime >= ? and mtime <= datetime('now') and if in ('igc1','vlan0.20','vlan0.30'))"
                          " where ip like '10.0.%' and ip not in ('10.0.10.1','10.0.20.1','10.0.30.1')"
                          " group by ip order by 2 desc limit 5", (start,)).fetchall()
        lines.append('Top bandwidth users:' + ''.join(f"\n  - {names.get(ip, ip)}: {o / 1e9:.1f} GB" for ip, o in rows))
    except Exception as ex:
        lines.append(f'Traffic: error {ex}')
    down = [k for k, v in state.get('down', {}).items() if v >= 2]
    lines.append('Services: ' + ('DOWN now: ' + ', '.join(down) if down else 'all running'))
    send('Weekly network report', '\n'.join(lines), prio='default', tags='bar_chart')


def main():
    os.makedirs(BASE, exist_ok=True)
    cmd = sys.argv[1] if len(sys.argv) > 1 else 'run'
    state = load_state()
    if cmd == 'seed':
        with open(KNOWN, 'a') as f:
            for mac, d in present().items():
                f.write(f"{mac}  # seeded {time.strftime('%Y-%m-%d')} {d['net']} {d['ip']} {d['name']}\n")
        tail(EVE, 'eve', state); tail(FILTER, 'filter', state)
    elif cmd == 'approve':
        mac = sys.argv[2].lower()
        with open(KNOWN, 'a') as f:
            f.write(f"{mac}  # approved {time.strftime('%Y-%m-%d')} {' '.join(sys.argv[3:])}\n")
        state['alerted'].pop(mac, None)
    elif cmd == 'test':
        send('Netwatch test', 'If you can read this, router alerts reach your phone.', prio='default', tags='white_check_mark')
    elif cmd == 'digest':
        digest(state)
    else:
        for fn in (check_devices, check_suricata, check_crowdsec_out, check_health):
            try:
                fn(state)
            except Exception as ex:
                sh(f"logger -t netwatch {json.dumps('error in ' + fn.__name__ + ': ' + str(ex))}")
    json.dump(state, open(STATE, 'w'))


if __name__ == '__main__':
    main()
