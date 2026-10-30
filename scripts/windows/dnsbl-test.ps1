# Ad/tracker vs. must-work domains, resolved through the router from the AP (a real LAN client).
param([string]$Label = 'test')
$ads = 'doubleclick.net','ad.doubleclick.net','googleadservices.com','pagead2.googlesyndication.com','adservice.google.com',
       'app-measurement.com','amazon-adsystem.com','device-metrics-us.amazon.com','adnxs.com','adsrvr.org','criteo.com',
       'taboola.com','outbrain.com','scorecardresearch.com','hotjar.com','analytics.tiktok.com','ads.yahoo.com',
       'samsungads.com','securepubads.g.doubleclick.net','static.ads-twitter.com'
$ok  = 'google.com','youtube.com','netflix.com','microsoft.com','teams.microsoft.com','amazon.com','spotify.com',
       'apple.com','chatgpt.com','claude.ai','github.com','wikipedia.org','dropbox.com','facebook.com','zoom.us'
$all = $ads + $ok
$cmd = ($all | ForEach-Object { "echo ==$_; nslookup $_ 10.0.10.1 2>&1 | sed -n '3,20p'" }) -join '; '
$out = ssh -o BatchMode=yes unifi-ap $cmd 2>&1
$res = @{}; $cur = $null
foreach ($l in $out) { if ($l -match '^==(.+)$') { $cur = $Matches[1]; $res[$cur] = @() } elseif ($cur) { $res[$cur] += $l } }
function St($d) { $t = $res[$d] -join ' '; if ($t -match 'Address: 0\.0\.0\.0|NXDOMAIN|can.t find') { 'BLOCKED' } elseif ($t -match 'Address: \S+|canonical name') { 'resolves' } else { 'no-answer' } }
$adRows = $ads | ForEach-Object { [pscustomobject]@{ group = 'ad/tracker'; domain = $_; status = St $_ } }
$okRows = $ok  | ForEach-Object { [pscustomobject]@{ group = 'must-work'; domain = $_; status = St $_ } }
"[$Label] ad/tracker blocked: $(@($adRows | Where-Object status -eq 'BLOCKED').Count)/$($ads.Count)   must-work resolving: $(@($okRows | Where-Object status -eq 'resolves').Count)/$($ok.Count)"
$adRows + $okRows | Format-Table -AutoSize
