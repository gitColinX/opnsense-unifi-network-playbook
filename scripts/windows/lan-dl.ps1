# Download test FROM THE DESKTOP through the router (so LAN-side Suricata sees it),
# while sampling router CPU over SSH. Prints desktop throughput + router CPU + suricata CPU.
param([int]$Seconds = 20, [int]$Streams = 12, [string]$Label = 'test')
$urls = 'https://hil-speed.hetzner.com/10GB.bin','https://ash-speed.hetzner.com/10GB.bin','https://proof.ovh.net/files/10Gb.dat'
$nic = Get-NetAdapter -Name 'Ethernet'
$jobs = 1..$Streams | ForEach-Object {
  $u = $urls[$_ % $urls.Count]
  Start-Process curl.exe -ArgumentList '-s','-o','NUL','--max-time',"$Seconds",$u -NoNewWindow -PassThru
}
Start-Sleep 5
$sw = [Diagnostics.Stopwatch]::StartNew()
$s1 = (Get-NetAdapterStatistics -Name 'Ethernet').ReceivedBytes
$cpu = 'top -b -d 2 -s 4 | grep -E "^CPU" | tail -1; ps -axo %cpu,comm | grep -E "suricata" | head -2' | ssh -o BatchMode=yes opnsense "tr -d '\r' | sh -s" 2>&1
$s2 = (Get-NetAdapterStatistics -Name 'Ethernet').ReceivedBytes
$elapsed = $sw.Elapsed.TotalSeconds
$jobs | Wait-Process -ErrorAction SilentlyContinue
"[$Label] desktop download (steady, ~8 s window): {0:N0} Mbps" -f (($s2 - $s1) * 8 / $elapsed / 1e6)
"[$Label] router: $($cpu -join ' | ')"
