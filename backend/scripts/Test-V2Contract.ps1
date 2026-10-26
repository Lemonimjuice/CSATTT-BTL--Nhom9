# Compose interpolation/schema checks only. Does not connect to Docker Engine.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$raw = & docker compose --project-name tv3-static-contract --env-file (Join-Path $root '.env.sqli-lab.example') `
    -f (Join-Path $root 'docker-compose.sqli-lab.yml') --profile sqli-lab config --format json 2>$null
if ($LASTEXITCODE -ne 0) { throw 'Lab Compose schema/interpolation failed (output omitted).' }
$config = ($raw -join "`n") | ConvertFrom-Json
$api = $config.services.'sqli-lab-api'
if (@($config.services.PSObject.Properties).Count -ne 3) { throw 'Expected exactly three lab services.' }
if (@($api.networks.PSObject.Properties.Name).Count -ne 1 -or
    'sqli-lab-net' -notin $api.networks.PSObject.Properties.Name -or
    -not $config.networks.'sqli-lab-net'.internal) { throw 'Lab API network isolation failed.' }
foreach ($name in @('external','network_mode','env_file')) {
    if ($api.PSObject.Properties.Name -contains $name) { throw 'Unexpected external API configuration.' }
}
foreach ($pair in @(@('DB_HOST','sqli-lab-auth-db'),@('DB_NAME','lab_identity'),
                    @('DB_USERNAME','lab_identity_app'),@('SPRING_PROFILES_ACTIVE','integration,sqli-lab'),
                    @('SQLI_DEMO_ENABLED','true'))) {
    if ($api.environment.($pair[0]) -ne $pair[1]) { throw 'Disposable datasource/profile contract failed.' }
}
if ($api.environment.JWT_SECRET -ne 'REPLACE_WITH_SEPARATE_BASE64_32_RANDOM_BYTES') {
    # A host override might be legitimate, but a deterministic static check must not use real keys.
    throw 'Run static contract check without SQLI_LAB_JWT_SECRET override; no value was printed.'
}
foreach ($db in @('sqli-lab-auth-db','sqli-lab-db')) {
    $service = $config.services.$db
    if ($service.PSObject.Properties.Name -contains 'ports') { throw 'A lab DB publishes a port.' }
    if ('/var/lib/postgresql/data' -notin $service.tmpfs) { throw 'Lab DB must use disposable tmpfs.' }
    if (($service.healthcheck.test -join ' ') -notmatch 'pg_isready -h 127\.0\.0\.1') {
        throw 'DB health can pass before init completes.'
    }
}
if ($api.ports[0].host_ip -ne '127.0.0.1' -or [int]$api.ports[0].target -ne 8080) { throw 'Lab must bind loopback.' }
if (@($api.depends_on.PSObject.Properties.Name).Count -ne 2 -or
    'sqli-lab-auth-db' -notin $api.depends_on.PSObject.Properties.Name) { throw 'Unexpected service dependency.' }
$identity = $config.services.'sqli-lab-auth-db'
if (@($identity.volumes).Count -ne 2 -or @($identity.volumes | Where-Object { -not $_.read_only }).Count) {
    throw 'Identity DB requires the two read-only TV3 init scripts.'
}
Write-Host 'PASS: Compose schema and effective lab config: independent identities/JWT, one internal network, loopback API, tmpfs DBs, no business service dependency.'
