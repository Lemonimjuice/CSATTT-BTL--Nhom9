#requires -Version 7.0
param(
    [string]$BaseUrl = 'http://localhost:8080',
    [string]$LabBaseUrl
)

$ErrorActionPreference = 'Stop'
foreach ($address in @($BaseUrl, $LabBaseUrl)) {
    if ($address -and ([uri]$address).Host -notin @('localhost', '127.0.0.1', '[::1]')) {
        throw 'This script only targets a local backend/lab.'
    }
}
$results = [System.Collections.Generic.List[object]]::new()

function Call-Api($name, $base, $method, $path, $body, $token, $expected) {
    $parameters = @{
        Uri = $base.TrimEnd('/') + $path
        Method = $method
        SkipHttpErrorCheck = $true
        TimeoutSec = 15
    }
    if ($null -ne $body) {
        $parameters.ContentType = 'application/json'
        $parameters.Body = $body | ConvertTo-Json -Compress
    }
    if ($token) { $parameters.Headers = @{ Authorization = "Bearer $token" } }
    $response = Invoke-WebRequest @parameters
    if ([int]$response.StatusCode -ne $expected) {
        throw "$name expected HTTP $expected, received $($response.StatusCode) (body omitted)."
    }
    $results.Add([pscustomobject]@{ case = $name; status = [int]$response.StatusCode })
    return $response
}

# Only new randomly named accounts and records; never delete existing data.
$suffix = [guid]::NewGuid().ToString('N').Substring(0, 12)
$password = 'A9!' + [guid]::NewGuid().ToString('N')
$tokens = @()
foreach ($label in @('a', 'b')) {
    $username = "sqli$label$suffix"
    $null = Call-Api "register-$label" $BaseUrl POST '/api/v1/auth/register' @{
        username = $username; email = "$username@example.test"; password = $password
    } $null 201
    $login = Call-Api "login-$label" $BaseUrl POST '/api/v1/auth/login' @{
        username = $username; password = $password
    } $null 200
    $tokens += ($login.Content | ConvertFrom-Json).accessToken
}
$ownerToken = $tokens[0]
$otherToken = $tokens[1]
$content = "LAB-ONLY alpha report $suffix"
$created = Call-Api 'record-create' $BaseUrl POST '/api/v1/secure/records' @{content=$content} $ownerToken 201
$id = ($created.Content | ConvertFrom-Json).id
$null = Call-Api 'record-other-create' $BaseUrl POST '/api/v1/secure/records' @{content=$content} $otherToken 201
$null = Call-Api 'record-owner-read' $BaseUrl GET "/api/v1/secure/records/$id" $null $ownerToken 200
$null = Call-Api 'record-other-denied' $BaseUrl GET "/api/v1/secure/records/$id" $null $otherToken 403
$null = Call-Api 'record-missing' $BaseUrl GET '/api/v1/secure/records/9223372036854775807' $null $ownerToken 404
$null = Call-Api 'record-no-jwt' $BaseUrl GET "/api/v1/secure/records/$id" $null $null 401
$null = Call-Api 'record-bad-jwt' $BaseUrl GET "/api/v1/secure/records/$id" $null 'invalid-jwt' 401
$searchPath = '/api/v1/secure/records/search'
$normal = Call-Api 'secure-normal-owner-scope' $BaseUrl POST $searchPath @{keyword=$suffix;ownerId=999999} $ownerToken 200
if (@($normal.Content | ConvertFrom-Json).Count -ne 1) { throw 'Secure search leaked another owner or missed own record.' }
$payload = "' OR 1=1 -- "
$safe = Call-Api 'secure-sqli-literal' $BaseUrl POST $searchPath @{keyword=$payload} $ownerToken 200
if (@($safe.Content | ConvertFrom-Json).Count -ne 0) { throw 'Unexpected SQLi search result.' }
$null = Call-Api 'secure-search-no-jwt' $BaseUrl POST $searchPath @{keyword='alpha'} $null 401
$null = Call-Api 'secure-search-invalid-input' $BaseUrl POST $searchPath @{keyword=' '} $ownerToken 400
$null = Call-Api 'vuln-disabled-on-main-backend' $BaseUrl POST '/api/v1/vuln/records/search' @{keyword='alpha'} $ownerToken 404
$null = Call-Api 'posts-me-anonymous' $BaseUrl GET '/api/v1/posts/me' $null $null 401
$null = Call-Api 'backend-health' $BaseUrl GET '/actuator/health' $null $null 200

if ($LabBaseUrl) {
    $path = '/api/v1/vuln/records/search'
    $normal = Call-Api 'lab-normal' $LabBaseUrl POST $path @{keyword='alpha'} $ownerToken 200
    if (@($normal.Content | ConvertFrom-Json).Count -ne 1) { throw 'Lab fixture must match exactly one alpha record.' }
    $injected = Call-Api 'lab-sqli-contrast' $LabBaseUrl POST $path @{keyword=$payload} $ownerToken 200
    $rows = @($injected.Content | ConvertFrom-Json)
    if ($rows.Count -ne 3 -or @($rows | Where-Object { $_.content -notlike 'LAB-ONLY *' }).Count -ne 0) {
        throw 'Unexpected lab dataset; stop and inspect isolation.'
    }
    foreach ($table in @('users', 'refresh_tokens', 'secure_records')) {
        $null = Call-Api "lab-cannot-read-$table" $LabBaseUrl POST $path @{
            keyword="' UNION ALL SELECT id, 'forbidden' FROM public.$table -- "
        } $ownerToken 400
    }
    $null = Call-Api 'lab-cannot-read-credential-catalog' $LabBaseUrl POST $path @{
        keyword="' UNION ALL SELECT 99, rolpassword FROM pg_catalog.pg_authid -- "
    } $ownerToken 400
    $null = Call-Api 'lab-no-jwt' $LabBaseUrl POST $path @{keyword='alpha'} $null 401
    $null = Call-Api 'lab-invalid-input' $LabBaseUrl POST $path @{keyword=' '} $ownerToken 400
}

# No passwords, tokens or response bodies in output.
$results | ConvertTo-Json
