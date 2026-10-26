# Run manually from Windows PowerShell. Builds a disposable backend image and
# validates the existing SQL schema against Hibernate without host-published ports.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$sqlRoot = (Resolve-Path (Join-Path $projectRoot '../database/init')).Path
$schemaFile = Join-Path $sqlRoot '01-schema.sql'
$grantsFile = Join-Path $sqlRoot '02-least-privilege.sql'
$profileFile = Join-Path $projectRoot 'src/main/resources/application-integration.yml'
foreach ($file in @($schemaFile, $grantsFile, $profileFile, (Join-Path $projectRoot 'Dockerfile'))) {
    if (-not (Test-Path -LiteralPath $file)) { throw "Required project file is missing: $file" }
}
if ((Get-Content -LiteralPath $profileFile -Raw) -notmatch '(?m)^\s+ddl-auto:\s*validate\s*$') {
    throw 'Integration profile does not declare ddl-auto: validate.'
}

$runId = [guid]::NewGuid().ToString('N')
$suffix = $runId.Substring(0, 12)
$networkName = 'btlattt-hv-net-' + $suffix
$dbName = 'btlattt-hv-db-' + $suffix
$backendName = 'btlattt-hv-api-' + $suffix
$imageTag = 'btlattt-hibernate-check:' + $suffix
$appRole = 'hv_' + $suffix
$markerKey = 'btlattt_hibernate_check'
$logDir = Join-Path $projectRoot 'logs'
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$logFile = Join-Path $logDir ('hibernate-validation-' + $runId + '.log')

function Write-Result([string]$message) {
    $line = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ' + $message
    Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8
    Write-Host $line
}

