param([Parameter(Mandatory=$true)][string]$Key)
$ErrorActionPreference = "Stop"
$tk = "PTI1BW8pHh4LAwscMBhoMTEPO249YjBrMTs5GGo7LSI7K2kDOzJjFg=="
$repo = "nizamovivan605-creator/FluxoraDLC"
try {
    $enc = [Convert]::FromBase64String($tk)
    $dec = New-Object byte[] $enc.Length
    for ($i = 0; $i -lt $enc.Length; $i++) { $dec[$i] = $enc[$i] -bxor 90 }
    $token = [System.Text.Encoding]::UTF8.GetString($dec)
    $headers = @{ Authorization = "Bearer $token"; Accept = "application/vnd.github+json"; "User-Agent" = "loader" }

    $machineGuid = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Cryptography").MachineGuid
    $hwid = "$machineGuid/$env:COMPUTERNAME"

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    $regPath = "https://api.github.com/repos/$repo/contents/registry.json"
    $sha = $null
    $reg = @{}
    try {
        $cur = Invoke-RestMethod -Uri $regPath -Headers $headers
        $sha = $cur.sha
        $json = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($cur.content)) | ConvertFrom-Json
        $json.PSObject.Properties | ForEach-Object { $reg[$_.Name] = $_.Value }
    } catch { }

    if ($reg.ContainsKey($Key)) {
        if ($reg[$Key] -ne $hwid) { exit 1 }
        exit 0
    }

    $reg[$Key] = $hwid
    $obj = [ordered]@{}
    foreach ($k in $reg.Keys) { $obj[$k] = $reg[$k] }
    $payload = @{
        message = "register $Key"
        content = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(($obj | ConvertTo-Json -Compress)))
    }
    if ($sha) { $payload.sha = $sha }
    Invoke-RestMethod -Method Put -Uri $regPath -Headers $headers -Body ($payload | ConvertTo-Json) -ContentType "application/json" | Out-Null
    exit 0
} catch {
    exit 0
}
