# Run manually from Windows PowerShell 5.1+ with Docker Desktop available.
# Only localhost HTTP ports for disposable backends are published. PostgreSQL
# stays inside a dedicated network and uses tmpfs rather than a Docker volume.
param([string]$LabBaseUrl)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Http-Response.ps1')
. (Join-Path $PSScriptRoot 'Docker-Loopback.ps1')

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$sqlRoot = (Resolve-Path (Join-Path $projectRoot '../database/init')).Path
$schemaFile = Join-Path $sqlRoot '01-schema.sql'
$grantsFile = Join-Path $sqlRoot '02-least-privilege.sql'
$profileFile = Join-Path $projectRoot 'src/main/resources/application-integration.yml'
foreach ($file in @($schemaFile, $grantsFile, $profileFile, (Join-Path $projectRoot 'Dockerfile'))) {
    if (-not (Test-Path -LiteralPath $file)) { throw "Required project file is missing: $file" }
}
if ((Get-Content -LiteralPath $profileFile -Raw) -notmatch '(?m)^\s+ddl-auto:\s*validate\s*$') {
    throw 'Integration profile must declare ddl-auto: validate.'
}

$runId = [guid]::NewGuid().ToString('N')
$suffix = $runId.Substring(0, 12)
$networkName = 'btlattt-2node-net-' + $suffix
$dbContainer = 'btlattt-2node-db-' + $suffix
$node1 = 'btlattt-2node-api1-' + $suffix
$node2 = 'btlattt-2node-api2-' + $suffix
$imageTag = 'btlattt-two-node-check:' + $suffix
$appRole = 'nodecheck_' + $suffix
$marker = 'btlattt_two_node_check'
$logDir = Join-Path $projectRoot 'logs'
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$logFile = Join-Path $logDir ('two-node-check-' + $runId + '.log')

function Write-Result([string]$message) {
    $line = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ' + $message
    Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8
    Write-Host $line
}

function Invoke-Docker([string[]]$dockerArgs, [string]$step) {
    # Never write raw Docker/psql output: failed SQL may echo expanded values.
    $output = & docker @dockerArgs 2>&1
    $code = $LASTEXITCODE
    if ($code -ne 0) {
        $safe = $output | ForEach-Object { [string]$_ } | Where-Object {
            $_ -match '(?i)(ERROR:|FATAL:|failed to solve|BUILD FAILURE|Failed to execute goal|Caused by:|permission denied|not found|unable to|connection refused)' -and
            $_ -notmatch '(?i)(password|secret|token|credential|authorization|jdbc:|bearer)'
        } | Select-Object -Last 6
        foreach ($line in $safe) {
            if ($line.Length -gt 500) { $line = $line.Substring(0, 500) }
            Write-Result ('Docker diagnostic: ' + $line)
        }
        throw "$step failed (Docker exit code $code)."
    }
    return (($output | ForEach-Object { [string]$_ }) -join "`n").Trim()
}

function New-RandomValue([int]$byteCount, [switch]$base64) {
    $bytes = New-Object byte[] $byteCount
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    if ($base64) { return [Convert]::ToBase64String($bytes) }
    return [BitConverter]::ToString($bytes).Replace('-', '')
}

function Confirm-NameFree([string[]]$dockerArgs, [string]$name) {
    if (Invoke-Docker $dockerArgs "Checking test name $name") {
        throw "Test resource name already exists: $name"
    }
}

function Get-LocalBaseUrl([string]$container) {
    $bindingJson = Invoke-Docker @('inspect', '--format', '{{json (index .NetworkSettings.Ports "8080/tcp")}}', $container) "Reading Engine port binding for $container"
    return Get-DockerLoopbackUrl $bindingJson
}

function Call-Api([string]$case, [string]$baseUrl, [string]$method,
                  [string]$path, $body, [string]$jwt, [int]$expected) {
    $parameters = @{
        Uri = $baseUrl + $path
        Method = $method
        UseBasicParsing = $true
        TimeoutSec = 15
    }
    if ($null -ne $body) {
        $parameters.ContentType = 'application/json'
        $parameters.Body = ConvertTo-Json -InputObject $body -Compress
    }
    if ($jwt) { $parameters.Headers = @{ Authorization = 'Bearer ' + $jwt } }
    $status = $null
    $content = $null
    try {
        $response = Invoke-WebRequest @parameters
        $status = [int]$response.StatusCode
        $content = ConvertTo-HttpText $response.Content
    }
    catch {
        $httpResponse = $_.Exception.Response
        if ($null -eq $httpResponse) {
            throw "$case failed before receiving HTTP (exception type: $($_.Exception.GetType().Name))."
        }
        $status = [int]$httpResponse.StatusCode
        # Intentionally discard error response bodies; they may contain user data.
    }
    if ($status -ne $expected) { throw "$case expected HTTP $expected but received HTTP $status." }
    Write-Result "PASS: $case HTTP $status."
    return [pscustomobject]@{ Status = $status; Content = $content }
}

