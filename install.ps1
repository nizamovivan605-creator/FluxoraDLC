param([Parameter(Mandatory=$true)][string]$Nick)
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ProgressPreference = "SilentlyContinue"

$mcVer = "1.21.4"
$base = Join-Path $env:APPDATA ".evaware"
$runDir = Join-Path $base "run"
$libDir = Join-Path $base "libraries"
$natDir = Join-Path $base "natives"
$assetsDir = Join-Path $base "assets"
$modsDir = Join-Path $runDir "mods"

function Log($m) { Write-Host ("[EvaWare] " + $m) }
function EnsureDir($p) { if (!(Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null } }
$wc = New-Object System.Net.WebClient
function Dl($url, $file) {
    if (Test-Path $file) { return }
    EnsureDir (Split-Path $file)
    $wc.DownloadFile($url, $file)
}

EnsureDir $base; EnsureDir $runDir; EnsureDir $libDir; EnsureDir $natDir; EnsureDir $assetsDir; EnsureDir $modsDir

# ---------- Java 21 ----------
$javaExe = $null
$candidates = @("$env:ProgramFiles\Java", "$env:ProgramFiles\Microsoft", "${env:ProgramFiles(x86)}\Java")
foreach ($c in $candidates) {
    if (Test-Path $c) {
        $found = Get-ChildItem $c -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "^jdk-2[1-9]" } | Select-Object -First 1
        if ($found) { $p = Join-Path $found.FullName "bin\javaw.exe"; if (Test-Path $p) { $javaExe = $p; break } }
    }
}
if (!$javaExe) {
    $javaExe = Join-Path $base "jdk\bin\javaw.exe"
    if (!(Test-Path $javaExe)) {
        Log "Downloading Java 21..."
        $jdkZip = Join-Path $base "jdk.zip"
        Dl "https://aka.ms/download-jdk/microsoft-jdk-21.0.5-windows-x64.zip" $jdkZip
        Log "Extracting Java..."
        Expand-Archive -Path $jdkZip -DestinationPath $base -Force
        $extracted = Get-ChildItem $base -Directory | Where-Object { $_.Name -match "^jdk-21" -and $_.Name -ne "jdk" } | Select-Object -First 1
        if (Test-Path (Join-Path $base "jdk")) { Remove-Item (Join-Path $base "jdk") -Recurse -Force }
        Move-Item $extracted.FullName (Join-Path $base "jdk") -Force
        Remove-Item $jdkZip -Force
    }
}
Log ("Java: " + $javaExe)

# ---------- Minecraft version ----------
Log "Fetching game version..."
$manifest = Invoke-RestMethod "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json"
$vinfo = $manifest.versions | Where-Object { $_.id -eq $mcVer } | Select-Object -First 1
$vjsonPath = Join-Path $base ("version_" + $mcVer + ".json")
if (!(Test-Path $vjsonPath)) { (Invoke-WebRequest -Uri $vinfo.url -UseBasicParsing).Content | Set-Content $vjsonPath -Encoding UTF8 }
$vjson = Get-Content $vjsonPath -Raw | ConvertFrom-Json

$mcJar = Join-Path $base ("minecraft_" + $mcVer + ".jar")
if (!(Test-Path $mcJar)) { Log "Downloading game client..."; Dl $vjson.downloads.client.url $mcJar }

# ---------- Fabric loader ----------
Log "Fetching Fabric loader..."
$loaderMeta = Invoke-RestMethod ("https://meta.fabricmc.net/v2/versions/loader/" + $mcVer)
$loader = $loaderMeta | Select-Object -First 1
$loaderVer = $loader.loader.version
$loaderJar = Join-Path $libDir ("fabric-loader-" + $loaderVer + ".jar")
if (!(Test-Path $loaderJar)) { Dl ("https://maven.fabricmc.net/net/fabricmc/fabric-loader/" + $loaderVer + "/fabric-loader-" + $loaderVer + ".jar") $loaderJar }

$intJar = Join-Path $libDir ("intermediary-" + $mcVer + ".jar")
if (!(Test-Path $intJar)) { Dl ("https://maven.fabricmc.net/net/fabricmc/intermediary/" + $mcVer + "/intermediary-" + $mcVer + ".jar") $intJar }

function LibUrl($lib) {
    $parts = $lib.name -split ":"
    $path = ($parts[0] -replace "\.", "/") + "/" + $parts[1] + "/" + $parts[2] + "/" + $parts[1] + "-" + $parts[2] + ".jar"
    if ($lib.url) { return ($lib.url.TrimEnd("/")) + "/" + $path }
    return "https://libraries.minecraft.net/" + $path
}
function LibFile($name) {
    return Join-Path $libDir (($name -replace ":", "_") + ".jar")
}
function LibAllowed($lib) {
    if (!$lib.rules) { return $true }
    $allow = $false
    foreach ($rule in $lib.rules) {
        $match = $true
        if ($rule.os) {
            if ($rule.os.name -ne "windows") { $match = $false }
            if ($rule.os.arch -and $rule.os.arch -ne "x86_64") { $match = $false }
        }
        if ($match) { $allow = ($rule.action -eq "allow") }
    }
    return $allow
}

