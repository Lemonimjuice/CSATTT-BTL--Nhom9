# Static effective-Compose and negative security regressions; no Docker Engine needed.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Lab-TestGateway.ps1')
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$raw = & docker compose --project-name tv3-gateway-static --env-file (Join-Path $root '.env.sqli-lab.example') `
    -f (Join-Path $root 'docker-compose.sqli-lab.yml') -f (Join-Path $root 'docker-compose.sqli-lab.test.yml') `
    --profile sqli-lab config --format json 2>$null
if ($LASTEXITCODE -ne 0) { throw 'Test gateway Compose merge failed (output omitted).' }
$json = $raw -join "`n"
$config = $json | ConvertFrom-Json
Assert-TestGatewayConfig $config
$mutations = @(
    { param($c) $c.services.'sqli-lab-api' | Add-Member ports @([pscustomobject]@{host_ip='127.0.0.1';target=8080;protocol='tcp'}) -Force },
    { param($c) $c.services.'sqli-lab-db'.networks | Add-Member 'sqli-test-edge' ([pscustomobject]@{}) },
    { param($c) $c.services.'sqli-lab-auth-db'.networks | Add-Member 'sqli-test-edge' ([pscustomobject]@{}) },
    { param($c) $c.services.'sqli-test-gateway'.ports[0].host_ip = '0.0.0.0' },
    { param($c) $c.services.'sqli-test-gateway'.ports[0].host_ip = '::' },
    { param($c) $c.services.'sqli-test-gateway'.networks | Add-Member 'business-network' ([pscustomobject]@{}) },
    { param($c) $c.networks.'sqli-lab-net'.internal = $false },
    { param($c) $c.networks.'sqli-test-edge' | Add-Member external $true -Force },
    { param($c) $c.services.'sqli-test-gateway'.ports[0] | Add-Member published '8081' -Force }
)
foreach ($mutation in $mutations) {
    $copy = $json | ConvertFrom-Json
    & $mutation $copy
    $rejected = $false
    try { Assert-TestGatewayConfig $copy } catch { $rejected = $true }
    if (-not $rejected) { throw 'Unsafe gateway topology was accepted.' }
}
Write-Host 'PASS: effective test override removes API ports, isolates API/DBs, publishes only loopback gateway; 9 unsafe-topology regressions rejected.'
