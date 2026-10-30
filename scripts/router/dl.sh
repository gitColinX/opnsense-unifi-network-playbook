#!/bin/sh
# Download-only test from the router: per-server throughput, WAN counter rate, CPU.
T=${T:-15}; tmp=/tmp/dl.$$; mkdir -p $tmp
URLS="${URLS:-https://hil-speed.hetzner.com/10GB.bin https://ash-speed.hetzner.com/10GB.bin}"
PER=${PER:-4}
n=0
for u in $URLS; do i=0; while [ $i -lt $PER ]; do
  curl -s -o /dev/null --max-time $T -w "%{size_download} $u\n" "$u" > $tmp/d$n & n=$((n+1)); i=$((i+1)); done; done
sleep 4
b1=$(netstat -I igc0 -b -n | awk 'NR==2{print $8}'); sleep 5; b2=$(netstat -I igc0 -b -n | awk 'NR==2{print $8}')
echo "WAN igc0 inbound rate (5 s window): $(echo "$b1 $b2" | awk '{printf "%.0f Mbps", ($2-$1)*8/5/1000000}')"
top -b -d 2 -s 1 | grep -E '^CPU' | tail -1
wait
cat $tmp/d* | awk -v T=$T '{s[$2]+=$1; t+=$1} END{for (u in s) printf "  %-45s %5.0f Mbps\n", u, s[u]*8/T/1000000; printf "  TOTAL %5.0f Mbps (curl-reported, includes ramp-up)\n", t*8/T/1000000}'
rm -rf $tmp
