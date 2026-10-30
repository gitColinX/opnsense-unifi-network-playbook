#!/bin/sh
# Uncached DNS lookup timing on the router. Flushes these names from Unbound's cache first,
# so every query is a real "new site" lookup (recursion or forwarder).
UC="unbound-control -c /var/unbound/unbound.conf"
DOMAINS="wikipedia.org bbc.co.uk nytimes.com lemonde.fr spiegel.de asahi.com abc.net.au cbc.ca
stackoverflow.com archlinux.org kernel.org debian.org python.org rust-lang.org nasa.gov noaa.gov
weather.gov usps.com nps.gov si.edu"
total=0; n=0; worst=0
for d in $DOMAINS; do
  $UC flush "$d" >/dev/null 2>&1; $UC flush_type "$d" A >/dev/null 2>&1; $UC flush_infra all >/dev/null 2>&1
  t=$(drill "$d" @127.0.0.1 | awk '/Query time/{print $4}')
  [ -z "$t" ] && t=0
  total=$((total + t)); n=$((n + 1)); [ "$t" -gt "$worst" ] && worst=$t
  printf "%-20s %5s ms\n" "$d" "$t"
done
echo "AVERAGE: $((total / n)) ms   WORST: ${worst} ms   (${n} uncached lookups)"
