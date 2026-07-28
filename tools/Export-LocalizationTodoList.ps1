[CmdletBinding()]
param(
    [string]$CatalogDatabasePath = "$PSScriptRoot\..\.cache\atg-catalog.sqlite",
    [string]$CompositeRulesPath = "$PSScriptRoot\..\translations\composite-text-rules.json",
    [string]$OutputPath = "$PSScriptRoot\..\.tmp\review-views\localization-todolist.csv"
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

$repositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$resolvedCatalogDatabasePath = Get-AtGFullPath -Path $CatalogDatabasePath -RepositoryRoot $repositoryRoot
$resolvedCompositeRulesPath = Get-AtGFullPath -Path $CompositeRulesPath -RepositoryRoot $repositoryRoot
$resolvedOutputPath = Get-AtGFullPath -Path $OutputPath -RepositoryRoot $repositoryRoot

foreach ($sourcePath in @($resolvedCatalogDatabasePath, $resolvedCompositeRulesPath)) {
    if (!(Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        throw "Required todo source data was not found: $sourcePath"
    }
}

if (![string]::Equals([System.IO.Path]::GetExtension($resolvedOutputPath), ".csv", [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Localization todo output must be a CSV file: $resolvedOutputPath"
}

$patchCliPath = Join-Path $repositoryRoot "tools\Invoke-AtGPatchCli.ps1"
& $patchCliPath -Command todo-csv -RepoRoot $repositoryRoot -CommandArguments @(
    "--database", $resolvedCatalogDatabasePath,
    "--rules", $resolvedCompositeRulesPath,
    "--csv", $resolvedOutputPath
) | Out-Host

if (!(Test-Path -LiteralPath $resolvedOutputPath -PathType Leaf)) {
    throw "Localization todo CSV was not generated: $resolvedOutputPath"
}

[pscustomobject]@{
    OutputPath = $resolvedOutputPath
    CatalogDatabasePath = $resolvedCatalogDatabasePath
    CompositeRulesPath = $resolvedCompositeRulesPath
}
