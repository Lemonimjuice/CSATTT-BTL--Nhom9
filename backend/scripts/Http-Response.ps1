# Invoke-WebRequest returns string on some PowerShell versions and byte[] on others.
# Keep conversion before any parameter binding to [string], which would stringify bytes.
function ConvertTo-HttpText($content) {
    if ($null -eq $content) { return '' }
    if ($content -is [byte[]]) { return [Text.Encoding]::UTF8.GetString($content) }
    return [string]$content
}
