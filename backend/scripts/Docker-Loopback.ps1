# Parse Docker inspect JSON, not Compose's human-readable `port` output.
# The integration contract requires exactly one IPv4 loopback binding.
function Get-DockerLoopbackUrl([string]$bindingJson) {
    try {
        $parsedBindings = ConvertFrom-Json -InputObject $bindingJson -ErrorAction Stop
        # PS 5.1 can return a JSON array as one pipeline object; enumerate explicitly.
        $bindings = @($parsedBindings)
    }
    catch { throw 'Invalid Docker port binding JSON (raw output withheld).' }
    if ($bindings.Count -eq 0 -or ($bindings.Count -eq 1 -and $null -eq $bindings[0])) {
        throw 'Docker Engine reports no published port. A requested HostConfig binding is not an active mapping; HTTP E2E cannot continue.'
    }
    if ($bindings.Count -ne 1) {
        throw 'Expected exactly one Docker port binding; refusing an absent or ambiguous mapping.'
    }
    $binding = $bindings[0]
    if ('HostIp' -notin $binding.PSObject.Properties.Name -or
        'HostPort' -notin $binding.PSObject.Properties.Name -or
        $binding.HostIp -cne '127.0.0.1') {
        throw 'Docker port is not bound exclusively to 127.0.0.1; refusing HTTP access.'
    }
    $portText = [string]$binding.HostPort
    $portNumber = 0
    if ($portText -notmatch '^[0-9]{1,5}$' -or
        -not [int]::TryParse($portText, [ref]$portNumber) -or
        $portNumber -lt 1 -or $portNumber -gt 65535) {
        throw 'Invalid Docker host port; refusing HTTP access.'
    }
    return 'http://127.0.0.1:' + $portNumber
}
