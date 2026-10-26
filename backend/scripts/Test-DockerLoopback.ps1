Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Docker-Loopback.ps1')
$passed = 0
foreach ($json in @(
    '[{"HostIp":"127.0.0.1","HostPort":"8081"}]',
    "`r`n [ { `"HostIp`": `"127.0.0.1`", `"HostPort`": `"8081`" } ] `r`n"
)) {
    if ((Get-DockerLoopbackUrl $json) -ne 'http://127.0.0.1:8081') { throw 'Valid binding rejected.' }
    $passed++
}
foreach ($json in @(
    'null', '[]', '', 'not-json',
    '[{"HostIp":"0.0.0.0","HostPort":"8081"}]',
    '[{"HostIp":"::","HostPort":"8081"}]',
    '[{"HostIp":"192.168.1.2","HostPort":"8081"}]',
    '[{"HostIp":"localhost","HostPort":"8081"}]',
    '[{"HostIp":"127.0.0.1","HostPort":"8081"},{"HostIp":"0.0.0.0","HostPort":"8081"}]',
    '[{"HostIp":"127.0.0.1","HostPort":"8081"},{"HostIp":"127.0.0.1","HostPort":"8082"}]',
    '[{"HostIp":"127.0.0.1","HostPort":"0"}]',
    '[{"HostIp":"127.0.0.1","HostPort":"65536"}]',
    '[{"HostIp":"127.0.0.1","HostPort":"-1"}]',
    '[{"HostIp":"127.0.0.1","HostPort":"8081/evil"}]',
    '[{"HostPort":"8081"}]', '[{"HostIp":"127.0.0.1"}]'
)) {
    $rejected = $false
    try { $null = Get-DockerLoopbackUrl $json } catch { $rejected = $true }
    if (-not $rejected) { throw 'Unsafe or malformed binding was accepted.' }
    $passed++
}
Write-Host "PASS: $passed Docker loopback parser regressions; public/mixed/invalid bindings refused."
