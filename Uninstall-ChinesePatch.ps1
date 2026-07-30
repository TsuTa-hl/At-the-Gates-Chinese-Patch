param(
    [string]$GamePath,
    [switch]$SkipSaveNameCompatibility,
    [switch]$NoSaveNameNotice
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\tools\AtGPaths.ps1"
. "$PSScriptRoot\tools\AtGSaveNameCompatibility.ps1"

$GamePath = Resolve-AtGGamePath $GamePath

$manifestPath = Join-Path $GamePath ".atg-chinese-patch.json"
if (!(Test-Path -LiteralPath $manifestPath)) {
    throw "Patch manifest not found: $manifestPath"
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$backupRoot = [string]$manifest.BackupRoot

$renamedSaves = @()
if (!$SkipSaveNameCompatibility) {
    $renamedSaves = @(Convert-AtGSavedGameNamesForOriginalFonts -GamePath $GamePath)
    foreach ($renamedSave in $renamedSaves) {
        Write-Host "Renamed save for original-font compatibility: $($renamedSave.OldName) -> $($renamedSave.NewName)"
    }
}

foreach ($file in $manifest.Files) {
    $relative = [string]$file.RelativePath
    $target = Join-AtGRelativePath $GamePath $relative
    $backup = Join-AtGRelativePath $backupRoot $relative

    if ($file.HadOriginal) {
        if (!(Test-Path -LiteralPath $backup)) {
            throw "Backup file missing: $backup"
        }
        Copy-Item -LiteralPath $backup -Destination $target -Force
    }
    else {
        if (Test-Path -LiteralPath $target) {
            Remove-Item -LiteralPath $target -Force
        }
    }
}

Remove-Item -LiteralPath $manifestPath -Force
Write-Host "Chinese patch uninstalled. Restored from: $backupRoot"

if (!$NoSaveNameNotice) {
    Show-AtGSaveNameCompatibilityNotice -RenamedSaves $renamedSaves
}
