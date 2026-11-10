<#
Máy nạn nhân: xem log của 3 lớp (Nginx, WAF, 2 node backend) để thấy quá trình phòng thủ.
Gọi qua file bấm đúp, không cần chạy trực tiếp:
  scripts\Xem-Log.bat                 xem trực tiếp mọi request mới (Ctrl+C hoặc đóng cửa sổ để dừng)
  scripts\Tra-RequestID.bat <rid>     tra một request ID (header X-Request-ID) trong cả 3 lớp
Chỉ đọc các file trong thư mục logs\, không sửa gì. Mã rid in rút gọn 8 ký tự đầu để dò cùng một request qua các lớp.
#>
param([string]$Rid = '', [int]$Seconds = 0)
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }

$root = Split-Path -Parent $PSScriptRoot
$files = [ordered]@{
    'NGINX'  = Join-Path $root 'logs\nginx\access.log'
    'WAF'    = Join-Path $root 'logs\waf\modsec_audit.log'
    'NODE-1' = Join-Path $root 'logs\backend-node-1\audit.log'
    'NODE-2' = Join-Path $root 'logs\backend-node-2\audit.log'
}

function Short([string]$id) { if ($id.Length -gt 8) { $id.Substring(0, 8) } else { $id } }
function StatusColor([string]$code) {
    switch -regex ($code) { '^2' { 'Green' } '^(401|403)$' { 'Yellow' } '^429$' { 'Magenta' } '^5' { 'Red' } default { 'Gray' } }
}
function Out-Layer([string]$layer, [string]$text, [string]$color) {
    Write-Host ('[{0,-6}] ' -f $layer) -NoNewline -ForegroundColor Cyan
    Write-Host $text -ForegroundColor $color
}

# Trả về $true nếu đã in (dòng có ý nghĩa), $false nếu bỏ qua
function Show-Line([string]$layer, [string]$line) {
    if ([string]::IsNullOrWhiteSpace($line)) { return $false }
    if ($layer -eq 'NGINX') {
        $m = [regex]::Match($line, '^(\S+) \[[^\]]+\] "(\S+) (\S+)[^"]*" (\d{3}) rid=(\S+) upstream=(.*?) rt=')
        if (-not $m.Success) { return $false }
        $code = $m.Groups[4].Value; $up = $m.Groups[6].Value
        $note = ''
        if ($up -eq '-') { $note = '  (không tới backend)' }
        elseif ($up -match ',') { $note = '  <- node đầu không trả lời, Nginx chuyển sang node sau (failover)' }
        Out-Layer $layer ('{0} {1} {2}  ip={3} upstream={4} rid={5}{6}' -f $code, $m.Groups[2].Value, $m.Groups[3].Value,
            $m.Groups[1].Value, $up, (Short $m.Groups[5].Value), $note) (StatusColor $code)
        return $true
    }
    if ($layer -eq 'WAF') {
        try { $t = ($line | ConvertFrom-Json).transaction } catch { return $false }
        $rules = @($t.messages | ForEach-Object { $_.details.ruleId } | Where-Object { $_ } | Sort-Object -Unique) -join ' '
        $msgs = @($t.messages | ForEach-Object { $_.message } | Where-Object { $_ } | Select-Object -First 2) -join ' | '
        # Ba trường hợp: chặn; DetectionOnly (phát hiện nhưng cố ý không chặn); On nhưng điểm dưới ngưỡng (chỉ cảnh báo)
        if ($t.is_interrupted) { $verdict = 'CHẶN'; $color = 'Red'; $script:wafVerdict = 'block' }
        elseif ($t.producer.secrules_engine -eq 'DetectionOnly') { $verdict = 'PHÁT HIỆN (DetectionOnly, không chặn)'; $color = 'Yellow'; $script:wafVerdict = 'detect' }
        else {
            $script:wafVerdict = 'warn'
            if ($rules -eq '920350') {
                # CRS 920350: Host là địa chỉ IP (máy khác gọi https://<IP>). Mức cảnh báo, dưới ngưỡng chặn.
                Out-Layer $layer ('cảnh báo nhẹ 920350 (gọi bằng địa chỉ IP), dưới ngưỡng chặn nên cho qua  rid={0}' -f (Short $t.unique_id)) 'DarkGray'
                return $true
            }
            $verdict = 'CẢNH BÁO (dưới ngưỡng chặn, cho qua)'; $color = 'DarkYellow'
        }
        Out-Layer $layer ('{0} {1} {2} {3}  ip={4} luật: {5} rid={6}' -f $verdict, $t.response.http_code, $t.request.method,
            $t.request.uri, $t.client_ip, $rules, (Short $t.unique_id)) $color
        if ($msgs) { Write-Host ('         {0}' -f $msgs) -ForegroundColor DarkGray }
        return $true
    }
    # Backend: bỏ mã màu ANSI, lấy user, ip, rid và nội dung
    $clean = $line -replace "\x1b\[[0-9;]*m", ''
    $m = [regex]::Match($clean, '^\S+ \S+(?: \S+)?\s+(\w+)\s+\[reqId=([^\]]*)\] \[user=([^\]]*)\] \[ip=([^\]]*)\] \S+ - (.*)$')
    if (-not $m.Success) { return $false }
    $level = $m.Groups[1].Value; $msg = $m.Groups[5].Value
    $color = 'Gray'
    if ($level -eq 'ERROR') { $color = 'Red' }
    elseif ($msg -match '-> (401|403)|event=login_failure|denied|Forbidden|Unauthenticated') { $color = 'Yellow' }
    elseif ($msg -match '-> 2\d\d|event=login_success') { $color = 'Green' }
    Out-Layer $layer ('user={0} ip={1} {2}  rid={3}' -f $m.Groups[3].Value, $m.Groups[4].Value, $msg, (Short $m.Groups[2].Value)) $color
    return $true
}

