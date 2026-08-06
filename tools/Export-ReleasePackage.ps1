param(
    [string]$SourceRoot = (Join-Path $PSScriptRoot ".."),
    [string]$OutputPath = (Join-Path $PSScriptRoot "..\.tmp\release-package"),
    [switch]$Overwrite
)

$ErrorActionPreference = "Stop"

function Get-AtGFullPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    return [IO.Path]::GetFullPath($Path).TrimEnd([char[]]@('\', '/'))
}

function Assert-AtGReleasePackagePath {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Output
    )

    if ($Source -eq $Output -or $Source.StartsWith($Output + "\", [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Release package output must not be the source root or an ancestor of it: $Output"
    }
}

function Expand-AtGReleaseEntryScript {
    param(
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)][string]$OutputRoot,
        [Parameter(Mandatory = $true)][string]$EntryScript,
        [Parameter(Mandatory = $true)][string[]]$Helpers
    )

    $entryPath = Join-Path $SourceRoot $EntryScript
    $content = [IO.File]::ReadAllText($entryPath, [Text.Encoding]::UTF8)
    foreach ($helper in $Helpers) {
        $helperPath = Join-Path $SourceRoot (Join-Path "tools" $helper)
        if (!(Test-Path -LiteralPath $helperPath -PathType Leaf)) {
            throw "Release script helper is missing: $helperPath"
        }

        $needle = '. "$PSScriptRoot\tools\' + $helper + '"'
        if (!$content.Contains($needle)) {
            throw "Release script entry point no longer contains the expected helper import: $needle"
        }

        $helperContent = [IO.File]::ReadAllText($helperPath, [Text.Encoding]::UTF8)
        $replacement = "# Inlined release dependency: $helper" + [Environment]::NewLine + $helperContent
        $content = $content.Replace($needle, $replacement)
    }

    if ($content.Contains('$PSScriptRoot\tools\')) {
        throw "Release script still depends on the development tools directory: $EntryScript"
    }

    $destination = Join-Path $OutputRoot $EntryScript
    [IO.File]::WriteAllText($destination, $content, (New-Object System.Text.UTF8Encoding($true)))
}

$resolvedSourceRoot = Get-AtGFullPath $SourceRoot
$resolvedOutputPath = Get-AtGFullPath $OutputPath
Assert-AtGReleasePackagePath -Source $resolvedSourceRoot -Output $resolvedOutputPath

$patchSource = Join-Path $resolvedSourceRoot "patch"
$readmeSource = Join-Path $resolvedSourceRoot "docs\release\README.md"
foreach ($requiredPath in @(
        $patchSource,
        $readmeSource,
        (Join-Path $resolvedSourceRoot "Install-ChinesePatch.ps1"),
        (Join-Path $resolvedSourceRoot "Uninstall-ChinesePatch.ps1"))) {
    if (!(Test-Path -LiteralPath $requiredPath)) {
        throw "Release package source is missing: $requiredPath"
    }
}

if (Test-Path -LiteralPath $resolvedOutputPath) {
    if (!$Overwrite) {
        throw "Release package output already exists. Choose an empty path or pass -Overwrite: $resolvedOutputPath"
    }
    Remove-Item -LiteralPath $resolvedOutputPath -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $resolvedOutputPath | Out-Null

Copy-Item -LiteralPath $patchSource -Destination (Join-Path $resolvedOutputPath "patch") -Recurse -Force
Copy-Item -LiteralPath $readmeSource -Destination (Join-Path $resolvedOutputPath "README.md") -Force

Expand-AtGReleaseEntryScript -SourceRoot $resolvedSourceRoot -OutputRoot $resolvedOutputPath -EntryScript "Install-ChinesePatch.ps1" -Helpers @(
    "AtGPaths.ps1",
    "AtGPatchManifest.ps1",
    "AtGPatchNotice.ps1"
)
Expand-AtGReleaseEntryScript -SourceRoot $resolvedSourceRoot -OutputRoot $resolvedOutputPath -EntryScript "Uninstall-ChinesePatch.ps1" -Helpers @(
    "AtGPaths.ps1",
    "AtGPatchManifest.ps1",
    "AtGSaveNameCompatibility.ps1"
)

$unexpectedFiles = @()
foreach ($file in @(Get-ChildItem -LiteralPath $resolvedOutputPath -Recurse -File)) {
    $relative = $file.FullName.Substring($resolvedOutputPath.Length).TrimStart([char[]]@('\', '/')) -replace '/', '\'
    if ($relative -notin @("README.md", "Install-ChinesePatch.ps1", "Uninstall-ChinesePatch.ps1") -and
        !$relative.StartsWith("patch\", [System.StringComparison]::OrdinalIgnoreCase)) {
        $unexpectedFiles += $relative
    }
}
if ($unexpectedFiles.Count -gt 0) {
    throw "Release package contains unexpected development files: $($unexpectedFiles -join ', ')"
}

$patchFileCount = @(Get-ChildItem -LiteralPath (Join-Path $resolvedOutputPath "patch") -Recurse -File).Count
if ($patchFileCount -eq 0) {
    throw "Release package has no patch files."
}

[pscustomobject]@{
    SourceRoot     = $resolvedSourceRoot
    OutputPath     = $resolvedOutputPath
    PatchFileCount = $patchFileCount
    EntryScripts   = @("Install-ChinesePatch.ps1", "Uninstall-ChinesePatch.ps1")
}
