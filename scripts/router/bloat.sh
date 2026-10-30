#!/bin/sh
# Bufferbloat test run ON the router: ping latency idle, under download, under upload.
# Uses Cloudflare's speed test endpoints; N parallel streams for T seconds.
N=${N:-8}; T=${T:-15}; P=1.1.1.1
tmp=/tmp/bloat.$$; mkdir -p $tmp

pingsum() { ping -c $1 -i 0.25 $P 2>/dev/null | awk -F'[/ =]+' '/round-trip/{printf "min %.1f / avg %.1f / max %.1f ms", $6, $7, $8} /packet loss/{for(i=1;i<=NF;i++) if($i ~ /%/) loss=$i} END{printf "  loss %s\n", loss}'; }

echo "IDLE:     $(pingsum 40)"

i=0; while [ $i -lt $N ]; do
  if [ $((i % 2)) -eq 0 ]; then u=https://hil-speed.hetzner.com/10GB.bin; else u=https://ash-speed.hetzner.com/10GB.bin; fi
  curl -s -o /dev/null --max-time $T -w '%{size_download}\n' $u > $tmp/d$i &
  i=$((i+1)); done
sleep 2; echo "DOWNLOAD: $(pingsum 40)"; wait
bytes=$(cat $tmp/d* | awk '{s+=$1} END{print s}')
echo "  download throughput: $(echo "$bytes $T" | awk '{printf "%.0f Mbps", $1*8/$2/1000000}')"

i=0; while [ $i -lt $N ]; do
  head -c 400000000 /dev/zero | curl -s -o /dev/null --max-time $T -w '%{size_upload}\n' --data-binary @- 'https://speed.cloudflare.com/__up' > $tmp/u$i &
  i=$((i+1)); done
sleep 2; echo "UPLOAD:   $(pingsum 40)"; wait
bytes=$(cat $tmp/u* | awk '{s+=$1} END{print s}')
echo "  upload throughput: $(echo "$bytes $T" | awk '{printf "%.0f Mbps", $1*8/$2/1000000}')"
rm -rf $tmp