# ---------- Libraries ----------
$cp = @($loaderJar, $intJar, $mcJar)
Log "Downloading libraries..."
$libsTodo = @()
$libsTodo += $vjson.libraries
$libsTodo += $loader.launcherMeta.libraries.common
$libsTodo += $loader.launcherMeta.libraries.client
$libMap = [ordered]@{}
foreach ($lib in $libsTodo) {
    if (!(LibAllowed $lib)) { continue }
    if ($lib.natives) {
        $cls = $lib.natives.windows
        if ($cls -and $lib.downloads -and $lib.downloads.classifiers) {
            $cls = $cls -replace '\$\{arch\}', '64'
            if ($lib.downloads.classifiers.PSObject.Properties.Name -contains $cls) {
                $nfile = Join-Path $libDir ((($lib.name -split ":")[1]) + "-" + $cls + ".jar")
                if (!(Test-Path $nfile)) { Dl $lib.downloads.classifiers.$cls.url $nfile; Expand-Archive -Path $nfile -DestinationPath $natDir -Force }
            }
            if ($lib.downloads.classifiers.PSObject.Properties.Name -contains "natives-windows-x86_64") {
                $nfile2 = Join-Path $libDir ((($lib.name -split ":")[1]) + "-natives-windows-x86_64.jar")
                if (!(Test-Path $nfile2)) { Dl $lib.downloads.classifiers."natives-windows-x86_64".url $nfile2; Expand-Archive -Path $nfile2 -DestinationPath $natDir -Force }
            }
        }
        if ($lib.downloads -and $lib.downloads.artifact -and $lib.downloads.artifact.url) {
            $key = $lib.name
            $libMap[$key] = $lib
        }
        continue
    }
    $key = $lib.name
    $libMap[$key] = $lib
}
$count = 0
foreach ($lib in $libMap.Values) {
    $file = LibFile $lib.name
    if (!(Test-Path $file)) {
        $url = $null
        if ($lib.downloads -and $lib.downloads.artifact -and $lib.downloads.artifact.url) { $url = $lib.downloads.artifact.url }
        if (!$url) { $url = LibUrl $lib }
        try { Dl $url $file } catch { Log ("Failed to download " + $lib.name); continue }
    }
    $cp += $file
    $count++
}
Log ("Libraries done: " + $count)

# ---------- fabric-api + client ----------
Log "Fetching fabric-api..."
$fabMeta = [xml]($wc.DownloadString("https://maven.fabricmc.net/net/fabricmc/fabric-api/fabric-api/maven-metadata.xml"))
$fabVer = $fabMeta.metadata.versioning.versions.version | Where-Object { $_ -match ("\+" + $mcVer.Replace(".", "\.")) } | Select-Object -Last 1
$fabJar = Join-Path $modsDir ("fabric-api-" + $fabVer + ".jar")
if (!(Test-Path $fabJar)) { Dl ("https://maven.fabricmc.net/net/fabricmc/fabric-api/fabric-api/" + $fabVer + "/fabric-api-" + $fabVer + ".jar") $fabJar }

$evaJar = Join-Path $modsDir "evaware-3.0.14.jar"
$evaUrl = "https://github.com/nizamovivan605-creator/FluxoraDLC/releases/latest/download/evaware-3.0.14.jar"
$needEva = $true
if (Test-Path $evaJar) {
    try {
        $remoteSize = [long](Invoke-WebRequest -Uri $evaUrl -Method Head -UseBasicParsing -MaximumRedirection 10).Headers["Content-Length"]
        if ((Get-Item $evaJar).Length -eq $remoteSize) { $needEva = $false }
    } catch { }
}
if ($needEva) { Log "Downloading EvaWare client..."; if (Test-Path $evaJar) { Remove-Item $evaJar -Force }; Dl $evaUrl $evaJar }

# ---------- Assets ----------
Log "Assets: index..."
$aidxPath = Join-Path $assetsDir ("indexes\" + $vjson.assetIndex.id + ".json")
if (!(Test-Path $aidxPath)) { EnsureDir (Split-Path $aidxPath); (Invoke-WebRequest -Uri $vjson.assetIndex.url -UseBasicParsing).Content | Set-Content $aidxPath -Encoding UTF8 }
$aidx = Get-Content $aidxPath -Raw | ConvertFrom-Json
$objs = @($aidx.objects.PSObject.Properties)
$total = $objs.Count
Log ("Assets: " + $total + " files")
$i = 0
foreach ($p in $objs) {
    $i++
    $hash = $p.Value.hash
    $f = Join-Path $assetsDir ("objects\" + $hash.Substring(0,2) + "\" + $hash)
    if (!(Test-Path $f)) {
        try { Dl ("https://resources.download.minecraft.net/" + $hash.Substring(0,2) + "/" + $hash) $f } catch { Log ("Asset failed: " + $p.Name); continue }
    }
    if ($i % 200 -eq 0) { Log ("Assets: " + $i + "/" + $total) }
}
Log "Assets done"

# ---------- Launch ----------
Log ("Launching game (nick: " + $Nick + ")...")
$cpStr = ($cp -join ";")
$g = [guid]::NewGuid().ToString("N")
$uuid = $g.Substring(0,8) + "-" + $g.Substring(8,4) + "-" + $g.Substring(12,4) + "-" + $g.Substring(16,4) + "-" + $g.Substring(20,12)
$javaArgs = @(
    "-Xmx2G",
    "-Djava.library.path=$natDir",
    "-Dminecraft.launcher.brand=EvaWare",
    "-cp", $cpStr,
    "net.fabricmc.loader.impl.launch.knot.KnotClient",
    "--assetIndex", $vjson.assetIndex.id,
    "--assetsDir", $assetsDir,
    "--gameDir", $runDir,
    "--version", $mcVer,
    "--username", $Nick,
    "--uuid", $uuid,
    "--userType", "legacy",
    "--accessToken", "0",
    "--versionType", "release",
    "--width", "1280",
    "--height", "720"
)
Start-Process -FilePath $javaExe -ArgumentList $javaArgs -WorkingDirectory $runDir
Log "Game started"
exit 0
