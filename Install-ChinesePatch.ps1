param(
    [string]$GamePath,
    [switch]$InstallFonts,
    [switch]$PreserveFonts,
    [switch]$NoInstallNotice
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\tools\AtGPaths.ps1"
. "$PSScriptRoot\tools\AtGPatchManifest.ps1"
. "$PSScriptRoot\tools\AtGPatchNotice.ps1"

$GamePath = Resolve-AtGGamePath $GamePath

$patchRoot = Join-Path $PSScriptRoot "patch"
$patchText = Join-Path $patchRoot "Content\Text\English.xml"
if (!(Test-Path -LiteralPath $patchText)) {
    throw "Patch content not found. The patch package is incomplete."
}

$gameExe = Join-Path $GamePath "At The Gates.exe"
if (!(Test-Path -LiteralPath $gameExe)) {
    throw "Game executable not found: $gameExe"
}

if (!$NoInstallNotice) {
    Show-AtGInstallationNotice
}

$manifestPath = Join-Path $GamePath ".atg-chinese-patch.json"
if (Test-Path -LiteralPath $manifestPath) {
    Write-Host "Existing Chinese patch manifest found. Uninstalling previous patch before refresh..."
    & (Join-Path $PSScriptRoot "Uninstall-ChinesePatch.ps1") -GamePath $GamePath -SkipSaveNameCompatibility -NoSaveNameNotice
    Write-Host "Previous Chinese patch uninstalled. Installing refreshed patch..."
}
else {
    Write-Host "No existing Chinese patch manifest found. Installing patch..."
}

$backupBase = Join-Path $GamePath "_ChinesePatchBackup"
$oldestBackup = $null
if (Test-Path -LiteralPath $backupBase) {
    $oldestBackup = Get-ChildItem -LiteralPath $backupBase -Directory |
        Where-Object { Test-Path -LiteralPath (Join-AtGRelativePath $_.FullName "Content\Text\English.xml") } |
        Sort-Object Name |
        Select-Object -First 1
}

if ($oldestBackup) {
    $backupRoot = $oldestBackup.FullName
}
else {
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupRoot = Join-Path $backupBase $timestamp
    New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null
}

function Test-AtGFontPatchFile {
    param([string]$RelativePath)

    $normalized = $RelativePath -replace "/", "\"
    return $normalized.StartsWith("Content\Images\Interface\Components\Fonts\", [System.StringComparison]::OrdinalIgnoreCase)
}

$fontMarkerRelative = "Content\Images\Interface\Components\Fonts\.atg-merged-fonts"
$fontMarker = Join-AtGRelativePath $patchRoot $fontMarkerRelative
$shouldInstallFonts = ($InstallFonts -or (Test-Path -LiteralPath $fontMarker)) -and !$PreserveFonts

$allPatchFiles = @(Get-AtGPatchInventory -PatchRoot $patchRoot)
$files = @()
$skippedFontFiles = @()
foreach ($file in $allPatchFiles) {
    $relative = [string]$file.RelativePath
    if (($relative -replace "/", "\") -eq $fontMarkerRelative) {
        continue
    }

    if ((Test-AtGFontPatchFile $relative) -and !$shouldInstallFonts) {
        $skippedFontFiles += $file
    }
    else {
        $files += $file
    }
}

if ($skippedFontFiles.Count -gt 0) {
    Write-Host "Skipping SpriteFont files to preserve the game's embedded icon glyphs. Build merged fonts first or pass -InstallFonts to override."

    foreach ($skipped in $skippedFontFiles) {
        $relative = [string]$skipped.RelativePath
        $target = Join-AtGRelativePath $GamePath $relative
        $backup = Join-AtGRelativePath $backupRoot $relative

        if (Test-Path -LiteralPath $backup) {
            $targetDir = Split-Path -Parent $target
            if ($targetDir) {
                New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
            }
            Copy-Item -LiteralPath $backup -Destination $target -Force
            Write-Host "Restored original SpriteFont from backup: $relative"
        }
    }
}

$manifestFiles = @()

foreach ($file in $files) {
    $relative = [string]$file.RelativePath
    $target = Join-AtGRelativePath $GamePath $relative
    $backup = Join-AtGRelativePath $backupRoot $relative

    $targetDir = Split-Path -Parent $target
    if ($targetDir) {
        New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
    }

    if (Test-Path -LiteralPath $backup -PathType Leaf) {
        $hadOriginal = $true
    }
    elseif (Test-Path -LiteralPath $target -PathType Leaf) {
        $backupDir = Split-Path -Parent $backup
        if ($backupDir) {
            New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
        }
        Copy-Item -LiteralPath $target -Destination $backup -Force
        $hadOriginal = $true
    }
    else {
        $hadOriginal = $false
    }

    $manifestFiles += [pscustomobject]@{
        RelativePath   = $relative
        HadOriginal    = $hadOriginal
        OriginalSha256 = if ($hadOriginal) { Get-AtGFileSha256 -Path $backup } else { $null }
        PatchSha256    = [string]$file.PatchSha256
    }
}

$manifest = [pscustomobject]@{
    SchemaVersion = 2
    Name          = "At the Gates Chinese Patch"
    InstallState  = "Prepared"
    Prepared      = (Get-Date).ToString("s")
    Installed     = $null
    GamePath      = (Resolve-Path -LiteralPath $GamePath).Path
    BackupRoot    = $backupRoot
    Files         = $manifestFiles
}

Write-AtGPatchManifest -ManifestPath $manifestPath -Manifest $manifest

foreach ($file in $files) {
    $relative = [string]$file.RelativePath
    $target = Join-AtGRelativePath $GamePath $relative
    Copy-Item -LiteralPath $file.SourcePath -Destination $target -Force

    $actualHash = Get-AtGFileSha256 -Path $target
    if ($actualHash -ne $file.PatchSha256) {
        throw "Installed patch file hash does not match the planned artifact: $relative"
    }
}

$manifest.InstallState = "Installed"
$manifest.Installed = (Get-Date).ToString("s")
Write-AtGPatchManifest -ManifestPath $manifestPath -Manifest $manifest

Write-Host "Chinese patch installed."
Write-Host "Backup: $backupRoot"
Write-Host "Manifest: $manifestPath"
