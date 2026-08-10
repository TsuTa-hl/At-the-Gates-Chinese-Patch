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

function ConvertTo-AtGReleaseRelativePath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $normalized = $Path.Trim().Replace([char]'/', [char]'\')
    if ([IO.Path]::IsPathRooted($normalized) -or $normalized.Split([char[]]@('\')) -contains '..') {
        throw "Release bundle manifest contains an unsafe path: $Path"
    }
    return $normalized
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

function Get-AtGReleaseScriptImports {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string]$SourceRoot
    )

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($FilePath, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) {
        throw "Release dependency source does not parse: $FilePath. $($errors[0].Message)"
    }

    $imports = @()
    $commands = @($ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.CommandAst] -and
                    $node.InvocationOperator -eq [System.Management.Automation.Language.TokenKind]::Dot
            }, $true))
    foreach ($command in $commands) {
        if ($command.CommandElements.Count -ne 1) {
            throw "Release dependency import must have exactly one path argument: $($command.Extent.Text)"
        }
        $argument = $command.CommandElements[0]
        $sourceText = $argument.Extent.Text.Trim()
        if (($sourceText.StartsWith('"') -and $sourceText.EndsWith('"')) -or
            ($sourceText.StartsWith("'") -and $sourceText.EndsWith("'"))) {
            $sourceText = $sourceText.Substring(1, $sourceText.Length - 2)
        }
        $releaseImportPrefix = '$PSScriptRoot\'
        if (!$sourceText.StartsWith($releaseImportPrefix, [System.StringComparison]::Ordinal)) {
            throw "Release dependency import must be a script-root-relative literal: $($command.Extent.Text)"
        }
        $sourceRelativeCandidate = $FilePath.Substring($SourceRoot.Length).TrimStart([char[]]@('\', '/'))
        $sourceRelativePath = ConvertTo-AtGReleaseRelativePath $sourceRelativeCandidate
        $sourceRelativeDirectory = Split-Path -Parent $sourceRelativePath
        $importTail = $sourceText.Substring($releaseImportPrefix.Length)
        $relative = if ([string]::IsNullOrWhiteSpace($sourceRelativeDirectory)) {
            ConvertTo-AtGReleaseRelativePath $importTail
        } else {
            ConvertTo-AtGReleaseRelativePath (Join-Path $sourceRelativeDirectory $importTail)
        }
        $candidate = Join-Path $SourceRoot $relative
        if (!(Test-Path -LiteralPath $candidate -PathType Leaf)) {
            throw "Release dependency source is missing: $candidate"
        }
        $imports += [pscustomobject]@{
            RelativePath = $relative
            SourceText = $command.Extent.Text
        }
    }
    return @($imports)
}

function Expand-AtGReleaseScript {
    param(
        [Parameter(Mandatory = $true)][string]$EntryRelativePath,
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)][string[]]$DeclaredDependencies
    )

    $allowed = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($dependency in $DeclaredDependencies) {
        [void]$allowed.Add((ConvertTo-AtGReleaseRelativePath $dependency))
    }
    $discovered = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $active = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

    function Expand-AtGReleaseDependency {
        param(
            [Parameter(Mandatory = $true)][string]$RelativePath,
            [Parameter(Mandatory = $true)][string]$Root,
            [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.HashSet[string]]$Allowed,
            [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.HashSet[string]]$Discovered,
            [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.HashSet[string]]$Active
        )

        if (!$Active.Add($RelativePath)) {
            throw "Release dependency cycle detected at: $RelativePath"
        }
        try {
            if ([string]::IsNullOrWhiteSpace($RelativePath)) {
                throw "Release dependency expansion received an empty relative path."
            }
            if ([string]::IsNullOrWhiteSpace($Root)) {
                throw "Release dependency expansion received an empty source root for: $RelativePath"
            }
            $sourcePath = Join-Path -Path $Root -ChildPath ([string]$RelativePath)
            $content = [IO.File]::ReadAllText($sourcePath, [Text.Encoding]::UTF8)
            $imports = @(Get-AtGReleaseScriptImports -FilePath ([string]$sourcePath) -SourceRoot ([string]$Root))
            foreach ($import in $imports) {
                if (!$Allowed.Contains($import.RelativePath)) {
                    throw "Release dependency '$($import.RelativePath)' is not declared for $EntryRelativePath."
                }
                [void]$Discovered.Add($import.RelativePath)
                $expanded = Expand-AtGReleaseDependency -RelativePath $import.RelativePath -Root $Root -Allowed $Allowed -Discovered $Discovered -Active $Active
                $replacement = "# Inlined release dependency: $($import.RelativePath)" + [Environment]::NewLine + $expanded
                if (!$content.Contains($import.SourceText)) {
                    throw "Could not replace declared release import: $($import.SourceText)"
                }
                $content = $content.Replace($import.SourceText, $replacement)
            }
            return $content
        }
        finally {
            [void]$Active.Remove($RelativePath)
        }
    }

    $entry = ConvertTo-AtGReleaseRelativePath $EntryRelativePath
    $content = Expand-AtGReleaseDependency -RelativePath $entry -Root $SourceRoot -Allowed $allowed -Discovered $discovered -Active $active
    $missingDeclarations = @($allowed | Where-Object { !$discovered.Contains($_) })
    $undeclaredImports = @($discovered | Where-Object { !$allowed.Contains($_) })
    if ($missingDeclarations.Count -gt 0 -or $undeclaredImports.Count -gt 0) {
        throw "Release dependency manifest does not exactly match $EntryRelativePath. Missing=$($missingDeclarations -join ', '); undeclared=$($undeclaredImports -join ', ')"
    }
    if ($content.Contains('$PSScriptRoot\tools\')) {
        throw "Release entry script still depends on the development tools directory: $EntryRelativePath"
    }

    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($content, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) {
        throw "Expanded release script does not parse: $EntryRelativePath. $($errors[0].Message)"
    }
    return $content
}

