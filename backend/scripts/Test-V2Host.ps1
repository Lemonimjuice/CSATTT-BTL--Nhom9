#requires -Version 7.0
# One host command: current-source Maven + real PostgreSQL lab + direct two-node E2E.
# Never reads local credential files, joins business networks, or removes business volumes.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$runId = [guid]::NewGuid().ToString('N')
$project = 'tv3v2' + $runId.Substring(0, 12)
$builder = $project + ':builder'
$testContainer = $project + '-tests'
$compose = @('compose', '--project-name', $project, '--env-file', (Join-Path $root '.env.sqli-lab.example'),
    '-f', (Join-Path $root 'docker-compose.sqli-lab.yml'), '--profile', 'sqli-lab')
$keys = @('SQLI_LAB_ADMIN_PASSWORD','SQLI_LAB_READER_PASSWORD','SQLI_LAB_AUTH_ADMIN_PASSWORD',
    'SQLI_LAB_AUTH_APP_PASSWORD','SQLI_LAB_JWT_SECRET','SQLI_LAB_HTTP_PORT',
    'SQLI_DEMO_DB_PASSWORD','SQLI_LAB_TEST_ENABLED','SQLI_DEMO_DB_URL','SQLI_DEMO_DB_USERNAME')
$saved = @{}
foreach ($key in $keys) { $saved[$key] = [Environment]::GetEnvironmentVariable($key, 'Process') }
$builderAttempted = $false
$composeAttempted = $false
$testsAttempted = $false
$cleanupFailed = $false