function Show-Ips {
    try {
        $ips = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
            Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' -and $_.InterfaceAlias -notmatch 'vEthernet|VMware|VirtualBox|Loopback' }
        foreach ($ip in $ips) { Write-Host ('  https://{0}   ({1})' -f $ip.IPAddress, $ip.InterfaceAlias) -ForegroundColor White }
    } catch { Write-Host '  (không đọc được IP, xem bằng lệnh ipconfig)' }
}

# ---------- Tra một request ID ----------
if ($Rid) {
    $Rid = $Rid.Trim()
    Write-Host "Tra request ID $Rid trong 3 lớp:" -ForegroundColor White
    $found = @{}; $script:wafVerdict = ''
    foreach ($layer in $files.Keys) {
        $path = $files[$layer]; $found[$layer] = 0
        if (-not (Test-Path $path)) { continue }
        # Docker đang giữ file log, nên mở ở chế độ đọc chung (ReadAllLines bị từ chối)
        $fs = [IO.File]::Open($path, 'Open', 'Read', 'ReadWrite, Delete')
        try { $all = (New-Object IO.StreamReader($fs, [Text.Encoding]::UTF8)).ReadToEnd() } finally { $fs.Dispose() }
        foreach ($line in ($all -split "`r?`n")) {
            if ($line.Contains($Rid) -and (Show-Line $layer $line)) { $found[$layer]++ }
        }
    }
    $backend = $found['NODE-1'] + $found['NODE-2']
    Write-Host ''
    if ($found['NGINX'] -eq 0) { Write-Host 'Không thấy request này trong log Nginx: kiểm tra lại mã (copy cả 32 ký tự).' -ForegroundColor Yellow; exit 1 }
    if ($script:wafVerdict -eq 'block') { Write-Host 'Kết luận: WAF đã chặn ở tầng biên, request KHÔNG tới được backend.' -ForegroundColor Green }
    elseif ($script:wafVerdict -eq 'detect') { Write-Host 'Kết luận: WAF phát hiện tấn công nhưng đang DetectionOnly nên cho qua; xem backend xử lý ra sao ở các dòng NODE.' -ForegroundColor Yellow }
    elseif ($backend -gt 0) { Write-Host 'Kết luận: WAF không chặn (không có gì bất thường hoặc chỉ cảnh báo nhẹ); backend đã xử lý, xem user, ip, mã trả về ở dòng NODE.' -ForegroundColor Green }
    else { Write-Host 'Kết luận: chỉ có ở Nginx (ví dụ bị rate limit 429 hoặc request không ghi log ở backend).' -ForegroundColor Yellow }
    exit 0
}

# ---------- Xem trực tiếp ----------
Write-Host 'Máy tấn công gọi tới máy này bằng một trong các địa chỉ:' -ForegroundColor White
Show-Ips
$mode = 'không rõ (container nginx-waf chưa chạy?)'
try {
    Push-Location $root
    & docker compose exec -T nginx-waf grep -q 'SecRuleEngine DetectionOnly' /etc/nginx/modsecurity-mode.conf 2>$null
    if ($LASTEXITCODE -eq 0) { $mode = 'DetectionOnly (chỉ ghi log, KHÔNG chặn)' } elseif ($LASTEXITCODE -eq 1) { $mode = 'On (chặn)' }
} catch { } finally { Pop-Location }
Write-Host "Chế độ WAF hiện tại: $mode" -ForegroundColor White
Write-Host 'Đang chờ request mới... (Ctrl+C để dừng). Màu: xanh lá = cho qua, vàng = từ chối 401/403 hoặc WAF DetectionOnly, đỏ = WAF chặn, tím = rate limit 429, xám = cảnh báo nhẹ' -ForegroundColor DarkGray
Write-Host ''

$pos = @{}; $rest = @{}
foreach ($layer in $files.Keys) {
    $p = $files[$layer]
    $pos[$layer] = if (Test-Path $p) { (Get-Item $p).Length } else { 0 }
    $rest[$layer] = ''
}
$deadline = if ($Seconds -gt 0) { (Get-Date).AddSeconds($Seconds) } else { [DateTime]::MaxValue }
while ((Get-Date) -lt $deadline) {
    foreach ($layer in $files.Keys) {
        $p = $files[$layer]
        if (-not (Test-Path $p)) { continue }
        try {
            $fs = [IO.File]::Open($p, 'Open', 'Read', 'ReadWrite, Delete')
            try {
                if ($fs.Length -lt $pos[$layer]) { $pos[$layer] = 0; $rest[$layer] = '' }   # file vừa được xoay vòng
                if ($fs.Length -gt $pos[$layer]) {
                    $fs.Position = $pos[$layer]
                    $buf = New-Object byte[] ($fs.Length - $pos[$layer])
                    $n = $fs.Read($buf, 0, $buf.Length)
                    $pos[$layer] += $n
                    $text = $rest[$layer] + [Text.Encoding]::UTF8.GetString($buf, 0, $n)
                    $lines = $text -split "`n"
                    $rest[$layer] = $lines[-1]
                    for ($i = 0; $i -lt $lines.Length - 1; $i++) { [void](Show-Line $layer $lines[$i].TrimEnd("`r")) }
                }
            } finally { $fs.Dispose() }
        } catch { }
    }
    Start-Sleep -Milliseconds 300
}