$resolvedSourceRoot = Get-AtGFullPath $SourceRoot
$resolvedOutputPath = Get-AtGFullPath $OutputPath
Assert-AtGReleasePackagePath -Source $resolvedSourceRoot -Output $resolvedOutputPath

$bundleManifestPath = Join-Path $resolvedSourceRoot "tools\release-bundle-manifest.json"
if (!(Test-Path -LiteralPath $bundleManifestPath -PathType Leaf)) {
    throw "Release bundle manifest is missing: $bundleManifestPath"
}
$bundleManifest = Get-Content -LiteralPath $bundleManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([int]$bundleManifest.SchemaVersion -ne 1 -or @($bundleManifest.Entries).Count -eq 0) {
    throw "Release bundle manifest has an unsupported schema or no entry scripts."
}

$patchSource = Join-Path $resolvedSourceRoot "patch"
$readmeSource = Join-Path $resolvedSourceRoot "docs\release\README.md"
foreach ($requiredPath in @(
        $patchSource,
        $readmeSource)) {
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

. (Join-Path $resolvedSourceRoot "tools\AtGPatchManifest.ps1")
$patchDestination = Join-Path $resolvedOutputPath "patch"
foreach ($file in @(Get-AtGPatchInventory -PatchRoot $patchSource)) {
    $destination = Join-Path $patchDestination ([string]$file.RelativePath)
    $destinationDirectory = Split-Path -Parent $destination
    if ($destinationDirectory) {
        New-Item -ItemType Directory -Force -Path $destinationDirectory | Out-Null
    }
    Copy-Item -LiteralPath $file.SourcePath -Destination $destination -Force
    if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ne [string]$file.PatchSha256) {
        throw "Release package copy hash mismatch: $($file.RelativePath)"
    }
}
Copy-Item -LiteralPath $readmeSource -Destination (Join-Path $resolvedOutputPath "README.md") -Force

foreach ($entry in @($bundleManifest.Entries)) {
    $entryScript = ConvertTo-AtGReleaseRelativePath ([string]$entry.EntryScript)
    $entryPath = Join-Path $resolvedSourceRoot $entryScript
    if (!(Test-Path -LiteralPath $entryPath -PathType Leaf)) {
        throw "Release entry script is missing: $entryPath"
    }
    $content = Expand-AtGReleaseScript -EntryRelativePath $entryScript -SourceRoot $resolvedSourceRoot -DeclaredDependencies @($entry.Dependencies | ForEach-Object { [string]$_ })
    [IO.File]::WriteAllText((Join-Path $resolvedOutputPath $entryScript), $content, [Text.UTF8Encoding]::new($false))
}

$allowedRootFiles = @($bundleManifest.ReleaseRootFiles | ForEach-Object { [string]$_ })
$unexpectedFiles = @()
foreach ($file in @(Get-ChildItem -LiteralPath $resolvedOutputPath -Recurse -File)) {
    $relative = $file.FullName.Substring($resolvedOutputPath.Length).TrimStart([char[]]@('\', '/')) -replace '/', '\'
    if ($relative -notin $allowedRootFiles -and !$relative.StartsWith("patch\", [System.StringComparison]::OrdinalIgnoreCase)) {
        $unexpectedFiles += $relative
    }
}
if ($unexpectedFiles.Count -gt 0) {
    throw "Release package contains unexpected development files: $($unexpectedFiles -join ', ')"
}

$patchFileCount = @(Get-ChildItem -LiteralPath $patchDestination -Recurse -File).Count
if ($patchFileCount -eq 0) {
    throw "Release package has no patch files."
}

[pscustomobject]@{
    SourceRoot     = $resolvedSourceRoot
    OutputPath     = $resolvedOutputPath
    PatchFileCount = $patchFileCount
    EntryScripts   = @($bundleManifest.Entries | ForEach-Object { [string]$_.EntryScript })
}
