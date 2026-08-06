param(
    [string]$GamePath,
    [switch]$SkipSaveNameCompatibility,
    [switch]$NoSaveNameNotice
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\tools\AtGPaths.ps1"
. "$PSScriptRoot\tools\AtGPatchManifest.ps1"
. "$PSScriptRoot\tools\AtGSaveNameCompatibility.ps1"

$GamePath = Resolve-AtGGamePath $GamePath
$manifestPath = Join-Path $GamePath ".atg-chinese-patch.json"
$manifestEntries = @()
$manifest = $null
$usedOrphanRecovery = $false

if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $backupRoot = [string]$manifest.BackupRoot
    if ([string]::IsNullOrWhiteSpace($backupRoot)) {
        throw "Patch manifest does not contain a backup path: $manifestPath"
    }

    $manifestEntries = @(Get-AtGManifestEntries -Manifest $manifest)
}
else {
    $backupBase = Join-Path $GamePath "_ChinesePatchBackup"
    $backupRoot = $null
    if (Test-Path -LiteralPath $backupBase -PathType Container) {
        $backupRoot = Get-ChildItem -LiteralPath $backupBase -Directory |
            Where-Object { Test-Path -LiteralPath (Join-AtGRelativePath $_.FullName "Content\Text\English.xml") } |
            Sort-Object Name |
            Select-Object -First 1 -ExpandProperty FullName
    }
    if ([string]::IsNullOrWhiteSpace($backupRoot)) {
        throw "Patch manifest not found and no recoverable Chinese patch backup exists: $manifestPath"
    }

    $usedOrphanRecovery = $true
    Write-Warning "Patch manifest is missing. Recovering managed files from the Chinese patch backup inventory."
}

if (!(Test-Path -LiteralPath $backupRoot -PathType Container)) {
    throw "Patch backup directory is missing: $backupRoot"
}

$resolvedGamePath = (Resolve-Path -LiteralPath $GamePath).Path.TrimEnd([char[]]@('\', '/'))
$backupBasePath = Join-Path $GamePath "_ChinesePatchBackup"
$resolvedBackupBase = (Resolve-Path -LiteralPath $backupBasePath).Path.TrimEnd([char[]]@('\', '/'))
$resolvedBackupRoot = (Resolve-Path -LiteralPath $backupRoot).Path.TrimEnd([char[]]@('\', '/'))
if (!$resolvedBackupRoot.StartsWith($resolvedBackupBase + "\", [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Patch backup must stay under the game's _ChinesePatchBackup directory: $backupRoot"
}

$renamedSaves = @()
if (!$SkipSaveNameCompatibility) {
    $renamedSaves = @(Convert-AtGSavedGameNamesForOriginalFonts -GamePath $GamePath)
    foreach ($renamedSave in $renamedSaves) {
        Write-Host "Renamed save for original-font compatibility: $($renamedSave.OldName) -> $($renamedSave.NewName)"
    }
}

$recoveryEntries = @{}
function Add-AtGRecoveryEntry {
    param(
        [Parameter(Mandatory = $true)][object]$Entry
    )

    $relative = ConvertTo-AtGNormalizedRelativePath ([string]$Entry.RelativePath)
    $candidate = [pscustomobject]@{
        RelativePath   = $relative
        HadOriginal    = [bool]$Entry.HadOriginal
        OriginalSha256 = [string]$Entry.OriginalSha256
        PatchSha256    = [string]$Entry.PatchSha256
        RecoverySource = [string]$Entry.RecoverySource
    }

    if (!$recoveryEntries.ContainsKey($relative)) {
        $recoveryEntries[$relative] = $candidate
        return
    }

    $existing = $recoveryEntries[$relative]
    if ($candidate.HadOriginal -and !$existing.HadOriginal) {
        $recoveryEntries[$relative] = $candidate
    }
}

foreach ($entry in $manifestEntries) {
    Add-AtGRecoveryEntry $entry
}

$backupEntries = @(Get-AtGBackupEntries -BackupRoot $backupRoot)
foreach ($entry in $backupEntries) {
    Add-AtGRecoveryEntry $entry
}

$patchRoot = Join-Path $PSScriptRoot "patch"
$legacyPatchOnlyEntries = @()
if (Test-Path -LiteralPath $patchRoot -PathType Container) {
    foreach ($entry in @(Get-AtGPatchInventory -PatchRoot $patchRoot)) {
        if (!$recoveryEntries.ContainsKey($entry.RelativePath) -and (Test-AtGKnownPatchOnlyArtifact $entry.RelativePath)) {
            $legacyPatchOnlyEntries += [pscustomobject]@{
                RelativePath   = $entry.RelativePath
                HadOriginal    = $false
                OriginalSha256 = $null
                PatchSha256    = $entry.PatchSha256
                RecoverySource = 'KnownPatchOnlyRecovery'
            }
        }
    }
}
foreach ($entry in $legacyPatchOnlyEntries) {
    Add-AtGRecoveryEntry $entry
}

$restoredCount = 0
$removedCount = 0
foreach ($entry in @($recoveryEntries.Values | Sort-Object RelativePath)) {
    $relative = [string]$entry.RelativePath
    $target = Join-AtGRelativePath $GamePath $relative
    $backup = Join-AtGRelativePath $backupRoot $relative

    if ($entry.HadOriginal) {
        if (!(Test-Path -LiteralPath $backup -PathType Leaf)) {
            throw "Backup file missing for uninstall recovery: $backup"
        }

        $backupHash = Get-AtGFileSha256 -Path $backup
        if (![string]::IsNullOrWhiteSpace($entry.OriginalSha256) -and $backupHash -ne $entry.OriginalSha256) {
            throw "Backup hash changed since install for: $relative"
        }

        $targetDirectory = Split-Path -Parent $target
        if ($targetDirectory) {
            New-Item -ItemType Directory -Force -Path $targetDirectory | Out-Null
        }
        Copy-Item -LiteralPath $backup -Destination $target -Force
        if ((Get-AtGFileSha256 -Path $target) -ne $backupHash) {
            throw "Uninstall did not restore the original file exactly: $relative"
        }
        $restoredCount++
    }
    else {
        if (Test-Path -LiteralPath $target -PathType Container) {
            throw "Refusing to remove a directory where a patch file is expected: $target"
        }
        if (Test-Path -LiteralPath $target -PathType Leaf) {
            Remove-Item -LiteralPath $target -Force
            $removedCount++
        }
        if (Test-Path -LiteralPath $target) {
            throw "Uninstall did not remove patch-only file: $relative"
        }
    }
}

if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
    Remove-Item -LiteralPath $manifestPath -Force
}

Write-Host "Chinese patch uninstall verification passed. Restored $restoredCount original file(s) and removed $removedCount patch-only file(s)."
if ($usedOrphanRecovery -or $backupEntries.Count -gt $manifestEntries.Count -or $legacyPatchOnlyEntries.Count -gt 0) {
    Write-Host "Recovery inventory included $($backupEntries.Count) backup file(s) and $($legacyPatchOnlyEntries.Count) known patch-only file(s)."
}
Write-Host "Chinese patch uninstalled. Restored from: $backupRoot"

if (!$NoSaveNameNotice) {
    Show-AtGSaveNameCompatibilityNotice -RenamedSaves $renamedSaves
}
