param([Parameter(Mandatory=$true)][string]$KeysFile)
$ErrorActionPreference = "Stop"
$tk = "PTI1BW8pHh4LAwscMBhoMTEPO249YjBrMTs5GGo7LSI7K2kDOzJjFg=="
$repo = "nizamovivan605-creator/FluxoraDLC"
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $enc = [Convert]::FromBase64String($tk)
    $dec = New-Object byte[] $enc.Length
    for ($i = 0; $i -lt $enc.Length; $i++) { $dec[$i] = $enc[$i] -bxor 90 }
    $token = [System.Text.Encoding]::UTF8.GetString($dec)
    $headers = @{ Authorization = "Bearer $token"; Accept = "application/vnd.github+json"; "User-Agent" = "loader" }
    $content = Get-Content $KeysFile -Raw
    $b64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($content))
    $url = "https://api.github.com/repos/$repo/contents/keys.txt"
    $sha = $null
    try { $cur = Invoke-RestMethod -Uri $url -Headers $headers; $sha = $cur.sha } catch { }
    $payload = @{ message = "update keys"; content = $b64 }
    if ($sha) { $payload.sha = $sha }
    Invoke-RestMethod -Method Put -Uri $url -Headers $headers -Body ($payload | ConvertTo-Json) -ContentType "application/json" | Out-Null
    exit 0
} catch {
    exit 1
}