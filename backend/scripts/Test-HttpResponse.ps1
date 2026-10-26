Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Http-Response.ps1')
# Load only definitions; do not run Docker or make HTTP requests.
$source = Join-Path $PSScriptRoot 'Test-TwoNodeIntegration.ps1'
$ast = [Management.Automation.Language.Parser]::ParseFile($source, [ref]$null, [ref]$null)
foreach ($name in @('Call-Api', 'Parse-ApiJson', 'Wait-Healthy')) {
    $definition = $ast.Find({ param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
    }, $true)
    Invoke-Expression $definition.Extent.Text
}
function Write-Result([string]$message) { } # No Docker/file dependencies.
$script:mockBody = '{"status":"UP"}'
function Invoke-WebRequest { return [pscustomobject]@{ StatusCode=200; Content=$script:mockBody } }
function Start-Sleep { throw 'Unexpected health retry in mock regression.' }
foreach ($asBytes in @($false, $true)) {
    $healthJson = '{"status":"UP"}'
    $script:mockBody = if ($asBytes) { ,([Text.Encoding]::UTF8.GetBytes($healthJson)) } else { $healthJson }
    Wait-Healthy 'http://localhost' 'mock node'
    $response = Call-Api 'health response' 'http://localhost' 'GET' '/actuator/health' $null $null 200
    if ($response.Content -isnot [string] -or (Parse-ApiJson 'health' $response.Content).status -ne 'UP') {
        throw 'Health response normalization failed.'
    }
    $json = '{"accessToken":"test-only-token","content":"Tiếng Việt"}'
    $script:mockBody = if ($asBytes) { ,([Text.Encoding]::UTF8.GetBytes($json)) } else { $json }
    $response = Call-Api 'login response' 'http://localhost' 'POST' '/api/v1/auth/login' @{} $null 200
    $parsed = Parse-ApiJson 'login' $response.Content
    if ($parsed.accessToken -ne 'test-only-token' -or $parsed.content -ne 'Tiếng Việt') {
        throw 'UTF-8 JSON normalization failed.'
    }
    if ((Parse-ApiJson 'raw content' $script:mockBody).content -ne 'Tiếng Việt') { throw 'Direct JSON parsing failed.' }
}
if ((ConvertTo-HttpText $null) -ne '') { throw 'Null normalization failed.' }
try { Parse-ApiJson 'malformed' 'invalid' | Out-Null; throw 'Expected malformed JSON failure.' }
catch { if ($_.Exception.Message -ne 'malformed returned malformed JSON (body omitted).') { throw } }
Write-Host 'PASS: string/byte[] UTF-8 across health, response, login JSON, direct parsing; null and malformed JSON.'
