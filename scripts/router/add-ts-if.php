<?php
// Assign tailscale0 as opt3 "Tailscale" (no IP config; tailscaled manages the address)
// so the firewall can have rules for it. Same mechanism as Interfaces > Assignments.
require_once('config.inc');
require_once('interfaces.inc');
require_once('filter.inc');
require_once('util.inc');

global $config;
foreach ($config['interfaces'] as $k => $i) {
    if (($i['if'] ?? '') === 'tailscale0') { echo "tailscale0 already assigned as $k\n"; exit(0); }
}
$key = 'opt3';
while (isset($config['interfaces'][$key])) { $key = 'opt' . ((int)substr($key, 3) + 1); }
$config['interfaces'][$key] = ['if' => 'tailscale0', 'descr' => 'Tailscale', 'enable' => '1', 'spoofmac' => ''];
write_config('Claude Code: assign tailscale0 as Tailscale interface');
filter_configure_sync();
echo "assigned tailscale0 as $key\n";
