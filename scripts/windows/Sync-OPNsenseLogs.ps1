# Nightly copy of OPNsense logs + config into OneDrive (off-router backup).
# Runs from Task Scheduler as a regular (non-admin) user. Uses the SSH key/host "opnsense" in
# ~/.ssh/config and the DPAPI-encrypted API key in ~/.secrets/opnsense-api.xml.
#   Logs   -> OneDrive\Documents\OPNsense logs\YYYY\MM\opnsense-logs-YYYYMMDD.tar.gz
#   Config -> OneDrive\Documents\OPNsense backups\auto\config-YYYYMMDD.xml (kept 365 days)
# Catches up missed days (PC asleep/off), up to $MaxDays back. Router keeps logs 365 days.
param([int]$MaxDays = 30)

$ErrorActionPreference = 'Stop'
$logRoot = Join-Path $env:USERPROFILE 'OneDrive\Documents\OPNsense logs'
$cfgRoot = Join-Path $env:USERPROFILE 'OneDrive\Documents\OPNsense backups\auto'
New-Item -ItemType Directory -Force $logRoot, $cfgRoot | Out-Null
$stateFile = Join-Path $logRoot '.last-synced'
$runLog = Join-Path $logRoot 'sync.log'
function Write-RunLog($msg) { "$(Get-Date -Format s)  $msg" | Add-Content $runLog }

try {
    $yesterday = (Get-Date).Date.AddDays(-1)
    $day = if (Test-Path $stateFile) {
        [datetime]::ParseExact((Get-Content $stateFile -Raw).Trim(), 'yyyyMMdd', $null).AddDays(1)
    } else { $yesterday }
    if ($day -lt $yesterday.AddDays(-$MaxDays)) { $day = $yesterday.AddDays(-$MaxDays) }

    while ($day -le $yesterday) {
        $d = $day.ToString('yyyyMMdd')
        $out = Join-Path $logRoot ('{0}\{1}\opnsense-logs-{2}.tar.gz' -f $day.Year, $day.ToString('MM'), $d)
        New-Item -ItemType Directory -Force (Split-Path $out) | Out-Null
        # Start-Process redirection writes the raw bytes (PowerShell pipes would mangle binary)
        $p = Start-Process ssh -ArgumentList '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=15', 'opnsense', "/root/netwatch/export-day.sh $d" `
            -RedirectStandardOutput $out -RedirectStandardError "$out.err" -NoNewWindow -Wait -PassThru
        $size = (Get-Item $out).Length
        if ($p.ExitCode -ne 0 -or $size -lt 1000) { throw "export $d failed (exit $($p.ExitCode), $size bytes): $(Get-Content "$out.err" -Raw)" }
        Remove-Item "$out.err" -ErrorAction SilentlyContinue
        Write-RunLog ("logs {0}: {1:N1} MB" -f $d, ($size / 1MB))
        Set-Content $stateFile $d
        $day = $day.AddDays(1)
    }

    $c = Import-Clixml (Join-Path $env:USERPROFILE '.secrets\opnsense-api.xml')
    $cfg = Join-Path $cfgRoot ("config-{0}.xml" -f (Get-Date -Format yyyyMMdd))
    Invoke-WebRequest 'https://10.0.10.1/api/core/backup/download/this' -Credential $c -Authentication Basic -SkipCertificateCheck -OutFile $cfg
    if ((Get-Item $cfg).Length -lt 10000) { throw "config backup looks too small" }
    Write-RunLog ("config {0}: {1:N0} KB" -f (Split-Path $cfg -Leaf), ((Get-Item $cfg).Length / 1KB))

    Get-ChildItem $cfgRoot -Filter 'config-*.xml' | Where-Object LastWriteTime -lt (Get-Date).AddDays(-365) | Remove-Item
}
catch {
    Write-RunLog "ERROR: $($_.Exception.Message)"
    exit 1
}
