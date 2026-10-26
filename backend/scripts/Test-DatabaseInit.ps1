# Run manually in PowerShell with Docker Desktop available. This script never
# connects to the business database and does not publish a database port.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$sqlRoot = (Resolve-Path (Join-Path $projectRoot '../database/init')).Path
$schemaFile = Join-Path $sqlRoot '01-schema.sql'
$grantsFile = Join-Path $sqlRoot '02-least-privilege.sql'
if (-not (Test-Path -LiteralPath $schemaFile) -or -not (Test-Path -LiteralPath $grantsFile)) {
    throw 'Required SQL files are missing.'
}

$runId = [guid]::NewGuid().ToString('N')
$containerName = 'btlattt-sqlcheck-' + $runId.Substring(0, 12)
$appRole = 'sqlcheck_' + $runId.Substring(0, 12)
$logDir = Join-Path $projectRoot 'logs'
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$logFile = Join-Path $logDir ('sql-init-check-' + $runId + '.log')

function Write-Result([string]$message) {
    $line = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ' + $message
    Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8
    Write-Host $line
}

function Invoke-Docker([string[]]$dockerArgs, [string]$step) {
    # Do not log Docker output: a failing psql command might include SQL text.
    $output = & docker @dockerArgs 2>&1
    $code = $LASTEXITCODE
    if ($code -ne 0) {
        throw "$step failed (Docker exit code $code)."
    }
    return (($output | ForEach-Object { [string]$_ }) -join "`n").Trim()
}

function New-TestPassword {
    $bytes = New-Object byte[] 32
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    return [BitConverter]::ToString($bytes).Replace('-', '')
}

