param(
    [string]$OutputPath = "$PSScriptRoot\..\.tmp\localization-todolist-test\localization-todolist.csv"
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
if (![string]::Equals([System.IO.Path]::GetExtension($OutputPath), ".csv", [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Localization todo test output must be CSV: $OutputPath"
}

$outputDirectory = Split-Path -Parent $OutputPath
$reviewViewGeneratorPath = Join-Path $repoRoot "docs\review\Generate-ReviewViews.ps1"
$compositeRulesPath = Join-Path $repoRoot "translations\composite-text-rules.json"
$todoExporterPath = Join-Path $PSScriptRoot "Export-LocalizationTodoList.ps1"

$viewResult = & $reviewViewGeneratorPath -View Todo -OutputDirectory $outputDirectory
if (!(Test-Path -LiteralPath $OutputPath -PathType Leaf)) {
    throw "Localization todo CSV was not generated: $OutputPath"
}

$generatedOutputs = @($viewResult.Outputs)
if ($generatedOutputs.Count -ne 1 -or
    ![string]::Equals([System.IO.Path]::GetFileName([string]$generatedOutputs[0].Path),
        "localization-todolist.csv", [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Todo-only generation must emit only localization-todolist.csv."
}

$catalog = Get-Content -LiteralPath $compositeRulesPath -Raw -Encoding UTF8 | ConvertFrom-Json
$expectedComposites = @($catalog.Entries | Where-Object { $_.AuditStatus -eq "Unreviewed" })
$expectedReviewedNoSafeComposites = @($catalog.Entries | Where-Object { $_.AuditStatus -eq "ReviewedNoSafeRule" })
$todoRows = @(Import-Csv -LiteralPath $OutputPath -Encoding UTF8)
if ($todoRows.Count -eq 0) {
    throw "Localization todo CSV has no rows."
}
foreach ($column in @("RowKind", "TodoId", "CategoryId", "Original", "Route", "EntryPointId", "PartsJson")) {
    if (-not $todoRows[0].PSObject.Properties[$column]) {
        throw "Localization todo CSV is missing required column: $column"
    }
}

$textRows = @($todoRows | Where-Object { $_.RowKind -eq "Text" })
$compositeRows = @($todoRows | Where-Object { $_.RowKind -eq "Composite" })
if ($textRows.Count -eq 0) {
    throw "Localization todo CSV has no unresolved source-text rows."
}
if (@($textRows | Where-Object { $_.TodoId -notmatch '^TXT-[0-9A-F]{12}$' }).Count -gt 0) {
    throw "Localization todo CSV contains an invalid text todo identifier."
}
if (@($compositeRows | Where-Object { $_.TodoId -notmatch '^CMP-[0-9A-F]{12}$' }).Count -gt 0) {
    throw "Localization todo CSV contains an invalid composite todo identifier."
}
if ($compositeRows.Count -ne ($expectedComposites.Count + $expectedReviewedNoSafeComposites.Count)) {
    throw "Localization todo CSV has $($compositeRows.Count) composite rows, expected $($expectedComposites.Count + $expectedReviewedNoSafeComposites.Count)."
}
if (@($compositeRows | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.EntryPointId) }).Count -gt 0) {
    throw "Localization todo CSV has a composite row without EntryPointId."
}

$todoExporterSource = Get-Content -LiteralPath $todoExporterPath -Raw -Encoding UTF8
if ($todoExporterSource -match "KnownTextsCsv|Import-Csv") {
    throw "Todo exporter must not read a generated known-text view."
}
if ($todoExporterSource -notmatch "CatalogDatabasePath|CompositeRulesPath|todo-csv") {
    throw "Todo exporter must read the SQLite catalog and composite rule JSON directly."
}

Write-Host "Localization todo CSV validation passed: $($textRows.Count) text rows, $($compositeRows.Count) composite entries."
