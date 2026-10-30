#!/bin/sh
# Stream one day's OPNsense logs as tar.gz on stdout: all /var/log/*/*_YYYYMMDD.log plus the
# current Suricata alert log (small; not date-named). Used by the PC's nightly OneDrive copy.
d="$1"
case "$d" in [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]) ;; *) echo "usage: $0 YYYYMMDD" >&2; exit 2;; esac
cd /var/log || exit 1
{ find . -name "*_${d}.log"; [ -f suricata/eve.json ] && echo suricata/eve.json; } | tar czf - -T -
