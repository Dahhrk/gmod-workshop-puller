#requires -Version 5.1
param(
    [string] $CollectionId,
    [string] $IdsFile,
    [Parameter(Mandatory = $true)]
    [string] $Dest,
    [string] $SteamCmd,
    [string] $Gmad,
    [string] $CacheDir,
    [string] $ApiKey = $env:STEAM_WEB_API_KEY,
    [int] $TimeoutSec = 180,
    [switch] $DryRun,
    [switch] $SkipExtract
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$STATUSES = @{
    ok           = $true
    already      = $true
    timeout      = $true
    missing      = $true
    extract_fail = $true
    skipped      = $true
}

function Assert-PullStatus([string] $status) {
    if (-not $STATUSES.ContainsKey($status)) {
        throw "WorkshopPuller: unknown status $status"
    }
    return $status
}

function New-PullResult {
    param(
        [string] $Id,
        [string] $Title,
        [string] $Status,
        [string] $Detail,
        [string] $DestFolder
    )
    Assert-PullStatus $Status | Out-Null
    return [pscustomobject]@{
        item   = [pscustomobject]@{ id = [string]$Id; title = $Title }
        status = $Status
        detail = $Detail
        dest   = $DestFolder
    }
}

function Find-SteamCmd([string] $hint) {
    if ($hint) {
        if (Test-Path $hint) { return (Resolve-Path $hint).Path }
        throw "WorkshopPuller: SteamCmd not found at $hint"
    }
    $cmd = Get-Command steamcmd -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $cmd = Get-Command steamcmd.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($p in @(
            "$env:USERPROFILE\steamcmd\steamcmd.exe",
            "C:\steamcmd\steamcmd.exe",
            "C:\Program Files\steamcmd\steamcmd.exe"
        )) {
        if (Test-Path $p) { return $p }
    }
    throw "WorkshopPuller: steamcmd not on PATH. Pass -SteamCmd"
}

function Find-Gmad([string] $hint) {
    if ($hint) {
        if (Test-Path $hint) { return (Resolve-Path $hint).Path }
        throw "WorkshopPuller: Gmad not found at $hint"
    }
    $cmd = Get-Command gmad -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $cmd = Get-Command gmad.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $roots = @(
        "${env:ProgramFiles(x86)}\Steam\steamapps\common\GarrysMod",
        "$env:ProgramFiles\Steam\steamapps\common\GarrysMod"
    )
    foreach ($gmod in $roots) {
        foreach ($rel in @("bin\win64\gmad.exe", "bin\gmad.exe")) {
            $p = Join-Path $gmod $rel
            if (Test-Path $p) { return $p }
        }
    }
    throw "WorkshopPuller: gmad not found. Pass -Gmad or install a GMod client"
}

function Get-CollectionItems([string] $id, [string] $key) {
    $body = @{
        collectioncount     = 1
        "publishedfileids[0]" = $id
    }
    if ($key) { $body.key = $key }
    $url = "https://api.steampowered.com/ISteamRemoteStorage/GetCollectionDetails/v1/"
    $resp = Invoke-RestMethod -Method Post -Uri $url -Body $body
    $detail = $resp.response.collectiondetails[0]
    $children = @()
    if ($detail.children) {
        $children = @($detail.children)
    }
    if ($children.Count -lt 1) {
        return @(
            [pscustomobject]@{ id = [string]$id; title = "" }
        )
    }
    $items = @()
    foreach ($child in $children) {
        $items += [pscustomobject]@{ id = [string]$child.publishedfileid; title = "" }
    }
    return $items
}

function Get-IdsFileItems([string] $path) {
    $items = @()
    Get-Content $path | ForEach-Object {
        $line = $_.Trim()
        if ($line -eq "" -or $line.StartsWith("#")) { return }
        if ($line -notmatch '^\d+$') {
            throw "WorkshopPuller: not a numeric Workshop ID: $line"
        }
        $items += [pscustomobject]@{ id = $line; title = "" }
    }
    return $items
}

function Invoke-ProcessWait {
    param(
        [string] $File,
        [string[]] $Args,
        [int] $TimeoutSec
    )
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $File
    $info.Arguments = ($Args | ForEach-Object {
            if ($_ -match '\s') { '"' + $_ + '"' } else { $_ }
        }) -join " "
    $info.UseShellExecute = $false
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $info
    [void]$proc.Start()
    if (-not $proc.WaitForExit($TimeoutSec * 1000)) {
        try { $proc.Kill() } catch { }
        return [pscustomobject]@{ timedOut = $true; code = -1; stdout = ""; stderr = "timeout ${TimeoutSec}s" }
    }
    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    return [pscustomobject]@{ timedOut = $false; code = $proc.ExitCode; stdout = $stdout; stderr = $stderr }
}

function Find-DownloadedGma([string] $cache, [string] $id) {
    $content = Join-Path $cache "steamapps\workshop\content\4000\$id"
    if (-not (Test-Path $content)) {
        return $null
    }
    $gma = Get-ChildItem $content -Filter *.gma -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($gma) { return $gma.FullName }
    return $content
}

function Copy-ExtractedTree([string] $from, [string] $to) {
    if (Test-Path $to) {
        Remove-Item -Recurse -Force $to
    }
    New-Item -ItemType Directory -Force -Path $to | Out-Null
    Copy-Item -Path (Join-Path $from "*") -Destination $to -Recurse -Force
}

if (-not $CollectionId -and -not $IdsFile) {
    throw "WorkshopPuller: pass -CollectionId or -IdsFile"
}
if ($CollectionId -and $IdsFile) {
    throw "WorkshopPuller: pass only one of -CollectionId or -IdsFile"
}

$Dest = [System.IO.Path]::GetFullPath($Dest)
if (-not (Test-Path $Dest)) {
    New-Item -ItemType Directory -Force -Path $Dest | Out-Null
}

if (-not $CacheDir) {
    $CacheDir = Join-Path $root "cache"
}
$CacheDir = [System.IO.Path]::GetFullPath($CacheDir)
New-Item -ItemType Directory -Force -Path $CacheDir | Out-Null

if ($IdsFile) {
    $items = @(Get-IdsFileItems $IdsFile)
}
else {
    $items = @(Get-CollectionItems $CollectionId $ApiKey)
}

$started = [DateTime]::UtcNow.ToString("o")
$results = @()

if ($DryRun) {
    foreach ($item in $items) {
        $results += New-PullResult -Id $item.id -Title $item.title -Status "skipped" -Detail "dry-run" -DestFolder $null
    }
}
else {
    $steam = Find-SteamCmd $SteamCmd
    $gmadPath = $null
    if (-not $SkipExtract) {
        $gmadPath = Find-Gmad $Gmad
    }
    foreach ($item in $items) {
        $folder = Join-Path $Dest ("ws_" + $item.id)
        if (Test-Path $folder) {
            $results += New-PullResult -Id $item.id -Title $item.title -Status "already" -Detail $folder -DestFolder $folder
            continue
        }
        $run = Invoke-ProcessWait -File $steam -Args @(
            "+force_install_dir", $CacheDir,
            "+login", "anonymous",
            "+workshop_download_item", "4000", $item.id,
            "+quit"
        ) -TimeoutSec $TimeoutSec
        if ($run.timedOut) {
            $results += New-PullResult -Id $item.id -Title $item.title -Status "timeout" -Detail $run.stderr -DestFolder $null
            continue
        }
        $payload = Find-DownloadedGma $CacheDir $item.id
        if (-not $payload) {
            $results += New-PullResult -Id $item.id -Title $item.title -Status "missing" -Detail "steamcmd exit $($run.code)" -DestFolder $null
            continue
        }
        if ($SkipExtract) {
            $results += New-PullResult -Id $item.id -Title $item.title -Status "skipped" -Detail $payload -DestFolder $null
            continue
        }
        try {
            if ($payload.ToLower().EndsWith(".gma")) {
                New-Item -ItemType Directory -Force -Path $folder | Out-Null
                $ex = Invoke-ProcessWait -File $gmadPath -Args @("extract", "-file", $payload, "-out", $folder) -TimeoutSec 120
                if ($ex.timedOut -or $ex.code -ne 0) {
                    if (Test-Path $folder) { Remove-Item -Recurse -Force $folder }
                    $results += New-PullResult -Id $item.id -Title $item.title -Status "extract_fail" -Detail $ex.stderr -DestFolder $null
                    continue
                }
            }
            else {
                Copy-ExtractedTree $payload $folder
            }
            $results += New-PullResult -Id $item.id -Title $item.title -Status "ok" -Detail $folder -DestFolder $folder
        }
        catch {
            if (Test-Path $folder) { Remove-Item -Recurse -Force $folder }
            $results += New-PullResult -Id $item.id -Title $item.title -Status "extract_fail" -Detail $_.Exception.Message -DestFolder $null
        }
    }
}

$ok = 0
$bad = 0
$already = 0
foreach ($row in $results) {
    Assert-PullStatus $row.status | Out-Null
    if ($row.status -eq "ok") { $ok++ }
    elseif ($row.status -eq "already") { $already++ }
    elseif ($row.status -eq "skipped") { }
    else { $bad++ }
}

$report = [pscustomobject]@{
    collection = $CollectionId
    dest       = $Dest
    started    = $started
    finished   = [DateTime]::UtcNow.ToString("o")
    results    = $results
    counts     = [pscustomobject]@{ ok = $ok; bad = $bad; already = $already }
}

$localDir = Join-Path $root "local"
New-Item -ItemType Directory -Force -Path $localDir | Out-Null
$report | ConvertTo-Json -Depth 6 | Set-Content -Encoding utf8 (Join-Path $localDir "last-pull.json")

Write-Host "Workshop Puller"
if ($CollectionId) { Write-Host "collection $CollectionId" }
Write-Host "dest $Dest"
Write-Host "ok $ok / already $already / bad $bad"
Write-Host ""
foreach ($row in $results) {
    $title = $row.item.title
    if (-not $title) { $title = "" }
    Write-Host ("{0} {1} {2} {3}" -f $row.item.id, $row.status, $title, $row.detail)
}

if ($bad -gt 0) { exit 1 }
exit 0
