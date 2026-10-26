function Assert-TestGatewayConfig($config) {
    $services = @($config.services.PSObject.Properties.Name)
    $expected = @('sqli-lab-api','sqli-lab-db','sqli-lab-auth-db','sqli-test-gateway')
    if ($services.Count -ne 4 -or @($services | Where-Object { $_ -notin $expected }).Count) {
        throw 'Test gateway topology must contain exactly the four disposable services.'
    }
    if (@($config.networks.PSObject.Properties.Name).Count -ne 2 -or
        -not $config.networks.'sqli-lab-net'.internal -or
        ('internal' -in $config.networks.'sqli-test-edge'.PSObject.Properties.Name -and
         $config.networks.'sqli-test-edge'.internal)) { throw 'Invalid internal/edge network configuration.' }
    foreach ($network in $config.networks.PSObject.Properties.Value) {
        if ('external' -in $network.PSObject.Properties.Name -and $network.external) {
            throw 'Test networks must be private to the disposable Compose project.'
        }
    }
    foreach ($name in $expected) {
        $service = $config.services.$name
        if ('network_mode' -in $service.PSObject.Properties.Name -or
            'container_name' -in $service.PSObject.Properties.Name) { throw 'Shared container/network configuration is forbidden.' }
        $nets = @($service.networks.PSObject.Properties.Name)
        $ports = @()
        if ('ports' -in $service.PSObject.Properties.Name) { $ports = @($service.ports) }
        if ($name -eq 'sqli-test-gateway') {
            if ($nets.Count -ne 2 -or 'sqli-lab-net' -notin $nets -or 'sqli-test-edge' -notin $nets) {
                throw 'Gateway must join only the disposable internal and edge networks.'
            }
            if ($ports.Count -ne 1 -or $ports[0].host_ip -ne '127.0.0.1' -or
                [int]$ports[0].target -ne 8080 -or $ports[0].protocol -ne 'tcp') {
                throw 'Only the gateway may publish one IPv4 loopback TCP port.'
            }
            if ('published' -in $ports[0].PSObject.Properties.Name -and $ports[0].published -notin @('', '0', 0)) {
                throw 'Test gateway host port must be allocated randomly.'
            }
        } else {
            if ($nets.Count -ne 1 -or $nets[0] -ne 'sqli-lab-net' -or $ports.Count -ne 0) {
                throw 'Lab API and DBs must stay internal-only with no published ports.'
            }
        }
    }
}
