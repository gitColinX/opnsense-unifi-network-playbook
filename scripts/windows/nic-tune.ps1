# Desktop Realtek 2.5GbE tuning (run elevated). Turns off power-saving features that cause
# latency spikes/link drops, disables flow control (switch has it off too), drops VLAN tag
# handling (port is untagged now), raises ring buffers, stops Windows powering the NIC down.
param([string]$Log = "$env:TEMP\nic-tune.log")
$n = 'Ethernet'
"run $(Get-Date -Format s)" | Out-File $Log
$set = [ordered]@{
    '*EEE' = '0'; 'EnableGreenEthernet' = '0'; 'PowerSavingMode' = '0'; 'GigaLite' = '0'
    '*FlowControl' = '0'; '*PriorityVLANTag' = '1'; '*ReceiveBuffers' = '4096'; '*TransmitBuffers' = '4096'
}
foreach ($k in $set.Keys) {
    try { Set-NetAdapterAdvancedProperty -Name $n -RegistryKeyword $k -RegistryValue $set[$k] -NoRestart -ErrorAction Stop; "set $k=$($set[$k])" | Add-Content $Log }
    catch { "FAILED $k : $($_.Exception.Message)" | Add-Content $Log }
}
try { Disable-NetAdapterPowerManagement -Name $n -NoRestart -ErrorAction Stop; 'power management off' | Add-Content $Log }
catch { "power mgmt: $($_.Exception.Message)" | Add-Content $Log }
Restart-NetAdapter -Name $n
'restarted' | Add-Content $Log
