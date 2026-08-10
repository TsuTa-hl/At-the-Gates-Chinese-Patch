param(
    [string]$TempRoot = "$PSScriptRoot\..\.tmp\patch-uninstall-completeness-tests"
)

$ErrorActionPreference = "Stop"

function Assert-AtG {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (!$Condition) {
        throw $Message
    }
}

function Write-AtGFixtureFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Value
    )

    $directory = Split-Path -Parent $Path
    if ($directory) {
        New-Item -ItemType Directory -Force -Path $directory | Out-Null
    }
    [IO.File]::WriteAllText($Path, $Value, (New-Object System.Text.UTF8Encoding($false)))
}

function Get-AtGFixtureSnapshot {
    param(
        [Parameter(Mandatory = $true)][string]$Root
    )

    $resolvedRoot = (Resolve-Path -LiteralPath $Root).Path.TrimEnd([char[]]@('\', '/'))
    $snapshot = @{}
    foreach ($file in @(Get-ChildItem -LiteralPath $resolvedRoot -Recurse -File | Sort-Object FullName)) {
        $relative = $file.FullName.Substring($resolvedRoot.Length).TrimStart([char[]]@('\', '/'))
        if ($relative -eq '.atg-chinese-patch.json' -or
            $relative.StartsWith('_ChinesePatchBackup\', [System.StringComparison]::OrdinalIgnoreCase) -or
            $relative.StartsWith('Saved Games\', [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }
        $snapshot[$relative] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    }

    return $snapshot
}

function Assert-AtGFixtureSnapshotEqual {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Expected,
        [Parameter(Mandatory = $true)][hashtable]$Actual,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $allPaths = @(@($Expected.Keys) + @($Actual.Keys) | Sort-Object -Unique)
    $differences = @()
    foreach ($path in $allPaths) {
        if (!$Expected.ContainsKey($path)) {
            $differences += "unexpected $path"
        }
        elseif (!$Actual.ContainsKey($path)) {
            $differences += "missing $path"
        }
        elseif ($Expected[$path] -ne $Actual[$path]) {
            $differences += "hash mismatch $path"
        }
    }

    Assert-AtG ($differences.Count -eq 0) "$Label did not restore the fake game exactly: $($differences -join '; ')"
}

function Initialize-AtGFixtureGame {
    param(
        [Parameter(Mandatory = $true)][string]$GameRoot,
        [Parameter(Mandatory = $true)][object[]]$Inventory,
        [switch]$AllTargetsHaveOriginal
    )

    New-Item -ItemType Directory -Force -Path $GameRoot | Out-Null
    $index = 0
    foreach ($entry in $Inventory) {
        $relative = [string]$entry.RelativePath
        $mustHaveOriginal = $relative -in @('At The Gates.exe', 'Content\Text\English.xml', 'AtTheGatesCommon.dll')
        $hasOriginal = $AllTargetsHaveOriginal -or $mustHaveOriginal -or (!$((Test-AtGKnownPatchOnlyArtifact $relative)) -and ($index % 2 -eq 0))
        if ($hasOriginal) {
            Write-AtGFixtureFile -Path (Join-AtGRelativePath $GameRoot $relative) -Value "original::$relative"
        }
        $index++
    }
}

if (Test-Path -LiteralPath $TempRoot) {
    Remove-Item -LiteralPath $TempRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $TempRoot | Out-Null

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $repoRoot 'tools\AtGPaths.ps1')
. (Join-Path $repoRoot 'tools\AtGPatchManifest.ps1')

$patchRoot = Join-Path $repoRoot 'patch'
$inventory = @(Get-AtGPatchInventory -PatchRoot $patchRoot)
Assert-AtG ($inventory.Count -gt 0) 'Patch inventory is empty.'

$inventoryByPath = @{}
foreach ($entry in $inventory) {
    $inventoryByPath[[string]$entry.RelativePath] = $entry
}

$gameRoot = Join-Path $TempRoot 'FakeGame'
Initialize-AtGFixtureGame -GameRoot $gameRoot -Inventory $inventory
$baseline = Get-AtGFixtureSnapshot -Root $gameRoot

& (Join-Path $repoRoot 'Install-ChinesePatch.ps1') -GamePath $gameRoot -NoInstallNotice
if (-not $?) {
    throw 'Initial fake-game installation failed.'
}

$manifestPath = Join-Path $gameRoot '.atg-chinese-patch.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-AtG ($manifest.SchemaVersion -eq 3) 'Install manifest did not use the transactional recovery schema.'
Assert-AtG ($manifest.InstallState -eq 'Installed') 'Install manifest was not finalized after all patch files copied.'
Assert-AtG (@($manifest.Files).Count -eq $inventory.Count) 'Install manifest does not enumerate every current patch file.'

$manifestByPath = @{}
foreach ($entry in @($manifest.Files)) {
    $manifestByPath[[string]$entry.RelativePath] = $entry
}
foreach ($entry in $inventory) {
    $relative = [string]$entry.RelativePath
    Assert-AtG ($manifestByPath.ContainsKey($relative)) "Install manifest is missing: $relative"
    Assert-AtG ($manifestByPath[$relative].PatchSha256 -eq $entry.PatchSha256) "Install manifest hash is missing or incorrect: $relative"
    Assert-AtG ($manifestByPath[$relative].BackupRelativePath -eq $relative) "Install manifest backup location is missing or incorrect: $relative"
    Assert-AtG ($manifestByPath[$relative].TransactionState -eq 'Installed') "Install manifest did not finalize file state: $relative"
    $target = Join-AtGRelativePath $gameRoot $relative
    Assert-AtG ((Get-AtGFileSha256 -Path $target) -eq $entry.PatchSha256) "Installed patch file hash does not match: $relative"
}

& (Join-Path $repoRoot 'Uninstall-ChinesePatch.ps1') -GamePath $gameRoot -SkipSaveNameCompatibility -NoSaveNameNotice
if (-not $?) {
    throw 'Complete-manifest fake-game uninstall failed.'
}
Assert-AtG (!(Test-Path -LiteralPath $manifestPath)) 'Complete-manifest uninstall left a manifest behind.'
Assert-AtG (!(Test-Path -LiteralPath (Join-Path $gameRoot '_ChinesePatchBackup'))) 'Complete-manifest uninstall left a transaction backup behind.'
Assert-AtGFixtureSnapshotEqual -Expected $baseline -Actual (Get-AtGFixtureSnapshot -Root $gameRoot) -Label 'Complete-manifest uninstall'

# Reproduce the exact terminal state behind the 2026-08-07 main-menu crash:
# all game files are already restored and the backup is gone, but an old
# manifest still claims Installed.  Direct uninstall must discard only that
# proven-stale marker, and the next install must recreate the runtime artifact.
function Write-AtGStaleRestoredManifest {
    param([string]$Path, [object]$InstalledManifest)

    $stale = $InstalledManifest | ConvertTo-Json -Depth 8 | ConvertFrom-Json
    $stale.InstallState = 'Installed'
    foreach ($entry in @($stale.Files)) {
        $entry.TransactionState = 'Restored'
        $entry.Installed = $null
    }
    Write-AtGPatchManifest -ManifestPath $Path -Manifest $stale
    return $stale
}

$staleRestoredManifest = Write-AtGStaleRestoredManifest -Path $manifestPath -InstalledManifest $manifest
Assert-AtG (Test-AtGManifestRestoredState -GamePath $gameRoot -Manifest $staleRestoredManifest) 'Stale-restored fixture does not prove its files are already back to baseline.'
& (Join-Path $repoRoot 'Uninstall-ChinesePatch.ps1') -GamePath $gameRoot -SkipSaveNameCompatibility -NoSaveNameNotice
if (-not $?) {
    throw 'Terminal stale-manifest cleanup failed.'
}
Assert-AtG (!(Test-Path -LiteralPath $manifestPath)) 'Terminal stale-manifest cleanup retained its marker.'
Assert-AtGFixtureSnapshotEqual -Expected $baseline -Actual (Get-AtGFixtureSnapshot -Root $gameRoot) -Label 'Terminal stale-manifest cleanup'

$staleRestoredManifest = Write-AtGStaleRestoredManifest -Path $manifestPath -InstalledManifest $manifest
& (Join-Path $repoRoot 'Install-ChinesePatch.ps1') -GamePath $gameRoot -NoInstallNotice
if (-not $?) {
    throw 'Refresh from terminal stale manifest failed.'
}
$refreshedManifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-AtG (Test-AtGManifestInstalledState -GamePath $gameRoot -Manifest $refreshedManifest) 'Refresh from terminal stale manifest did not restore a complete installed transaction.'
Assert-AtG ((Get-AtGFileSha256 -Path (Join-AtGRelativePath $gameRoot 'AtG.RuntimeText.dll')) -eq $inventoryByPath['AtG.RuntimeText.dll'].PatchSha256) 'Refresh from terminal stale manifest did not restore AtG.RuntimeText.dll.'
& (Join-Path $repoRoot 'Uninstall-ChinesePatch.ps1') -GamePath $gameRoot -SkipSaveNameCompatibility -NoSaveNameNotice
if (-not $?) {
    throw 'Post-refresh stale-manifest fixture uninstall failed.'
}
Assert-AtGFixtureSnapshotEqual -Expected $baseline -Actual (Get-AtGFixtureSnapshot -Root $gameRoot) -Label 'Refresh from terminal stale manifest'

& (Join-Path $repoRoot 'Install-ChinesePatch.ps1') -GamePath $gameRoot -NoInstallNotice
if (-not $?) {
    throw 'Legacy-recovery fake-game installation failed.'
}

$legacyManifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$omittedPaths = @(
    'AtTheGatesCommon.dll',
    'AtG.RuntimeText.dll',
    'Content\Text\AtG.RuntimeText.tsv'
) | Where-Object { $manifestByPath.ContainsKey($_) }
Assert-AtG ($omittedPaths.Count -eq 3) 'Fixture cannot exercise the stale-manifest recovery paths.'
$legacyManifest.Files = @($legacyManifest.Files | Where-Object { $_.RelativePath -notin $omittedPaths })
$legacyManifest.PSObject.Properties.Remove('SchemaVersion')
$legacyManifest.PSObject.Properties.Remove('InstallState')
$legacyManifest.PSObject.Properties.Remove('Prepared')
$legacyManifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

& (Join-Path $repoRoot 'Uninstall-ChinesePatch.ps1') -GamePath $gameRoot -SkipSaveNameCompatibility -NoSaveNameNotice
if (-not $?) {
    throw 'Legacy-manifest recovery uninstall failed.'
}
Assert-AtG (!(Test-Path -LiteralPath $manifestPath)) 'Legacy-manifest recovery left a manifest behind.'
Assert-AtGFixtureSnapshotEqual -Expected $baseline -Actual (Get-AtGFixtureSnapshot -Root $gameRoot) -Label 'Legacy-manifest recovery uninstall'

$modGameRoot = Join-Path $TempRoot 'ModdedGame'
Initialize-AtGFixtureGame -GameRoot $modGameRoot -Inventory $inventory -AllTargetsHaveOriginal
Write-AtGFixtureFile -Path (Join-Path $modGameRoot 'Mods\Unrelated.mod') -Value 'unrelated mod state'
$modBaseline = Get-AtGFixtureSnapshot -Root $modGameRoot
& (Join-Path $repoRoot 'Install-ChinesePatch.ps1') -GamePath $modGameRoot -NoInstallNotice
if (-not $?) {
    throw 'MOD-preservation fake-game installation failed.'
}
$modManifestPath = Join-Path $modGameRoot '.atg-chinese-patch.json'
$modManifest = Get-Content -LiteralPath $modManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-AtG (@($modManifest.Files | Where-Object { -not $_.HadOriginal }).Count -eq 0) 'MOD fixture did not record every affected file as pre-existing.'
& (Join-Path $repoRoot 'Uninstall-ChinesePatch.ps1') -GamePath $modGameRoot -SkipSaveNameCompatibility -NoSaveNameNotice
if (-not $?) {
    throw 'MOD-preservation fake-game uninstall failed.'
}
Assert-AtGFixtureSnapshotEqual -Expected $modBaseline -Actual (Get-AtGFixtureSnapshot -Root $modGameRoot) -Label 'MOD-preservation uninstall'

$patchOnlyGameRoot = Join-Path $TempRoot 'PatchOnlyChangedGame'
Initialize-AtGFixtureGame -GameRoot $patchOnlyGameRoot -Inventory $inventory
$patchOnlyBaseline = Get-AtGFixtureSnapshot -Root $patchOnlyGameRoot
& (Join-Path $repoRoot 'Install-ChinesePatch.ps1') -GamePath $patchOnlyGameRoot -NoInstallNotice
if (-not $?) {
    throw 'Patch-only ownership fixture installation failed.'
}
$patchOnlyManifestPath = Join-Path $patchOnlyGameRoot '.atg-chinese-patch.json'
$patchOnlyManifest = Get-Content -LiteralPath $patchOnlyManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$patchOnlyEntry = @($patchOnlyManifest.Files | Where-Object { $_.PatchExclusive } | Select-Object -First 1)
Assert-AtG ($patchOnlyEntry.Count -eq 1) 'Fixture did not include a patch-exclusive file.'
$patchOnlyRelative = [string]$patchOnlyEntry[0].RelativePath
$patchOnlyTarget = Join-AtGRelativePath $patchOnlyGameRoot $patchOnlyRelative
Write-AtGFixtureFile -Path $patchOnlyTarget -Value 'post-install mod replacement'
$uninstallBlocked = $false
try {
    & (Join-Path $repoRoot 'Uninstall-ChinesePatch.ps1') -GamePath $patchOnlyGameRoot -SkipSaveNameCompatibility -NoSaveNameNotice
}
catch {
    $uninstallBlocked = $true
}
Assert-AtG $uninstallBlocked 'Uninstall removed a patch-exclusive file replaced after installation.'
Assert-AtG (Test-Path -LiteralPath $patchOnlyManifestPath) 'Blocked uninstall discarded its recovery manifest.'
Assert-AtG ((Get-Content -LiteralPath $patchOnlyTarget -Raw -Encoding UTF8).Trim() -eq 'post-install mod replacement') 'Blocked uninstall deleted a post-install MOD file.'
Copy-Item -LiteralPath $inventoryByPath[$patchOnlyRelative].SourcePath -Destination $patchOnlyTarget -Force
& (Join-Path $repoRoot 'Uninstall-ChinesePatch.ps1') -GamePath $patchOnlyGameRoot -SkipSaveNameCompatibility -NoSaveNameNotice
if (-not $?) {
    throw 'Patch-only ownership fixture recovery uninstall failed.'
}
Assert-AtGFixtureSnapshotEqual -Expected $patchOnlyBaseline -Actual (Get-AtGFixtureSnapshot -Root $patchOnlyGameRoot) -Label 'Patch-only ownership recovery uninstall'

Write-Host "Patch install/uninstall completeness regression passed for $($inventory.Count) current patch file(s), including terminal stale-manifest recovery, MOD preservation, and patch-only ownership protection."
