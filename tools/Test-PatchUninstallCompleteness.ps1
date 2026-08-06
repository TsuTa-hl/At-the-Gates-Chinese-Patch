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
        [Parameter(Mandatory = $true)][object[]]$Inventory
    )

    New-Item -ItemType Directory -Force -Path $GameRoot | Out-Null
    $index = 0
    foreach ($entry in $Inventory) {
        $relative = [string]$entry.RelativePath
        $mustHaveOriginal = $relative -in @('At The Gates.exe', 'Content\Text\English.xml', 'AtTheGatesCommon.dll')
        $hasOriginal = $mustHaveOriginal -or (!$((Test-AtGKnownPatchOnlyArtifact $relative)) -and ($index % 2 -eq 0))
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
Assert-AtG ($manifest.SchemaVersion -eq 2) 'Install manifest did not use the complete-recovery schema.'
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
    $target = Join-AtGRelativePath $gameRoot $relative
    Assert-AtG ((Get-AtGFileSha256 -Path $target) -eq $entry.PatchSha256) "Installed patch file hash does not match: $relative"
}

& (Join-Path $repoRoot 'Uninstall-ChinesePatch.ps1') -GamePath $gameRoot -SkipSaveNameCompatibility -NoSaveNameNotice
if (-not $?) {
    throw 'Complete-manifest fake-game uninstall failed.'
}
Assert-AtG (!(Test-Path -LiteralPath $manifestPath)) 'Complete-manifest uninstall left a manifest behind.'
Assert-AtGFixtureSnapshotEqual -Expected $baseline -Actual (Get-AtGFixtureSnapshot -Root $gameRoot) -Label 'Complete-manifest uninstall'

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

Write-Host "Patch install/uninstall completeness regression passed for $($inventory.Count) current patch file(s), including stale-manifest recovery."
