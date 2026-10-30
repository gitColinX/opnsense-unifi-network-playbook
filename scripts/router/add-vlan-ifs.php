<?php
// Assign VLAN 20 (IoT) and VLAN 30 (Guest) as opt1/opt2 with static IPv4, the same
// way Interfaces > Assignments + Interfaces > [OPTx] Save/Apply would. Touches nothing else.
require_once('config.inc');
require_once('interfaces.inc');
require_once('filter.inc');
require_once('system.inc');
require_once('util.inc');

global $config;
$new = [
    'opt1' => ['vlan0.20', 'IoT',   '10.0.20.1'],
    'opt2' => ['vlan0.30', 'Guest', '10.0.30.1'],
];
foreach ($new as $key => $v) {
    foreach ($config['interfaces'] as $k => $i) {
        if (($i['if'] ?? '') === $v[0]) { echo "{$v[0]} already assigned as $k, skipping\n"; continue 2; }
    }
    if (isset($config['interfaces'][$key])) { echo "$key already exists, skipping\n"; continue; }
    $config['interfaces'][$key] = [
        'if' => $v[0], 'descr' => $v[1], 'enable' => '1',
        'spoofmac' => '', 'ipaddr' => $v[2], 'subnet' => '24',
    ];
    echo "assigned {$v[0]} as $key ({$v[1]}) {$v[2]}/24\n";
}
write_config('Claude Code: add IoT (VLAN 20) and Guest (VLAN 30) interfaces');
foreach (array_keys($new) as $key) {
    interface_configure(false, $key, true);
}
system_routing_configure();
filter_configure_sync();
echo "done\n";