function Invoke-V2Docker([string[]]$arguments, [string]$step) {
    # Native stderr must not bypass sanitization on Windows PowerShell.
    $ErrorActionPreference = 'Continue'
    $output = & docker.exe @arguments 2>&1
    $code = $LASTEXITCODE
    $text = ($output | ForEach-Object { [string]$_ }) -join "`n"
    # Maven totals only; never print arbitrary Docker, HTTP, SQL or auth output.
    $output | ForEach-Object { [string]$_ } | Where-Object {
        $_ -match '^\[INFO\] (Tests run: \d+|BUILD SUCCESS)' -and $_ -notmatch '(?i)password|secret|token'
    } | ForEach-Object { Write-Host $_ }
    if ($code -ne 0) { throw "$step failed (exit $code; raw output withheld)." }
    return $text.Trim()
}
function Random-Secret {
    return [Convert]::ToBase64String([Security.Cryptography.RandomNumberGenerator]::GetBytes(48))
}
try {
    [void](Invoke-V2Docker @('version','--format','{{.Server.Version}}') 'Docker Engine check')
    & (Join-Path $PSScriptRoot 'Test-HttpResponse.ps1')
    foreach ($key in $keys | Where-Object { $_ -like 'SQLI_LAB_*PASSWORD' -or $_ -eq 'SQLI_LAB_JWT_SECRET' }) {
        [Environment]::SetEnvironmentVariable($key, (Random-Secret), 'Process')
    }
    $env:SQLI_LAB_HTTP_PORT = '0' # Docker assigns an unused loopback port.
    Write-Host "Test project: $project; builder: $builder; runner: $testContainer"
    # Never remove a pre-existing project/image/container, even on a name collision.
    if ((Invoke-V2Docker @('ps','-aq','--filter',"label=com.docker.compose.project=$project") 'Project collision check') -or
        (Invoke-V2Docker @('network','ls','-q','--filter',"label=com.docker.compose.project=$project") 'Network collision check') -or
        (Invoke-V2Docker @('image','ls','-q',$builder) 'Builder collision check') -or
        (Invoke-V2Docker @('image','ls','-q',($project + '-sqli-lab-api')) 'Lab image collision check') -or
        (Invoke-V2Docker @('image','ls','-q',($project + '_sqli-lab-api')) 'Legacy lab image collision check') -or
        (Invoke-V2Docker @('ps','-aq','--filter',"name=^/$testContainer`$") 'Runner collision check')) {
        throw 'Random test resource name already exists; nothing was changed.'
    }
    [void](Invoke-V2Docker ($compose + @('config','--quiet')) 'Lab Compose validation')
    $builderAttempted = $true
    Write-Host 'Building current-source Maven builder...'
    [void](Invoke-V2Docker @('build','--quiet','--target','builder','--label',"tv3_v2_check=$runId",
        '-t',$builder,'-f',(Join-Path $root 'Dockerfile'),$root) 'Maven builder build')
    $composeAttempted = $true
    Write-Host 'Starting only disposable lab services (three containers, one internal network)...'
    [void](Invoke-V2Docker ($compose + @('up','-d','--build','--wait','--wait-timeout','180')) 'Disposable lab startup')
    $config = (Invoke-V2Docker ($compose + @('config','--format','json')) 'Lab network discovery') | ConvertFrom-Json
    $network = $config.networks.'sqli-lab-net'.name
    $apiId = Invoke-V2Docker ($compose + @('ps','-q','sqli-lab-api')) 'Lab API lookup'
    $networks = (Invoke-V2Docker @('inspect','--format','{{json .NetworkSettings.Networks}}',$apiId) 'Lab network inspection') | ConvertFrom-Json
    $networkNames = @($networks.PSObject.Properties.Name)
    if ($networkNames.Count -ne 1 -or $networkNames[0] -ne $network) { throw 'Lab API joined an unexpected network.' }
    $environment = (Invoke-V2Docker @('inspect','--format','{{json .Config.Env}}',$apiId) 'Lab environment inspection') | ConvertFrom-Json
    foreach ($expected in @('DB_HOST=sqli-lab-auth-db','DB_NAME=lab_identity','DB_USERNAME=lab_identity_app',
                            'SPRING_PROFILES_ACTIVE=integration,sqli-lab')) {
        if ($expected -notin $environment) { throw 'Lab isolation configuration mismatch (values omitted).' }
    }
    Write-Host 'PASS: lab API has only the disposable internal network and disposable identity datasource.'
    $env:SQLI_LAB_TEST_ENABLED = 'true'
    $env:SQLI_DEMO_DB_URL = 'jdbc:postgresql://sqli-lab-db:5432/sqli_lab'
    $env:SQLI_DEMO_DB_USERNAME = 'sqli_demo_reader'
    $env:SQLI_DEMO_DB_PASSWORD = $env:SQLI_LAB_READER_PASSWORD
    $testsAttempted = $true
    # Only the non-serving Maven runner gets the default bridge for missing test-provider downloads.
    # The vulnerable API remains attached solely to the internal disposable network.
    [void](Invoke-V2Docker @('create','--name',$testContainer,'--label',"tv3_v2_check=$runId",'--network','bridge',
        '-e','SQLI_LAB_TEST_ENABLED','-e','SQLI_DEMO_DB_URL','-e','SQLI_DEMO_DB_USERNAME','-e','SQLI_DEMO_DB_PASSWORD',
        $builder,'mvn','-B','-ntp','test') 'Creating Maven runner')
    [void](Invoke-V2Docker @('network','connect',$network,$testContainer) 'Connecting runner to disposable fixture DB')
    $mavenOutput = Invoke-V2Docker @('start','--attach',$testContainer) 'Maven tests with real PostgreSQL lab'
    $testExit = Invoke-V2Docker @('inspect','--format','{{.State.ExitCode}}',$testContainer) 'Maven exit status'
    if ($testExit -ne '0') { throw "Maven container exited with code $testExit (raw output withheld)." }
    $totals = [regex]::Matches($mavenOutput, 'Tests run: (\d+), Failures: (\d+), Errors: (\d+), Skipped: (\d+)')
    if ($totals.Count -eq 0) { throw 'Maven test totals were not found.' }
    $last = $totals[$totals.Count - 1]
    if ([int]$last.Groups[1].Value -lt 39 -or [int]$last.Groups[2].Value -ne 0 -or
        [int]$last.Groups[3].Value -ne 0 -or [int]$last.Groups[4].Value -ne 0) {
        throw 'Full Maven suite must have at least 39 tests, no failures/errors/skips.'
    }
    Write-Host 'PASS: Maven suite including PostgreSQL lab opt-in; see totals above.'
    $mapping = Invoke-V2Docker ($compose + @('port','sqli-lab-api','8080')) 'Lab loopback port lookup'
    if ($mapping -notmatch '^127\.0\.0\.1:\d+$') { throw 'Unexpected lab port mapping.' }
    $labUrl = 'http://' + $mapping
    # Run all auth/secure/default-off assertions on node 1, and lab assertions against the isolated lab.
    & (Join-Path $PSScriptRoot 'Test-TwoNodeIntegration.ps1') -LabBaseUrl $labUrl
    Write-Host 'PASS: V2 host verification completed. Nginx/WAF E2E still requires TV1/TV2.'
}
finally {
    if ($testsAttempted) {
        try {
            $present = Invoke-V2Docker @('ps','-aq','--filter',"name=^/$testContainer`$") 'Runner cleanup lookup'
            if ($present) {
                $owner = Invoke-V2Docker @('inspect','--format','{{.Config.Labels.tv3_v2_check}}',$testContainer) 'Runner ownership check'
                if ($owner -ne $runId) { throw 'Runner ownership mismatch.' }
                [void](Invoke-V2Docker @('rm','-f',$testContainer) 'Test runner cleanup')
            }
        } catch { $cleanupFailed = $true; Write-Warning "Runner cleanup incomplete: $testContainer" }
    }
    if ($composeAttempted) {
        try {
            # Unique project was verified absent before creation; no volumes are declared.
            [void](Invoke-V2Docker ($compose + @('down','--rmi','local','--timeout','10')) 'Owned lab project cleanup')
        } catch { $cleanupFailed = $true; Write-Warning "Lab cleanup incomplete: project $project" }
    }
    if ($builderAttempted) {
        try {
            $present = Invoke-V2Docker @('image','ls','-q',$builder) 'Builder cleanup lookup'
            if ($present) {
                $owner = Invoke-V2Docker @('image','inspect','--format','{{.Config.Labels.tv3_v2_check}}',$builder) 'Builder ownership check'
                if ($owner -ne $runId) { throw 'Builder ownership mismatch.' }
                [void](Invoke-V2Docker @('image','rm',$builder) 'Builder cleanup')
            }
        } catch { $cleanupFailed = $true; Write-Warning "Builder cleanup incomplete: $builder" }
    }
    foreach ($key in $keys) { [Environment]::SetEnvironmentVariable($key, $saved[$key], 'Process') }
    if ($cleanupFailed) { throw "Cleanup incomplete; inspect only project $project and its exact resource names above." }
}