$savedEnvironment = @{}
foreach ($key in @('POSTGRES_PASSWORD', 'APP_DB_USERNAME', 'APP_DB_PASSWORD', 'PGPASSWORD')) {
    $savedEnvironment[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
}
$failure = $null
$cleanupFailure = $null
try {
    $serverVersion = Invoke-Docker @('version', '--format', '{{.Server.Version}}') 'Docker Engine check'
    Write-Result "Docker Engine available (server $serverVersion)."
    Write-Result "Reserved test container name: $containerName."

    # A random name is still checked before creating anything.
    $collision = Invoke-Docker @('container', 'ls', '--all', '--filter',
        ('name=^/' + $containerName + '$'), '--format', '{{.Names}}') 'Container name check'
    if ($collision) { throw 'Generated container name already exists; nothing was created.' }

    $env:POSTGRES_PASSWORD = New-TestPassword
    $env:APP_DB_USERNAME = $appRole
    $env:APP_DB_PASSWORD = New-TestPassword
    $env:PGPASSWORD = $env:POSTGRES_PASSWORD

    # No --publish, no business network, no named/anonymous persistent volume.
    # -e NAME transfers the process environment value without putting it in argv.
    [void](Invoke-Docker @(
        'run', '--detach', '--rm', '--pull=never',
        '--name', $containerName,
        '--network', 'none',
        '--tmpfs', '/var/lib/postgresql/data:rw,nosuid,size=512m',
        '--label', ('btlattt_sqlcheck=' + $runId),
        '-e', 'POSTGRES_PASSWORD',
        'postgres:16-alpine'
    ) 'Starting isolated PostgreSQL 16')
    Write-Result 'Isolated PostgreSQL 16 container created without a published port.'

    $ready = $false
    for ($attempt = 1; $attempt -le 60; $attempt++) {
        & docker exec $containerName pg_isready -h 127.0.0.1 -U postgres -d postgres *> $null
        if ($LASTEXITCODE -eq 0) { $ready = $true; break }
        Start-Sleep -Seconds 1
    }
    if (-not $ready) { throw 'Temporary PostgreSQL did not become ready within 60 seconds.' }

    [void](Invoke-Docker @('cp', $schemaFile, ($containerName + ':/tmp/01-schema.sql')) 'Copying schema script')
    [void](Invoke-Docker @('cp', $grantsFile, ($containerName + ':/tmp/02-least-privilege.sql')) 'Copying grants script')
    [void](Invoke-Docker @('exec', '-e', 'PGPASSWORD', $containerName,
        'psql', '-X', '-v', 'ON_ERROR_STOP=1', '-h', '127.0.0.1', '-U', 'postgres',
        '-d', 'postgres', '-f', '/tmp/01-schema.sql') '01-schema.sql')
    Write-Result 'PASS: 01-schema.sql executed.'
    [void](Invoke-Docker @('exec', '-e', 'PGPASSWORD', '-e', 'APP_DB_USERNAME',
        '-e', 'APP_DB_PASSWORD', $containerName,
        'psql', '-X', '-v', 'ON_ERROR_STOP=1', '-h', '127.0.0.1', '-U', 'postgres',
        '-d', 'postgres', '-f', '/tmp/02-least-privilege.sql') '02-least-privilege.sql')
    Write-Result 'PASS: 02-least-privilege.sql executed.'

    $tablesSql = @'
SELECT coalesce(string_agg(table_name, ',' ORDER BY table_name), '')
FROM information_schema.tables
WHERE table_schema = 'public' AND table_type = 'BASE TABLE';
'@
    $tables = Invoke-Docker @('exec', '-e', 'PGPASSWORD', $containerName,
        'psql', '-X', '-A', '-t', '-v', 'ON_ERROR_STOP=1', '-h', '127.0.0.1',
        '-U', 'postgres', '-d', 'postgres', '-c', $tablesSql) 'Table inventory'
    if ($tables -ne 'categories,comments,posts,refresh_tokens,secure_records,users') {
        throw 'Table inventory differs from the six expected JPA tables.'
    }
    Write-Result 'PASS: exactly six expected public tables exist.'

    $env:PGPASSWORD = $env:APP_DB_PASSWORD
    $privilegesSql = @'
WITH table_permissions(rel, privilege, expected) AS (
    VALUES
      ('users','SELECT',true), ('users','INSERT',true), ('users','UPDATE',false), ('users','DELETE',false),
      ('secure_records','SELECT',true), ('secure_records','INSERT',true), ('secure_records','UPDATE',false), ('secure_records','DELETE',false),
      ('refresh_tokens','SELECT',true), ('refresh_tokens','INSERT',true), ('refresh_tokens','UPDATE',false), ('refresh_tokens','DELETE',true),
      ('posts','SELECT',true), ('posts','INSERT',true), ('posts','UPDATE',true), ('posts','DELETE',true),
      ('comments','SELECT',true), ('comments','INSERT',true), ('comments','UPDATE',true), ('comments','DELETE',true),
      ('categories','SELECT',true), ('categories','INSERT',true), ('categories','UPDATE',true), ('categories','DELETE',true)
), sequence_permissions(seq) AS (
    VALUES ('users_id_seq'), ('secure_records_id_seq'), ('refresh_tokens_id_seq'),
           ('posts_id_seq'), ('comments_id_seq'), ('categories_id_seq')
)
SELECT
    has_database_privilege(current_user, current_database(), 'CONNECT')
    AND NOT has_database_privilege(current_user, current_database(), 'CREATE')
    AND NOT has_database_privilege(current_user, current_database(), 'TEMP')
    AND has_schema_privilege(current_user, 'public', 'USAGE')
    AND NOT has_schema_privilege(current_user, 'public', 'CREATE')
    AND (SELECT NOT (rolsuper OR rolcreatedb OR rolcreaterole OR rolreplication OR rolbypassrls)
         FROM pg_roles WHERE rolname = current_user)
    AND (SELECT pg_get_userbyid(nspowner) <> current_user
         FROM pg_namespace WHERE nspname = 'public')
    AND (SELECT pg_get_userbyid(datdba) <> current_user
         FROM pg_database WHERE datname = current_database())
    AND (SELECT bool_and(has_table_privilege(current_user, 'public.' || rel, privilege) = expected)
         FROM table_permissions)
    AND (SELECT bool_and(has_sequence_privilege(current_user, 'public.' || seq, 'USAGE'))
         FROM sequence_permissions);
'@
    $permissions = Invoke-Docker @('exec', '-e', 'PGPASSWORD', $containerName,
        'psql', '-X', '-A', '-t', '-v', 'ON_ERROR_STOP=1', '-h', '127.0.0.1',
        '-U', $appRole, '-d', 'postgres', '-c', $privilegesSql) 'Application role privilege check'
    if ($permissions -ne 't') { throw 'Application role privilege check did not pass.' }
    Write-Result 'PASS: app role can connect and has the expected table/sequence rights, without database/schema creation or administrator rights.'
    Write-Result 'PASS: SQL initialization checks completed. Hibernate validation was not run.'
}
catch {
    $failure = $_.Exception.Message
    Write-Result ('FAIL: ' + $failure)
}
finally {
    # Clean up only the exact random container bearing this run's marker.
    try {
        $existing = Invoke-Docker @('container', 'ls', '--all', '--filter',
            ('name=^/' + $containerName + '$'), '--format', '{{.Names}}') 'Cleanup container lookup'
        if ($existing) {
            $marker = Invoke-Docker @('container', 'inspect', '--format',
                '{{.Config.Labels.btlattt_sqlcheck}}', $containerName) 'Cleanup ownership check'
            if ($marker -eq $runId) {
                [void](Invoke-Docker @('rm', '--force', '--volumes', $containerName) 'Removing test container')
                Write-Result 'Temporary container removed.'
            }
            else {
                $cleanupFailure = 'Container name exists but ownership marker differs; manual inspection required.'
                Write-Result ('FAIL: ' + $cleanupFailure)
            }
        }
    }
    catch {
        $cleanupFailure = 'Could not verify or remove the temporary container; inspect its exact name from this log.'
        Write-Result ('FAIL: ' + $cleanupFailure)
    }
    foreach ($key in $savedEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($key, $savedEnvironment[$key], 'Process')
    }
}

Write-Result ('Log file: ' + $logFile)
if ($cleanupFailure) { throw $cleanupFailure }
if ($failure) { throw $failure }