function Parse-ApiJson([string]$case, $content) {
    try { return ((ConvertTo-HttpText $content) | ConvertFrom-Json) }
    catch { throw "$case returned malformed JSON (body omitted)." }
}

function Wait-Healthy([string]$baseUrl, [string]$nodeLabel) {
    $lastStatus = 'no HTTP response'
    for ($attempt = 1; $attempt -le 120; $attempt++) {
        try {
            $response = Invoke-WebRequest -Uri ($baseUrl + '/actuator/health') -UseBasicParsing -TimeoutSec 3
            $lastStatus = 'HTTP ' + [int]$response.StatusCode + '; content type ' + $response.Content.GetType().Name
            if ([int]$response.StatusCode -eq 200 -and
                ((ConvertTo-HttpText $response.Content) -match '"status"\s*:\s*"UP"')) {
                Write-Result "PASS: $nodeLabel health UP."
                return
            }
        }
        catch { $lastStatus = 'exception type ' + $_.Exception.GetType().Name }
        Start-Sleep -Seconds 1
    }
    throw "$nodeLabel did not become healthy within 120 seconds ($lastStatus; body omitted)."
}

function Write-SafeStartupDiagnostics([string]$container) {
    $raw = & docker logs --tail 160 $container 2>&1
    if ($LASTEXITCODE -ne 0) { Write-Result "Startup logs unavailable for $container."; return }
    $safe = $raw | ForEach-Object { [string]$_ } | Where-Object {
        $_ -match '(?i)(Schema-validation|SchemaManagementException|missing table|missing column|wrong column type|Caused by:|ERROR|Failed to|profile.*integration)' -and
        $_ -notmatch '(?i)(password|secret|token|credential|authorization|jdbc:|bearer)'
    } | Select-Object -Last 12
    foreach ($line in $safe) {
        if ($line.Length -gt 500) { $line = $line.Substring(0, 500) }
        Write-Result ("Backend diagnostic [$container]: " + $line)
    }
}