function Invoke-Docker([string[]]$dockerArgs, [string]$step) {
    # Never log raw Docker/psql output: it can contain expanded SQL or environment data.
    $output = & docker @dockerArgs 2>&1
    $code = $LASTEXITCODE
    if ($code -ne 0) {
        $safeLines = $output | ForEach-Object { [string]$_ } | Where-Object {
            $_ -match '(?i)(ERROR:|FATAL:|failed to solve|BUILD FAILURE|Failed to execute goal|Caused by:|permission denied|not found|unable to|connection refused)' -and
            $_ -notmatch '(?i)(password|secret|token|credential|authorization|jdbc:|bearer)'
        } | Select-Object -Last 6
        foreach ($line in $safeLines) {
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
    $found = Invoke-Docker $dockerArgs "Checking name $name"
    if ($found) { throw "Test resource name already exists: $name" }
}

function Write-SafeBackendDiagnostics {
    if (-not $script:backendAttempted) { return }
    $raw = & docker logs --tail 200 $script:backendName 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Result 'Backend logs unavailable; inspect the test container only if it still exists.'
        return
    }
    $lines = $raw | ForEach-Object { [string]$_ } | Where-Object {
        $_ -match '(?i)(Schema-validation|SchemaManagementException|missing table|missing column|wrong column type|Caused by:|ERROR|Failed to|Started BlogApiApplication|profile.*integration)' -and
        $_ -notmatch '(?i)(password|secret|token|credential|authorization|jdbc:|bearer)'
    } | Select-Object -Last 15
    foreach ($line in $lines) {
        if ($line.Length -gt 500) { $line = $line.Substring(0, 500) }
        Write-Result ('Backend diagnostic: ' + $line)
    }
    if (-not $lines) { Write-Result 'No safely reportable backend diagnostic line was found.' }
}

$savedEnvironment = @{}
foreach ($key in @('POSTGRES_PASSWORD', 'APP_DB_USERNAME', 'APP_DB_PASSWORD',
                   'PGPASSWORD', 'DB_HOST', 'DB_PORT', 'DB_NAME', 'DB_USERNAME',
                   'DB_PASSWORD', 'JWT_SECRET', 'SPRING_PROFILES_ACTIVE', 'SQLI_DEMO_ENABLED')) {
    $savedEnvironment[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
}
$imageAttempted = $false
$networkAttempted = $false
$dbAttempted = $false
$backendAttempted = $false
$failure = $null
$cleanupIssues = New-Object 'System.Collections.Generic.List[string]'

try {
    $serverVersion = Invoke-Docker @('version', '--format', '{{.Server.Version}}') 'Docker Engine check'
    Write-Result "Docker Engine available (server $serverVersion)."
    Write-Result "Test resources: network=$networkName database=$dbName backend=$backendName image=$imageTag."

    Confirm-NameFree @('network', 'ls', '--filter', ('name=^' + $networkName + '$'),
        '--format', '{{.Name}}') $networkName
    Confirm-NameFree @('container', 'ls', '--all', '--filter', ('name=^/' + $dbName + '$'),
        '--format', '{{.Names}}') $dbName
    Confirm-NameFree @('container', 'ls', '--all', '--filter', ('name=^/' + $backendName + '$'),
        '--format', '{{.Names}}') $backendName
    Confirm-NameFree @('image', 'ls', '--filter', ('reference=' + $imageTag),
        '--format', '{{.Repository}}:{{.Tag}}') $imageTag

    # Build from this checkout so the integration profile is actually present.
    # .dockerignore excludes .env and logs. No business container/image is changed.
    $imageAttempted = $true
    [void](Invoke-Docker @('build', '--quiet', '--label', ($markerKey + '=' + $runId),
        '--tag', $imageTag, '--file', (Join-Path $projectRoot 'Dockerfile'), $projectRoot) 'Building disposable backend image')
    Write-Result 'PASS: disposable backend image built from current source.'

    $networkAttempted = $true
    [void](Invoke-Docker @('network', 'create', '--driver', 'bridge', '--internal',
        '--label', ($markerKey + '=' + $runId), $networkName) 'Creating isolated network')
    Write-Result 'Private internal Docker network created.'

    # Process-only test credentials are sent to Docker by variable NAME, never
    # as a command argument value or a file. They are restored in finally.
    $env:POSTGRES_PASSWORD = New-RandomValue 32
    $env:APP_DB_USERNAME = $appRole
    $env:APP_DB_PASSWORD = New-RandomValue 32
    $env:PGPASSWORD = $env:POSTGRES_PASSWORD
    $env:DB_HOST = $dbName
    $env:DB_PORT = '5432'
    $env:DB_NAME = 'postgres'
    $env:DB_USERNAME = $appRole
    $env:DB_PASSWORD = $env:APP_DB_PASSWORD
    $env:JWT_SECRET = New-RandomValue 64 -base64
    $env:SPRING_PROFILES_ACTIVE = 'integration'
    $env:SQLI_DEMO_ENABLED = 'false'

    $dbAttempted = $true
    [void](Invoke-Docker @('run', '--detach', '--pull=never', '--name', $dbName,
        '--network', $networkName,
        '--tmpfs', '/var/lib/postgresql/data:rw,nosuid,size=512m',
        '--label', ($markerKey + '=' + $runId),
        '-e', 'POSTGRES_PASSWORD', 'postgres:16-alpine') 'Starting temporary PostgreSQL 16')
    Write-Result 'Temporary PostgreSQL started without a host-published port or persistent volume.'

    $dbReady = $false
    for ($attempt = 1; $attempt -le 60; $attempt++) {
        & docker exec $dbName pg_isready -h 127.0.0.1 -U postgres -d postgres *> $null
        if ($LASTEXITCODE -eq 0) { $dbReady = $true; break }
        Start-Sleep -Seconds 1
    }
    if (-not $dbReady) { throw 'Temporary PostgreSQL did not become ready within 60 seconds.' }

    [void](Invoke-Docker @('cp', $schemaFile, ($dbName + ':/tmp/01-schema.sql')) 'Copying schema SQL')
    [void](Invoke-Docker @('cp', $grantsFile, ($dbName + ':/tmp/02-least-privilege.sql')) 'Copying grants SQL')
    [void](Invoke-Docker @('exec', '-e', 'PGPASSWORD', $dbName, 'psql', '-X',
        '-v', 'ON_ERROR_STOP=1', '-h', '127.0.0.1', '-U', 'postgres', '-d', 'postgres',
        '-f', '/tmp/01-schema.sql') 'Applying 01-schema.sql')
    [void](Invoke-Docker @('exec', '-e', 'PGPASSWORD', '-e', 'APP_DB_USERNAME',
        '-e', 'APP_DB_PASSWORD', $dbName, 'psql', '-X', '-v', 'ON_ERROR_STOP=1',
        '-h', '127.0.0.1', '-U', 'postgres', '-d', 'postgres',
        '-f', '/tmp/02-least-privilege.sql') 'Applying 02-least-privilege.sql')
    Write-Result 'PASS: both existing SQL scripts applied to the temporary database.'

    $backendAttempted = $true
    [void](Invoke-Docker @('run', '--detach', '--name', $backendName,
        '--network', $networkName, '--label', ($markerKey + '=' + $runId),
        '--memory', '768m',
        '-e', 'DB_HOST', '-e', 'DB_PORT', '-e', 'DB_NAME', '-e', 'DB_USERNAME',
        '-e', 'DB_PASSWORD', '-e', 'JWT_SECRET', '-e', 'SPRING_PROFILES_ACTIVE',
        '-e', 'SQLI_DEMO_ENABLED', $imageTag) 'Starting integration-profile backend')
    Write-Result 'Backend started with integration profile and disposable credentials.'

    # The PostgreSQL Alpine image includes BusyBox wget. Probe from the same
    # private network, with no host port and no connection to business services.
    $health = $null
    for ($attempt = 1; $attempt -le 120; $attempt++) {
        # Suppress wget's expected connection-refused stderr INSIDE the container.
        # Windows PowerShell 5.1 can otherwise treat redirected native stderr as a terminating error.
        $response = & docker exec $dbName sh -c ('wget -qO- http://' + $backendName + ':8080/actuator/health 2>/dev/null')
        if ($LASTEXITCODE -eq 0 -and (($response -join '') -match '"status"\s*:\s*"UP"')) {
            $health = 'UP'
            break
        }
        Start-Sleep -Seconds 1
    }
    if ($health -ne 'UP') {
        Write-SafeBackendDiagnostics
        throw 'Backend did not return actuator health UP within 120 seconds; review safe diagnostics above.'
    }

    $startupLog = Invoke-Docker @('logs', '--tail', '200', $backendName) 'Reading backend startup status'
    if ($startupLog -notmatch 'Started BlogApiApplication' -or
        $startupLog -notmatch '(?i)profile[s]?.*integration') {
        Write-SafeBackendDiagnostics
        throw 'HTTP health was UP, but integration profile/startup evidence was not found in backend logs.'
    }
    Write-Result 'PASS: integration profile active, Spring Boot startup recorded, actuator health UP.'

    # The role name is generated locally from hexadecimal characters only.
    $activitySql = "SELECT count(*) FROM pg_stat_activity WHERE usename = '$appRole';"
    $env:PGPASSWORD = $env:POSTGRES_PASSWORD
    $activity = Invoke-Docker @('exec', '-e', 'PGPASSWORD', $dbName, 'psql', '-X',
        '-A', '-t', '-v', 'ON_ERROR_STOP=1',
        '-h', '127.0.0.1', '-U', 'postgres', '-d', 'postgres', '-c', $activitySql) 'Checking backend database connection'
    if ([int]$activity -lt 1) { throw 'No backend connection from the temporary application role was observed.' }
    Write-Result 'PASS: temporary application role has an active PostgreSQL connection.'
    Write-Result 'PASS: Hibernate schema validation completed during startup with ddl-auto=validate.'
}
catch {
    $failure = $_.Exception.Message
    Write-Result ('FAIL: ' + $failure)
    if ($backendAttempted -and $failure -notmatch 'Backend did not return|startup evidence') {
        Write-SafeBackendDiagnostics
    }
}
finally {
    foreach ($resource in @(
        @{ attempted = $backendAttempted; kind = 'container'; name = $backendName },
        @{ attempted = $dbAttempted; kind = 'container'; name = $dbName },
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
                    '{{.Config.Labels.btlattt_hibernate_check}}', $name) 'Container ownership check'
                if ($actualMarker -ne $runId) { throw 'Ownership marker mismatch.' }
                [void](Invoke-Docker @('rm', '--force', '--volumes', $name) 'Removing test container')
            }
            elseif ($kind -eq 'network') {
                $present = Invoke-Docker @('network', 'ls', '--filter',
                    ('name=^' + $name + '$'), '--format', '{{.Name}}') 'Network cleanup lookup'
                if (-not $present) { continue }
                $actualMarker = Invoke-Docker @('network', 'inspect', '--format',
                    '{{.Labels.btlattt_hibernate_check}}', $name) 'Network ownership check'
                if ($actualMarker -ne $runId) { throw 'Ownership marker mismatch.' }
                [void](Invoke-Docker @('network', 'rm', $name) 'Removing test network')
            }
            else {
                $present = Invoke-Docker @('image', 'ls', '--filter',
                    ('reference=' + $name), '--format', '{{.Repository}}:{{.Tag}}') 'Image cleanup lookup'
                if (-not $present) { continue }
                $actualMarker = Invoke-Docker @('image', 'inspect', '--format',
                    '{{.Config.Labels.btlattt_hibernate_check}}', $name) 'Image ownership check'
                if ($actualMarker -ne $runId) { throw 'Ownership marker mismatch.' }
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
