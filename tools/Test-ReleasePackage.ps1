param(
    [string]$TempRoot = "$PSScriptRoot\..\.tmp\release-package-tests"
)

$ErrorActionPreference = "Stop"

function Assert-AtG {
    param([bool]$Condition, [string]$Message)

    if (!$Condition) {
        throw $Message
    }
}

function Write-AtGFixtureFile {
    param([string]$Path, [string]$Value)

    $directory = Split-Path -Parent $Path
    if ($directory) {
        New-Item -ItemType Directory -Force -Path $directory | Out-Null
    }
    [IO.File]::WriteAllText($Path, $Value, (New-Object System.Text.UTF8Encoding($false)))
}

function Get-AtGFixtureSnapshot {
    param([string]$Root)

    $resolvedRoot = (Resolve-Path -LiteralPath $Root).Path.TrimEnd([char[]]@('\', '/'))
    $snapshot = @{}
    foreach ($file in @(Get-ChildItem -LiteralPath $resolvedRoot -Recurse -File | Sort-Object FullName)) {
        $relative = $file.FullName.Substring($resolvedRoot.Length).TrimStart([char[]]@('\', '/'))
        if ($relative -eq '.atg-chinese-patch.json' -or $relative.StartsWith('_ChinesePatchBackup\', [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }
        $snapshot[$relative] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    }
    return $snapshot
}

function Assert-AtGSnapshotEqual {
    param([hashtable]$Expected, [hashtable]$Actual)

    $paths = @(@($Expected.Keys) + @($Actual.Keys) | Sort-Object -Unique)
    $differences = @()
    foreach ($path in $paths) {
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
    Assert-AtG ($differences.Count -eq 0) "Release package did not restore the fake game exactly: $($differences -join '; ')"
}

function Get-AtGFileHashMap {
    param([string]$Root)

    $resolvedRoot = (Resolve-Path -LiteralPath $Root).Path.TrimEnd([char[]]@('\', '/'))
    $hashes = @{}
    foreach ($file in @(Get-ChildItem -LiteralPath $resolvedRoot -Recurse -File | Sort-Object FullName)) {
        $relative = $file.FullName.Substring($resolvedRoot.Length).TrimStart([char[]]@('\', '/'))
        $hashes[$relative] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    }
    return $hashes
}

if (Test-Path -LiteralPath $TempRoot) {
    Remove-Item -LiteralPath $TempRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $TempRoot | Out-Null

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $repoRoot 'tools\AtGPatchManifest.ps1')
$packageRoot = Join-Path $TempRoot 'ReleasePackage'
& (Join-Path $repoRoot 'tools\Export-ReleasePackage.ps1') -SourceRoot $repoRoot -OutputPath $packageRoot
if (!$?) {
    throw 'Release package export failed.'
}

$rootFiles = @(Get-ChildItem -LiteralPath $packageRoot -File | Select-Object -ExpandProperty Name | Sort-Object)
Assert-AtG (($rootFiles -join '|') -eq 'Install-ChinesePatch.ps1|README.md|Uninstall-ChinesePatch.ps1') 'Release root contains an unexpected file set.'
Assert-AtG (Test-Path -LiteralPath (Join-Path $packageRoot 'patch') -PathType Container) 'Release package does not contain patch/.'
Assert-AtG (!(Test-Path -LiteralPath (Join-Path $packageRoot 'tools'))) 'Release package must not retain development tools.'
Assert-AtG (!(Test-Path -LiteralPath (Join-Path $packageRoot 'docs'))) 'Release package must not retain development documentation.'

$sourcePatchFiles = @(Get-AtGPatchInventory -PatchRoot (Join-Path $repoRoot 'patch'))
$releasePatchFiles = @(Get-ChildItem -LiteralPath (Join-Path $packageRoot 'patch') -Recurse -File | Sort-Object FullName)
Assert-AtG ($sourcePatchFiles.Count -eq $releasePatchFiles.Count) 'Release package did not retain every patch file.'
$sourcePatchHashes = @{}
foreach ($file in $sourcePatchFiles) {
    $sourcePatchHashes[[string]$file.RelativePath] = [string]$file.PatchSha256
}
$releasePatchHashes = Get-AtGFileHashMap -Root (Join-Path $packageRoot 'patch')
Assert-AtGSnapshotEqual -Expected $sourcePatchHashes -Actual $releasePatchHashes
Assert-AtG (!(Test-Path -LiteralPath (Join-Path $packageRoot 'patch\.atg-build-report.json'))) 'Release package retained build-only metadata in patch/.'

foreach ($scriptName in @('Install-ChinesePatch.ps1', 'Uninstall-ChinesePatch.ps1')) {
    $scriptPath = Join-Path $packageRoot $scriptName
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    Assert-AtG ($parseErrors.Count -eq 0) "Release entry script does not parse: $scriptName"
    $content = [IO.File]::ReadAllText($scriptPath, [Text.Encoding]::UTF8)
    Assert-AtG (!$content.Contains('$PSScriptRoot\tools\')) "Release entry script still depends on tools/: $scriptName"
}
Assert-AtG (Test-Path -LiteralPath (Join-Path $repoRoot 'tools\release-bundle-manifest.json')) 'Release export has no explicit dependency manifest.'

$gameRoot = Join-Path $TempRoot 'FakeGame'
Write-AtGFixtureFile -Path (Join-Path $gameRoot 'At The Gates.exe') -Value 'original executable'
Write-AtGFixtureFile -Path (Join-Path $gameRoot 'Content\Text\English.xml') -Value '<english>original text</english>'
$baseline = Get-AtGFixtureSnapshot -Root $gameRoot

& (Join-Path $packageRoot 'Install-ChinesePatch.ps1') -GamePath $gameRoot -InstallFonts -NoInstallNotice
if (!$?) {
    throw 'Release package fake-game installation failed.'
}
$manifestPath = Join-Path $gameRoot '.atg-chinese-patch.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-AtG (@($manifest.Files).Count -eq $sourcePatchFiles.Count) 'Release installer manifest does not cover the full patch tree.'

& (Join-Path $packageRoot 'Uninstall-ChinesePatch.ps1') -GamePath $gameRoot -SkipSaveNameCompatibility -NoSaveNameNotice
if (!$?) {
    throw 'Release package fake-game uninstall failed.'
}
Assert-AtG (!(Test-Path -LiteralPath $manifestPath)) 'Release package uninstall left a manifest behind.'
Assert-AtGSnapshotEqual -Expected $baseline -Actual (Get-AtGFixtureSnapshot -Root $gameRoot)

Write-Host "Release package export and self-contained install/uninstall checks passed for $($sourcePatchFiles.Count) patch file(s)."