$savedEnvironment = @{}
foreach ($key in @('POSTGRES_PASSWORD', 'PGPASSWORD', 'APP_DB_USERNAME', 'APP_DB_PASSWORD',
                   'DB_HOST', 'DB_PORT', 'DB_NAME', 'DB_USERNAME', 'DB_PASSWORD',
                   'JWT_SECRET', 'SPRING_PROFILES_ACTIVE', 'SQLI_DEMO_ENABLED')) {
    $savedEnvironment[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
}
$imageAttempted = $false
$networkAttempted = $false
$dbAttempted = $false
$node1Attempted = $false
$node2Attempted = $false
$failure = $null
$cleanupIssues = New-Object 'System.Collections.Generic.List[string]'

try {
    [void](Invoke-Docker @('version', '--format', '{{.Server.Version}}') 'Docker Engine check')
    Write-Result "Test resources: network=$networkName database=$dbContainer node1=$node1 node2=$node2 image=$imageTag."

    Confirm-NameFree @('network', 'ls', '--filter', ('name=^' + $networkName + '$'),
        '--format', '{{.Name}}') $networkName
    foreach ($name in @($dbContainer, $node1, $node2)) {
        Confirm-NameFree @('container', 'ls', '--all', '--filter', ('name=^/' + $name + '$'),
            '--format', '{{.Names}}') $name
    }
    Confirm-NameFree @('image', 'ls', '--filter', ('reference=' + $imageTag),
        '--format', '{{.Repository}}:{{.Tag}}') $imageTag

    # Build once from this checkout; both nodes use this exact image tag.
    # The existing .dockerignore excludes .env and logs from the build context.
    $imageAttempted = $true
    [void](Invoke-Docker @('build', '--quiet', '--label', ($marker + '=' + $runId),
        '--tag', $imageTag, '--file', (Join-Path $projectRoot 'Dockerfile'), $projectRoot) 'Building test backend image')
    Write-Result 'PASS: one disposable backend image built from current source.'

    $networkAttempted = $true
    [void](Invoke-Docker @('network', 'create', '--driver', 'bridge',
        '--label', ($marker + '=' + $runId), $networkName) 'Creating test network')
    Write-Result 'Private Docker network created; no business network was joined.'

    # New test-only values; existing .env is never read. Docker -e NAME transfers
    # each value from this PowerShell process without writing it in command argv.
    $env:POSTGRES_PASSWORD = New-RandomValue 32
    $env:APP_DB_USERNAME = $appRole
    $env:APP_DB_PASSWORD = New-RandomValue 32
    $env:PGPASSWORD = $env:POSTGRES_PASSWORD
    $env:DB_HOST = $dbContainer
    $env:DB_PORT = '5432'
    $env:DB_NAME = 'postgres'
    $env:DB_USERNAME = $appRole
    $env:DB_PASSWORD = $env:APP_DB_PASSWORD
    $env:JWT_SECRET = New-RandomValue 64 -base64
    $env:SPRING_PROFILES_ACTIVE = 'integration'
    $env:SQLI_DEMO_ENABLED = 'false'

    $dbAttempted = $true
    [void](Invoke-Docker @('run', '--detach', '--pull=never', '--name', $dbContainer,
        '--network', $networkName,
        '--tmpfs', '/var/lib/postgresql/data:rw,nosuid,size=512m',
        '--label', ($marker + '=' + $runId),
        '-e', 'POSTGRES_PASSWORD', 'postgres:16-alpine') 'Starting temporary PostgreSQL 16')
    Write-Result 'Temporary PostgreSQL started without a published port or persistent volume.'

    $dbReady = $false
    for ($attempt = 1; $attempt -le 60; $attempt++) {
        & docker exec $dbContainer pg_isready -h 127.0.0.1 -U postgres -d postgres *> $null
        if ($LASTEXITCODE -eq 0) { $dbReady = $true; break }
        Start-Sleep -Seconds 1
    }
    if (-not $dbReady) { throw 'Temporary PostgreSQL did not become ready within 60 seconds.' }

    [void](Invoke-Docker @('cp', $schemaFile, ($dbContainer + ':/tmp/01-schema.sql')) 'Copying schema SQL')
    [void](Invoke-Docker @('cp', $grantsFile, ($dbContainer + ':/tmp/02-least-privilege.sql')) 'Copying grants SQL')
    [void](Invoke-Docker @('exec', '-e', 'PGPASSWORD', $dbContainer, 'psql', '-X',
        '-v', 'ON_ERROR_STOP=1', '-h', '127.0.0.1', '-U', 'postgres', '-d', 'postgres',
        '-f', '/tmp/01-schema.sql') 'Applying schema SQL')
    [void](Invoke-Docker @('exec', '-e', 'PGPASSWORD', '-e', 'APP_DB_USERNAME',
        '-e', 'APP_DB_PASSWORD', $dbContainer, 'psql', '-X', '-v', 'ON_ERROR_STOP=1',
        '-h', '127.0.0.1', '-U', 'postgres', '-d', 'postgres',
        '-f', '/tmp/02-least-privilege.sql') 'Applying least-privilege SQL')
    Write-Result 'PASS: both existing SQL files applied to the temporary database.'

    $backendEnvironment = @('-e', 'DB_HOST', '-e', 'DB_PORT', '-e', 'DB_NAME',
        '-e', 'DB_USERNAME', '-e', 'DB_PASSWORD', '-e', 'JWT_SECRET',
        '-e', 'SPRING_PROFILES_ACTIVE', '-e', 'SQLI_DEMO_ENABLED')
    $node1Attempted = $true
    [void](Invoke-Docker (@('run', '--detach', '--name', $node1,
        '--network', $networkName, '--label', ($marker + '=' + $runId),
        '--memory', '768m', '--publish', '127.0.0.1::8080/tcp') +
        $backendEnvironment + @($imageTag)) 'Starting backend node 1')
    $node2Attempted = $true
    [void](Invoke-Docker (@('run', '--detach', '--name', $node2,
        '--network', $networkName, '--label', ($marker + '=' + $runId),
        '--memory', '768m', '--publish', '127.0.0.1::8080/tcp') +
        $backendEnvironment + @($imageTag)) 'Starting backend node 2')
    $imageId1 = Invoke-Docker @('container', 'inspect', '--format', '{{.Image}}', $node1) 'Reading Node 1 image ID'
    $imageId2 = Invoke-Docker @('container', 'inspect', '--format', '{{.Image}}', $node2) 'Reading Node 2 image ID'
    if ($imageId1 -ne $imageId2) { throw 'Backend nodes do not use the same image ID.' }
    Write-Result 'PASS: both nodes use the same image ID, test DB, and JWT configuration.'

    $base1 = Get-LocalBaseUrl $node1
    $base2 = Get-LocalBaseUrl $node2
    Wait-Healthy $base1 'Node 1'
    Wait-Healthy $base2 'Node 2'
    if ($LabBaseUrl) {
        & (Join-Path $PSScriptRoot 'Test-SqliE2E.ps1') -BaseUrl $base1 -LabBaseUrl $LabBaseUrl
    }

    $usernameA = 'nodea' + $suffix
    $usernameB = 'nodeb' + $suffix
    $passwordA = New-RandomValue 24
    $passwordB = New-RandomValue 24
    $null = Call-Api 'register A on Node 1' $base1 'POST' '/api/v1/auth/register' @{
        username = $usernameA; email = ($usernameA + '@example.test'); password = $passwordA
    } $null 201
    $null = Call-Api 'register B on Node 1' $base1 'POST' '/api/v1/auth/register' @{
        username = $usernameB; email = ($usernameB + '@example.test'); password = $passwordB
    } $null 201
    $loginA = Call-Api 'login A on Node 1' $base1 'POST' '/api/v1/auth/login' @{
        username = $usernameA; password = $passwordA
    } $null 200
    $tokenA = (Parse-ApiJson 'Node 1 login' $loginA.Content).accessToken
    if (-not $tokenA) { throw 'Node 1 login did not return an access token.' }
    $loginB = Call-Api 'login B on Node 2' $base2 'POST' '/api/v1/auth/login' @{
        username = $usernameB; password = $passwordB
    } $null 200
    $tokenB = (Parse-ApiJson 'Node 2 login' $loginB.Content).accessToken
    if (-not $tokenB) { throw 'Node 2 login did not return an access token.' }

    $recordContent = 'two-node-check-' + $runId
    $created = Call-Api 'create Record on Node 1' $base1 'POST' '/api/v1/secure/records' @{
        content = $recordContent
    } $tokenA 201
    $createdRecord = Parse-ApiJson 'Node 1 Record creation' $created.Content
    if (-not $createdRecord.id -or $createdRecord.content -ne $recordContent) {
        throw 'Node 1 returned an unexpected Record response.'
    }
    $recordPath = '/api/v1/secure/records/' + $createdRecord.id
    $readA = Call-Api 'JWT from Node 1 accepted by Node 2' $base2 'GET' $recordPath $null $tokenA 200
    if ((Parse-ApiJson 'Node 2 Record read' $readA.Content).content -ne $recordContent) {
        throw 'Node 2 did not return the Record created on Node 1.'
    }
    Write-Result 'PASS: Node 1 and Node 2 share the test PostgreSQL Record data.'
    $null = Call-Api 'other owner denied by Node 2' $base2 'GET' $recordPath $null $tokenB 403
    $null = Call-Api 'JWT from Node 2 accepted by Node 1; other owner denied' $base1 'GET' $recordPath $null $tokenB 403
    $reverse = Call-Api 'create Record on Node 2 with Node 1 JWT' $base2 'POST' '/api/v1/secure/records' @{
        content = $recordContent
    } $tokenA 201
    $reverseId = (Parse-ApiJson 'Node 2 Record creation' $reverse.Content).id
    if (-not $reverseId) { throw 'Node 2 creation did not return a Record ID.' }
    $reverseRead = Call-Api 'read Node 2 Record on Node 1' $base1 'GET' ('/api/v1/secure/records/' + $reverseId) $null $tokenA 200
    if ((Parse-ApiJson 'Node 1 reverse Record read' $reverseRead.Content).content -ne $recordContent) {
        throw 'Node 1 did not return the Record created on Node 2.'
    }

    # Controlled stop is restricted to this run's labeled Node 1 container.
    $node1Marker = Invoke-Docker @('container', 'inspect', '--format',
        '{{.Config.Labels.btlattt_two_node_check}}', $node1) 'Checking Node 1 ownership before stop'
    if ($node1Marker -ne $runId) { throw 'Node 1 ownership label mismatch; refusing to stop it.' }
    [void](Invoke-Docker @('stop', '--time', '10', $node1) 'Stopping disposable Node 1')
    $node1Running = Invoke-Docker @('container', 'inspect', '--format',
        '{{.State.Running}}', $node1) 'Verifying Node 1 is stopped'
    if ($node1Running -ne 'false') { throw 'Node 1 did not stop as expected.' }
    Write-Result 'PASS: disposable Node 1 stopped with ownership check.'
    $node2Health = Call-Api 'Node 2 health after Node 1 stop' $base2 'GET' '/actuator/health' $null $null 200
    if ($node2Health.Content -notmatch '"status"\s*:\s*"UP"') {
        throw 'Node 2 health response was not UP after Node 1 stopped.'
    }
    $readAfterStop = Call-Api 'Node 2 Record read after Node 1 stop' $base2 'GET' $recordPath $null $tokenA 200
    if ((Parse-ApiJson 'Node 2 Record read after stop' $readAfterStop.Content).content -ne $recordContent) {
        throw 'Node 2 returned different Record content after Node 1 stopped.'
    }
    Write-Result 'PASS: cross-instance JWT, shared Record, ownership 403, and Node 2 readiness after Node 1 stop.'
    Write-Result 'Scope: direct backend node survival only; Nginx load balancing/failover is NOT tested.'
}
catch {
    $failure = $_.Exception.Message
    Write-Result ('FAIL: ' + $failure)
    if ($node1Attempted) { Write-SafeStartupDiagnostics $node1 }
    if ($node2Attempted) { Write-SafeStartupDiagnostics $node2 }
}
finally {
    foreach ($resource in @(
        @{ attempted = $node2Attempted; kind = 'container'; name = $node2 },
        @{ attempted = $node1Attempted; kind = 'container'; name = $node1 },
        @{ attempted = $dbAttempted; kind = 'container'; name = $dbContainer },
        @{ attempted = $networkAttempted; kind = 'network'; name = $networkName },
        @{ attempted = $imageAttempted; kind = 'image'; name = $imageTag }
    )) {
        if (-not $resource.attempted) { continue }
        try {
            $name = $resource.name
            $kind = $resource.kind
            if ($kind -eq 'container') {
                $present = Invoke-Docker @('container', 'ls', '--all', '--filter',
                    ('name=^/' + $name + '$'), '--format', '{{.Names}}') 'Container cleanup lookup'
                if (-not $present) { continue }
                $actualMarker = Invoke-Docker @('container', 'inspect', '--format',
                    '{{.Config.Labels.btlattt_two_node_check}}', $name) 'Container ownership check'
                if ($actualMarker -ne $runId) { throw 'Ownership label mismatch.' }
                [void](Invoke-Docker @('rm', '--force', '--volumes', $name) 'Removing test container')
            }
            elseif ($kind -eq 'network') {
                $present = Invoke-Docker @('network', 'ls', '--filter',
                    ('name=^' + $name + '$'), '--format', '{{.Name}}') 'Network cleanup lookup'
                if (-not $present) { continue }
                $actualMarker = Invoke-Docker @('network', 'inspect', '--format',
                    '{{.Labels.btlattt_two_node_check}}', $name) 'Network ownership check'
                if ($actualMarker -ne $runId) { throw 'Ownership label mismatch.' }
                [void](Invoke-Docker @('network', 'rm', $name) 'Removing test network')
            }
            else {
                $present = Invoke-Docker @('image', 'ls', '--filter',
                    ('reference=' + $name), '--format', '{{.Repository}}:{{.Tag}}') 'Image cleanup lookup'
                if (-not $present) { continue }
                $actualMarker = Invoke-Docker @('image', 'inspect', '--format',
                    '{{.Config.Labels.btlattt_two_node_check}}', $name) 'Image ownership check'
                if ($actualMarker -ne $runId) { throw 'Ownership label mismatch.' }
                [void](Invoke-Docker @('image', 'rm', $name) 'Removing test image')
            }
            Write-Result "Removed test $kind $name."
        }
        catch {
            $issue = "Could not safely remove $($resource.kind) $($resource.name): $($_.Exception.Message)"
            $cleanupIssues.Add($issue)
            Write-Result ('FAIL: ' + $issue)
        }
    }
    foreach ($key in $savedEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($key, $savedEnvironment[$key], 'Process')
    }
}

Write-Result ('Log file: ' + $logFile)
if ($cleanupIssues.Count -gt 0) { throw 'At least one test resource could not be removed; inspect the exact names in the log.' }
if ($failure) { throw $failure }
