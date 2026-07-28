[CmdletBinding()]
param(
    [ValidateSet("All", "KnownTexts", "Composite", "Todo")]
    [string[]]$View = @("All"),

    [string]$OutputDirectory = ""
)

$ErrorActionPreference = "Stop"

function Get-AtGFullPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$RepositoryRoot
    )

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $RepositoryRoot $Path))
}

function Test-AtGPathWithin {
    param(
        [Parameter(Mandatory = $true)][string]$Candidate,
        [Parameter(Mandatory = $true)][string]$Parent
    )

    $normalizedCandidate = [System.IO.Path]::GetFullPath($Candidate).TrimEnd([char[]]"\\/")
    $normalizedParent = [System.IO.Path]::GetFullPath($Parent).TrimEnd([char[]]"\\/")
    return $normalizedCandidate.Equals($normalizedParent, [System.StringComparison]::OrdinalIgnoreCase) -or
        $normalizedCandidate.StartsWith($normalizedParent + [System.IO.Path]::DirectorySeparatorChar,
            [System.StringComparison]::OrdinalIgnoreCase)
}

function Assert-AtGSourceFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (!(Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required review source data was not found: $Path"
    }
}

$repositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = ".tmp\review-views"
}
$resolvedOutputDirectory = Get-AtGFullPath -Path $OutputDirectory -RepositoryRoot $repositoryRoot

# Views are disposable CSV files. Keep their output outside every source-data and
# documentation root that this script reads from.
$protectedRoots = @(
    (Join-Path $repositoryRoot "docs\review"),
    (Join-Path $repositoryRoot "docs\agent"),
    (Join-Path $repositoryRoot "translations"),
    (Join-Path $repositoryRoot "source"),
    (Join-Path $repositoryRoot "patch"),
    (Join-Path $repositoryRoot ".cache")
)
foreach ($protectedRoot in $protectedRoots) {
    if (Test-AtGPathWithin -Candidate $resolvedOutputDirectory -Parent $protectedRoot) {
        throw "Review view output must be outside source-data/documentation roots: $resolvedOutputDirectory"
    }
}

$selected = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
foreach ($item in @($View)) {
    if ($item -eq "All") {
        [void]$selected.Add("KnownTexts")
        [void]$selected.Add("Composite")
        [void]$selected.Add("Todo")
    }
    else {
        [void]$selected.Add($item)
    }
}

$needsKnownTexts = $selected.Contains("KnownTexts")
$needsComposite = $selected.Contains("Composite")
$needsTodo = $selected.Contains("Todo")

New-Item -ItemType Directory -Force -Path $resolvedOutputDirectory | Out-Null

$catalogDatabasePath = Join-Path $repositoryRoot ".cache\atg-catalog.sqlite"
$compositeRulesPath = Join-Path $repositoryRoot "translations\composite-text-rules.json"
$patchCliPath = Join-Path $repositoryRoot "tools\Invoke-AtGPatchCli.ps1"
$todoExporterPath = Join-Path $repositoryRoot "tools\Export-LocalizationTodoList.ps1"
$knownTextsCsvPath = Join-Path $resolvedOutputDirectory "known-texts.csv"
$compositeCsvPath = Join-Path $resolvedOutputDirectory "composite-text-localization.csv"
$todoCsvPath = Join-Path $resolvedOutputDirectory "localization-todolist.csv"

$sourceData = @(
    [pscustomobject]@{
        Name = "Known-text occurrence catalog"
        Path = $catalogDatabasePath
        UsedBy = "KnownTexts, Composite, Todo"
    },
    [pscustomobject]@{
        Name = "Composite rule authority"
        Path = $compositeRulesPath
        UsedBy = "KnownTexts, Composite, Todo"
    },
    [pscustomobject]@{
        Name = "Exact source catalogs outside view generation"
        Path = (Join-Path $repositoryRoot "docs\review\generated")
        UsedBy = "Source refresh and exact patch operands; not read by these CSV views"
    }
)

Push-Location -LiteralPath $repositoryRoot
try {
    if ($needsKnownTexts) {
        Assert-AtGSourceFile -Path $catalogDatabasePath
        Assert-AtGSourceFile -Path $compositeRulesPath
        & $patchCliPath -Command known-texts-csv -RepoRoot $repositoryRoot -CommandArguments @(
            "--database", $catalogDatabasePath,
            "--rules", $compositeRulesPath,
            "--csv", $knownTextsCsvPath
        ) | Out-Host
    }

    if ($needsComposite) {
        Assert-AtGSourceFile -Path $catalogDatabasePath
        Assert-AtGSourceFile -Path $compositeRulesPath
        & $patchCliPath -Command composite-csv -RepoRoot $repositoryRoot -CommandArguments @(
            "--database", $catalogDatabasePath,
            "--rules", $compositeRulesPath,
            "--csv", $compositeCsvPath
        ) | Out-Host
    }

    if ($needsTodo) {
        Assert-AtGSourceFile -Path $catalogDatabasePath
        Assert-AtGSourceFile -Path $compositeRulesPath
        & $todoExporterPath `
            -CatalogDatabasePath $catalogDatabasePath `
            -CompositeRulesPath $compositeRulesPath `
            -OutputPath $todoCsvPath | Out-Host
    }
}
finally {
    Pop-Location
}

$requestedViews = @($selected | Sort-Object)
$outputPaths = @()
if ($needsKnownTexts) { $outputPaths += $knownTextsCsvPath }
if ($needsComposite) { $outputPaths += $compositeCsvPath }
if ($needsTodo) { $outputPaths += $todoCsvPath }

$outputs = @(
    foreach ($path in $outputPaths) {
        if (!(Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Expected review CSV was not generated: $path"
        }
        if (![string]::Equals([System.IO.Path]::GetExtension($path), ".csv", [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Review view must be CSV: $path"
        }
        $item = Get-Item -LiteralPath $path
        [pscustomobject]@{
            Path = $item.FullName
            Bytes = [int64]$item.Length
        }
    }
)

[pscustomobject]@{
    OutputDirectory = $resolvedOutputDirectory
    RequestedViews = $requestedViews
    OutputCount = $outputs.Count
    SourceData = $sourceData
    Outputs = $outputs
}
