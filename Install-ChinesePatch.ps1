param(
    [string]$GamePath,
    [switch]$InstallFonts,
    [switch]$PreserveFonts
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\tools\AtGPaths.ps1"

$GamePath = Resolve-AtGGamePath $GamePath

$patchRoot = Join-Path $PSScriptRoot "patch"
$patchText = Join-Path $patchRoot "Content\Text\English.xml"
if (!(Test-Path -LiteralPath $patchText)) {
    throw "Patch content not found. Run tools\Build-Patch.ps1 first."
}

$gameExe = Join-Path $GamePath "At The Gates.exe"
if (!(Test-Path -LiteralPath $gameExe)) {
    throw "Game executable not found: $gameExe"
}

$manifestPath = Join-Path $GamePath ".atg-chinese-patch.json"
if (Test-Path -LiteralPath $manifestPath) {
    Write-Host "Existing Chinese patch manifest found. Uninstalling previous patch before refresh..."
    & (Join-Path $PSScriptRoot "Uninstall-ChinesePatch.ps1") -GamePath $GamePath
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

$existingManifest = $null
$reusingExistingBackup = $false
if (Test-Path -LiteralPath $manifestPath) {
    $existingManifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $backupRoot = [string]$existingManifest.BackupRoot
    if ($oldestBackup) {
        $backupRoot = $oldestBackup.FullName
    }
    if (!(Test-Path -LiteralPath $backupRoot)) {
        throw "Existing patch manifest points to a missing backup: $backupRoot"
    }
    $reusingExistingBackup = $true
}
else {
    if ($oldestBackup) {
        $backupRoot = $oldestBackup.FullName
        $reusingExistingBackup = $true
    }
    else {
        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $backupRoot = Join-Path $backupBase $timestamp
        New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null
    }
}

$existingFiles = @{}
if ($existingManifest) {
    foreach ($file in $existingManifest.Files) {
        $existingFiles[[string]$file.RelativePath] = [bool]$file.HadOriginal
    }
}

function Test-AtGFontPatchFile {
    param([string]$RelativePath)

    $normalized = $RelativePath -replace "/", "\"
    return $normalized.StartsWith("Content\Images\Interface\Components\Fonts\", [System.StringComparison]::OrdinalIgnoreCase)
}

$fontMarkerRelative = "Content\Images\Interface\Components\Fonts\.atg-merged-fonts"
$fontMarker = Join-AtGRelativePath $patchRoot $fontMarkerRelative
$shouldInstallFonts = ($InstallFonts -or (Test-Path -LiteralPath $fontMarker)) -and !$PreserveFonts

$allPatchFiles = Get-ChildItem -LiteralPath $patchRoot -Recurse -File
$files = @()
$skippedFontFiles = @()
foreach ($file in $allPatchFiles) {
    $relative = $file.FullName.Substring($patchRoot.Length).TrimStart([char[]]@("\", "/"))
    if (($relative -replace "/", "\") -eq $fontMarkerRelative) {
        continue
    }

    if ((Test-AtGFontPatchFile $relative) -and !$shouldInstallFonts) {
        $skippedFontFiles += [pscustomobject]@{
            File         = $file
            RelativePath = $relative
        }
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
    $relative = $file.FullName.Substring($patchRoot.Length).TrimStart([char[]]@("\", "/"))
    $target = Join-AtGRelativePath $GamePath $relative
    $backup = Join-AtGRelativePath $backupRoot $relative

    $targetDir = Split-Path -Parent $target
    if ($targetDir) {
        New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
    }

    if ($existingFiles.ContainsKey($relative)) {
        $hadOriginal = $existingFiles[$relative]
    }
    elseif ($reusingExistingBackup) {
        if (Test-Path -LiteralPath $backup) {
            $hadOriginal = $true
        }
        elseif (Test-Path -LiteralPath $target) {
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
    }
    elseif (Test-Path -LiteralPath $target) {
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

    Copy-Item -LiteralPath $file.FullName -Destination $target -Force
    $manifestFiles += [pscustomobject]@{
        RelativePath = $relative
        HadOriginal  = $hadOriginal
    }
}

$manifest = [pscustomobject]@{
    Name       = "At the Gates Chinese Patch"
    Installed  = (Get-Date).ToString("s")
    GamePath   = (Resolve-Path -LiteralPath $GamePath).Path
    BackupRoot = $backupRoot
    Files      = $manifestFiles
}

$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

Write-Host "Chinese patch installed."
Write-Host "Backup: $backupRoot"
Write-Host "Manifest: $manifestPath"
