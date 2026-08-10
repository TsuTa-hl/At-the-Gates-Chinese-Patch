param(
    [string]$GamePath,
    [switch]$SkipSaveNameCompatibility,
    [switch]$NoSaveNameNotice
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\tools\AtGPaths.ps1"
. "$PSScriptRoot\tools\AtGFileOps.ps1"
. "$PSScriptRoot\tools\AtGPatchManifest.ps1"
. "$PSScriptRoot\tools\AtGSaveNameCompatibility.ps1"

$GamePath = Resolve-AtGGamePath $GamePath
Assert-AtGGameNotRunning -Operation 'uninstalling the Chinese patch'
$manifestPath = Join-Path $GamePath ".atg-chinese-patch.json"
$backupBasePath = Join-Path $GamePath "_ChinesePatchBackup"
$manifestEntries = @()
$manifest = $null
$usedOrphanRecovery = $false

if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $backupRoot = [string]$manifest.BackupRoot
    if ([string]::IsNullOrWhiteSpace($backupRoot)) {
        throw "Patch manifest does not contain a backup path: $manifestPath"
    }
    if (!(Test-Path -LiteralPath $backupRoot -PathType Container) -and
        (Test-AtGManifestRestoredState -GamePath $GamePath -Manifest $manifest)) {
        # Cleanup completed before its final metadata deletion.  The recorded
        # hashes prove that the original bytes are already back in place, so
        # remove only the stale marker instead of treating it as a broken
        # active transaction.
        Remove-Item -LiteralPath $manifestPath -Force
        if ((Test-Path -LiteralPath $backupBasePath -PathType Container) -and
            @((Get-ChildItem -LiteralPath $backupBasePath -Force)).Count -eq 0) {
            Remove-Item -LiteralPath $backupBasePath -Force
        }

        $renamedSaves = @()
        if (!$SkipSaveNameCompatibility) {
            $renamedSaves = @(Convert-AtGSavedGameNamesForOriginalFonts -GamePath $GamePath)
            foreach ($renamedSave in $renamedSaves) {
                Write-Host "Renamed save for original-font compatibility: $($renamedSave.OldName) -> $($renamedSave.NewName)"
            }
        }

        Write-Host "Chinese patch was already fully restored; removed its stale transaction manifest."
        if (!$NoSaveNameNotice) {
            Show-AtGSaveNameCompatibilityNotice -RenamedSaves $renamedSaves
        }
        return
    }
    $manifestEntries = @(Get-AtGManifestEntries -Manifest $manifest)
    $manifest | Add-Member -NotePropertyName InstallState -NotePropertyValue "Uninstalling" -Force
    $manifest | Add-Member -NotePropertyName LastUpdated -NotePropertyValue (Get-Date).ToString("s") -Force
    Write-AtGPatchManifest -ManifestPath $manifestPath -Manifest $manifest
}
else {
    $backupBase = $backupBasePath
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

$resolvedBackupBase = (Resolve-Path -LiteralPath $backupBasePath).Path.TrimEnd([char[]]@('\', '/'))
$resolvedBackupRoot = (Resolve-Path -LiteralPath $backupRoot).Path.TrimEnd([char[]]@('\', '/'))
if (!$resolvedBackupRoot.StartsWith($resolvedBackupBase + "\", [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Patch backup must stay under the game's _ChinesePatchBackup directory: $backupRoot"
}

function Get-AtGManifestCreatedDirectories {
    param([object]$Manifest)

    if ($null -eq $Manifest -or $null -eq $Manifest.PSObject.Properties['CreatedDirectories']) {
        return @()
    }

    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $directories = @()
    foreach ($value in @($Manifest.CreatedDirectories)) {
        if ($null -eq $value) {
            continue
        }
        $relative = ConvertTo-AtGNormalizedRelativePath ([string]$value)
        if ($seen.Add($relative)) {
            $directories += $relative
        }
    }
    return @($directories)
}

function Update-AtGManifestEntryState {
    param(
        [Parameter(Mandatory = $true)][object]$Manifest,
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$State
    )

    foreach ($file in @($Manifest.Files)) {
        if ([string]::Equals([string]$file.RelativePath, $RelativePath, [System.StringComparison]::OrdinalIgnoreCase)) {
            $file | Add-Member -NotePropertyName TransactionState -NotePropertyValue $State -Force
            $file | Add-Member -NotePropertyName Restored -NotePropertyValue (Get-Date).ToString("s") -Force
            break
        }
    }
    $Manifest | Add-Member -NotePropertyName LastUpdated -NotePropertyValue (Get-Date).ToString("s") -Force
    Write-AtGPatchManifest -ManifestPath $manifestPath -Manifest $Manifest
}

$recoveryEntries = @{}
function Add-AtGRecoveryEntry {
    param(
        [Parameter(Mandatory = $true)][object]$Entry
    )

    $relative = ConvertTo-AtGNormalizedRelativePath ([string]$Entry.RelativePath)
    $candidate = [pscustomobject]@{
        RelativePath       = $relative
        HadOriginal        = [bool]$Entry.HadOriginal
        OriginalSha256     = [string]$Entry.OriginalSha256
        BackupRelativePath = if ($null -ne $Entry.PSObject.Properties['BackupRelativePath']) {
            ConvertTo-AtGNormalizedRelativePath ([string]$Entry.BackupRelativePath)
        } else {
            $relative
        }
        PatchSha256        = [string]$Entry.PatchSha256
        PatchExclusive     = if ($null -ne $Entry.PSObject.Properties['PatchExclusive']) {
            [bool]$Entry.PatchExclusive
        } else {
            -not [bool]$Entry.HadOriginal
        }
        TransactionState   = if ($null -ne $Entry.PSObject.Properties['TransactionState']) {
            [string]$Entry.TransactionState
        } else {
            'Legacy'
        }
        RecoverySource     = [string]$Entry.RecoverySource
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
$patchInventoryByPath = @{}
if (Test-Path -LiteralPath $patchRoot -PathType Container) {
    foreach ($entry in @(Get-AtGPatchInventory -PatchRoot $patchRoot)) {
        $patchInventoryByPath[[string]$entry.RelativePath] = $entry
        if (!$recoveryEntries.ContainsKey($entry.RelativePath) -and (Test-AtGKnownPatchOnlyArtifact $entry.RelativePath)) {
            Add-AtGRecoveryEntry ([pscustomobject]@{
                    RelativePath = $entry.RelativePath
                    HadOriginal = $false
                    OriginalSha256 = $null
                    BackupRelativePath = $entry.RelativePath
                    PatchSha256 = $entry.PatchSha256
                    PatchExclusive = $true
                    TransactionState = 'LegacyPatchInventory'
                    RecoverySource = 'KnownPatchOnlyRecovery'
                })
        }
    }
}

foreach ($legacyEntry in @(Get-AtGLegacyPatchOnlyEntries)) {
    $relative = ConvertTo-AtGNormalizedRelativePath ([string]$legacyEntry.RelativePath)
    if (!$recoveryEntries.ContainsKey($relative)) {
        $knownPatchHash = if ($patchInventoryByPath.ContainsKey($relative)) { [string]$patchInventoryByPath[$relative].PatchSha256 } else { $null }
        Add-AtGRecoveryEntry ([pscustomobject]@{
                RelativePath = $relative
                HadOriginal = $false
                OriginalSha256 = $null
                BackupRelativePath = $relative
                PatchSha256 = $knownPatchHash
                PatchExclusive = $true
                TransactionState = 'HistoricalRegistry'
                RecoverySource = [string]$legacyEntry.Reason
            })
    }
}

# The old package used generated Chinese ClanCard directory names.  Scan that
# narrow ownership namespace so a corrupt old manifest cannot strand aliases.
$legacyClanCardRoot = Join-Path $GamePath "Content\Images\Interface\ScreenSpecific\ClanCard"
if (Test-Path -LiteralPath $legacyClanCardRoot -PathType Container) {
    $gameRootFull = (Resolve-Path -LiteralPath $GamePath).Path.TrimEnd([char[]]@('\', '/'))
    foreach ($file in @(Get-ChildItem -LiteralPath $legacyClanCardRoot -Recurse -File -ErrorAction SilentlyContinue)) {
        $relative = ConvertTo-AtGNormalizedRelativePath ($file.FullName.Substring($gameRootFull.Length).TrimStart([char[]]@('\', '/')))
        if ((Test-AtGKnownPatchOnlyArtifact $relative) -and !$recoveryEntries.ContainsKey($relative)) {
            Add-AtGRecoveryEntry ([pscustomobject]@{
                    RelativePath = $relative
                    HadOriginal = $false
                    OriginalSha256 = $null
                    BackupRelativePath = $relative
                    PatchSha256 = $null
                    PatchExclusive = $true
                    TransactionState = 'HistoricalRegistry'
                    RecoverySource = 'HistoricalClanCardAlias'
                })
        }
    }
}

$restoredCount = 0
$removedCount = 0
foreach ($entry in @($recoveryEntries.Values | Sort-Object RelativePath)) {
    $relative = [string]$entry.RelativePath
    $target = Join-AtGRelativePath $GamePath $relative
    $backup = Join-AtGRelativePath $backupRoot ([string]$entry.BackupRelativePath)

    if ($entry.HadOriginal) {
        if (!(Test-Path -LiteralPath $backup -PathType Leaf)) {
            throw "Backup file missing for uninstall recovery: $backup"
        }

        $backupHash = Get-AtGFileSha256 -Path $backup
        if (![string]::IsNullOrWhiteSpace($entry.OriginalSha256) -and $backupHash -ne $entry.OriginalSha256) {
            throw "Backup hash changed since install for: $relative"
        }

        Copy-AtGFileIfChanged -Source $backup -Destination $target | Out-Null
        if ((Get-AtGFileSha256 -Path $target) -ne $backupHash) {
            throw "Uninstall did not restore the original file exactly: $relative"
        }
        $restoredCount++
    }
    else {
        if (!$entry.PatchExclusive) {
            throw "Manifest incorrectly marks a non-original file as non-exclusive: $relative"
        }
        if (Test-Path -LiteralPath $target -PathType Container) {
            throw "Refusing to remove a directory where a patch file is expected: $target"
        }
        if (Test-Path -LiteralPath $target -PathType Leaf) {
            $actualHash = Get-AtGFileSha256 -Path $target
            # New transaction manifests retain a patch hash. Do not erase a
            # file a player or MOD replaced after installation; leave the
            # transaction recoverable and ask for a manual decision instead.
            if (![string]::IsNullOrWhiteSpace($entry.PatchSha256) -and $actualHash -ne $entry.PatchSha256) {
                throw "Patch-only file changed after installation; refusing to delete it: $relative"
            }
            Remove-Item -LiteralPath $target -Force
            $removedCount++
        }
        if (Test-Path -LiteralPath $target) {
            throw "Uninstall did not remove patch-only file: $relative"
        }
    }

    if ($null -ne $manifest) {
        Update-AtGManifestEntryState -Manifest $manifest -RelativePath $relative -State "Restored"
    }
}

foreach ($relativeDirectory in @(Get-AtGManifestCreatedDirectories -Manifest $manifest | Sort-Object Length -Descending)) {
    $directory = Join-AtGRelativePath $GamePath $relativeDirectory
    if ((Test-Path -LiteralPath $directory -PathType Container) -and
        @((Get-ChildItem -LiteralPath $directory -Force -ErrorAction Stop)).Count -eq 0) {
        Remove-Item -LiteralPath $directory -Force
    }
}

if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
    Remove-Item -LiteralPath $manifestPath -Force
}
Remove-Item -LiteralPath $backupRoot -Recurse -Force
if ((Test-Path -LiteralPath $backupBasePath -PathType Container) -and
    @((Get-ChildItem -LiteralPath $backupBasePath -Force)).Count -eq 0) {
    Remove-Item -LiteralPath $backupBasePath -Force
}

$renamedSaves = @()
if (!$SkipSaveNameCompatibility) {
    $renamedSaves = @(Convert-AtGSavedGameNamesForOriginalFonts -GamePath $GamePath)
    foreach ($renamedSave in $renamedSaves) {
        Write-Host "Renamed save for original-font compatibility: $($renamedSave.OldName) -> $($renamedSave.NewName)"
    }
}

Write-Host "Chinese patch uninstall verification passed. Restored $restoredCount original file(s) and removed $removedCount patch-only file(s)."
if ($usedOrphanRecovery -or $backupEntries.Count -gt $manifestEntries.Count) {
    Write-Host "Recovery inventory included $($backupEntries.Count) backup file(s)."
}
Write-Host "Chinese patch uninstalled and transaction backup removed."

if (!$NoSaveNameNotice) {
    Show-AtGSaveNameCompatibilityNotice -RenamedSaves $renamedSaves
}
