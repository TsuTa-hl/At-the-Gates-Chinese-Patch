param(
    [string]$GamePath
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\tools\AtGPaths.ps1"

$GamePath = Resolve-AtGGamePath $GamePath

$manifestPath = Join-Path $GamePath ".atg-chinese-patch.json"
if (!(Test-Path -LiteralPath $manifestPath)) {
    throw "Patch manifest not found: $manifestPath"
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$backupRoot = [string]$manifest.BackupRoot

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
