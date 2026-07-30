[CmdletBinding()]
param(
    [string]$ProjectRoot = "",
    [string]$KnownTextCsvPath = "",
    [string]$OutputDirectory = ".tmp\interface-localization-progress-test",
    [switch]$SkipExport
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}
else {
    $ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
}

function Assert-AtGProgress {
    param([bool]$Condition, [string]$Message)
    if (!$Condition) { throw $Message }
}

function Test-AtGPowerShellFile {
    param([string]$Path)
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    Assert-AtGProgress ($errors.Count -eq 0) "PowerShell parse failed: $Path"
}

$routePath = Join-Path $ProjectRoot 'docs\agent\interface-localization-routes.json'
$exporterPath = Join-Path $ProjectRoot 'tools\Export-InterfaceLocalizationProgress.ps1'
$digestPath = Join-Path $ProjectRoot 'tools\AtGLocalizationInputDigest.ps1'
$buildPath = Join-Path $ProjectRoot 'tools\Build-Patch.ps1'
$reportTestPath = Join-Path $ProjectRoot 'tools\Test-RuntimeBuildReport.ps1'
foreach ($path in @($routePath, $exporterPath, $digestPath, $buildPath, $reportTestPath)) {
    Assert-AtGProgress (Test-Path -LiteralPath $path -PathType Leaf) "Required progress file is missing: $path"
}
foreach ($path in @($exporterPath, $digestPath, $buildPath, $reportTestPath)) { Test-AtGPowerShellFile -Path $path }

$routeLedger = Get-Content -LiteralPath $routePath -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-AtGProgress ([int]$routeLedger.SchemaVersion -eq 1) 'Route ledger must be schema v1.'
$routes = @($routeLedger.Routes)
$routeIds = @($routes | ForEach-Object { [string]$_.RouteId })
Assert-AtGProgress (@($routeIds | Select-Object -Unique).Count -eq @($routeIds).Count) 'Route IDs must be unique.'
Assert-AtGProgress (@($routes | Where-Object { [int]$_.Priority -lt 1 }).Count -eq 0) 'Route priorities must be positive.'
foreach ($route in $routes) {
    foreach ($field in @('RouteId', 'Interface', 'Surface', 'Trigger', 'PlayerVisible', 'NeedsTranslation', 'Match')) {
        Assert-AtGProgress ($null -ne $route.PSObject.Properties[$field]) "Route '$($route.RouteId)' is missing '$field'."
    }
}
$requiredRoutes = @(
    'map-terrain-resource-tooltip', 'clan-trait-config-tooltip', 'tile-tooltip',
    'generic-mouseover-tooltip', 'profession-tooltip', 'clan-tooltip',
    'structure-resource-tooltip', 'selection-context', 'world-notification-context',
    'knowledge-tech-tooltip', 'runtime-final-display'
)
foreach ($routeId in $requiredRoutes) {
    Assert-AtGProgress (@($routeIds | Where-Object { $_ -eq $routeId }).Count -eq 1) "Required route is missing: $routeId"
}

$scriptText = Get-Content -LiteralPath $exporterPath -Raw -Encoding UTF8
Assert-AtGProgress ($scriptText -notmatch 'black-box-scenarios\.json|black-box-tests\.md') 'Progress exporter must not read black-box scenario sources.'

if (!$SkipExport) {
    $resolvedKnownTextPath = $KnownTextCsvPath
    if (![string]::IsNullOrWhiteSpace($resolvedKnownTextPath) -and -not [IO.Path]::IsPathRooted($resolvedKnownTextPath)) {
        $resolvedKnownTextPath = Join-Path $ProjectRoot $resolvedKnownTextPath
    }
    if (![string]::IsNullOrWhiteSpace($resolvedKnownTextPath)) {
        & $exporterPath -ProjectRoot $ProjectRoot -OutputDirectory $OutputDirectory -KnownTextCsvPath $resolvedKnownTextPath | Out-Host
    }
    else {
        & $exporterPath -ProjectRoot $ProjectRoot -OutputDirectory $OutputDirectory | Out-Host
    }
}

$resolvedOutput = if ([IO.Path]::IsPathRooted($OutputDirectory)) { $OutputDirectory } else { Join-Path $ProjectRoot $OutputDirectory }
$summaryPath = Join-Path $resolvedOutput 'interface-localization-summary.csv'
$itemsPath = Join-Path $resolvedOutput 'interface-localization-items.csv'
$metadataPath = Join-Path $resolvedOutput 'interface-localization-metadata.json'
foreach ($path in @($summaryPath, $itemsPath, $metadataPath)) {
    Assert-AtGProgress (Test-Path -LiteralPath $path -PathType Leaf) "Expected progress output is missing: $path"
}

$items = @(Import-Csv -LiteralPath $itemsPath)
$summary = @(Import-Csv -LiteralPath $summaryPath)
$metadata = Get-Content -LiteralPath $metadataPath -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-AtGProgress (@($items).Count -gt 0) 'Progress item CSV must not be empty.'
Assert-AtGProgress (@($summary).Count -gt 0) 'Progress summary CSV must not be empty.'
Assert-AtGProgress (@($items | Select-Object -ExpandProperty ItemId -Unique).Count -eq @($items).Count) 'Progress ItemId values must be unique.'
Assert-AtGProgress ([int]$metadata.Totals.AllKnownCount -eq @($items).Count) 'Metadata AllKnownCount must equal item rows.'
Assert-AtGProgress ([int]$metadata.Totals.UnclassifiedCount -eq @($items | Where-Object RouteId -eq 'Unclassified').Count) 'Metadata UnclassifiedCount must equal item rows.'
Assert-AtGProgress ([int]$metadata.Totals.VisibleLocalizedCount -le [int]$metadata.Totals.VisibleTranslatableCount) 'Localized visible count cannot exceed visible denominator.'
Assert-AtGProgress ([string]$metadata.BuildArtifactState -in @('Current', 'Stale', 'Unavailable')) 'Build artifact state is invalid.'

$tooltipRoutes = @($summary | Where-Object Surface -eq 'Tooltip' | ForEach-Object RouteId)
foreach ($routeId in @('map-terrain-resource-tooltip', 'tile-tooltip', 'generic-mouseover-tooltip', 'profession-tooltip', 'clan-tooltip', 'structure-resource-tooltip', 'knowledge-tech-tooltip')) {
    Assert-AtGProgress (@($tooltipRoutes | Where-Object { $_ -eq $routeId }).Count -eq 1) "Tooltip route missing from summary: $routeId"
}
Assert-AtGProgress (@($summary | Where-Object Surface -eq 'Conditional').Count -gt 0) 'Conditional display summary is missing.'
Assert-AtGProgress (@($summary | Where-Object RouteId -eq 'Unclassified').Count -eq 1) 'Unclassified must have one aggregate summary row.'

Write-Host "Interface localization progress tests passed. Items=$(@($items).Count); Summary=$(@($summary).Count)."
