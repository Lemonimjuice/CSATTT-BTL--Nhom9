#requires -Version 7.0
param(
    [switch]$WithLab,
    [string]$Image = 'btl-backend-tests'
)

$ErrorActionPreference = 'Stop'
$repoPath = Split-Path $PSScriptRoot -Parent
$previousReaderPassword = [Environment]::GetEnvironmentVariable('SQLI_DEMO_DB_PASSWORD', 'Process')
Push-Location $repoPath
try {
    $dockerArguments = @('run', '--rm', '--mount', "type=bind,source=$repoPath,target=/workspace", '--workdir', '/workspace')
    if ($WithLab) {
        # Resolve project-specific network names without displaying resolved Compose credentials.
        $composeArguments = @('compose', '--env-file', '.env', '--env-file', '.env.sqli-lab',
            '-f', 'docker-compose.yml', '-f', 'docker-compose.sqli-lab.yml', '--profile', 'sqli-lab')
        $configText = & docker @composeArguments config --format json
        if ($LASTEXITCODE -ne 0) { throw 'Lab Compose config is invalid.' }
        $config = $configText | ConvertFrom-Json
        $databaseId = & docker @composeArguments ps --status running -q sqli-lab-db
        if (-not $databaseId) { throw 'Start the isolated lab database before running -WithLab.' }
        $readerLine = Get-Content -LiteralPath .env.sqli-lab |
            Where-Object { $_.StartsWith('SQLI_LAB_READER_PASSWORD=') } | Select-Object -First 1
        if (-not $readerLine) { throw 'Missing local lab reader password.' }
        $env:SQLI_DEMO_DB_PASSWORD = $readerLine.Substring('SQLI_LAB_READER_PASSWORD='.Length).Trim().Trim('"').Trim("'")
        $dockerArguments += @('--network', $config.networks.'blog-net'.name,
            '--network', $config.networks.'sqli-lab-net'.name,
            '--env', 'SQLI_LAB_TEST_ENABLED=true',
            '--env', 'SQLI_DEMO_DB_URL=jdbc:postgresql://sqli-lab-db:5432/sqli_lab',
            '--env', 'SQLI_DEMO_DB_USERNAME=sqli_demo_reader', '--env', 'SQLI_DEMO_DB_PASSWORD')
    }
    $dockerArguments += @($Image, 'mvn', '-B', '-ntp', 'test')
    & docker @dockerArguments
    if ($LASTEXITCODE -ne 0) { throw 'Maven Docker tests failed; inspect the test output.' }
} finally {
    [Environment]::SetEnvironmentVariable('SQLI_DEMO_DB_PASSWORD', $previousReaderPassword, 'Process')
    Pop-Location
}
