param(
    [string]$ReportPath = "$PSScriptRoot\..\patch\.atg-build-report.json"
)

$ErrorActionPreference = "Stop"
$resolvedReportPath = (Resolve-Path -LiteralPath $ReportPath).Path
$reportBytes = [System.IO.File]::ReadAllBytes($resolvedReportPath)
if ($reportBytes.Length -ge 3 -and
    $reportBytes[0] -eq 0xEF -and $reportBytes[1] -eq 0xBB -and $reportBytes[2] -eq 0xBF) {
    throw "Runtime build report must use UTF-8 without BOM."
}
$reportJson = [System.IO.File]::ReadAllText($resolvedReportPath, [System.Text.Encoding]::UTF8)
if ($reportJson.Length -gt 0 -and [char]::IsWhiteSpace($reportJson[$reportJson.Length - 1])) {
    throw "Runtime build report must not end with whitespace."
}
$report = $reportJson | ConvertFrom-Json
if ($report.RendererMode -ne "DynamicCjk") {
    throw "Runtime build report test requires a DynamicCjk build report."
}
if ($null -eq $report.RuntimeText) {
    throw "DynamicCjk build report is missing RuntimeText details."
}
if ([int]$report.RuntimeText.RedirectedCount -ne 145) {
    throw "Expected 145 runtime redirects, got $($report.RuntimeText.RedirectedCount)."
}
if ([int]$report.RuntimeText.ConceptKeyCount -ne 113) {
    throw "Expected 113 concept keys, got $($report.RuntimeText.ConceptKeyCount)."
}
if ([int]$report.RuntimeText.ConceptDisplayCount -lt 31) {
    throw "Expected at least 31 concept display mappings, got $($report.RuntimeText.ConceptDisplayCount)."
}
if ([int64]$report.RuntimeText.AtlasBudgetBytes -ne 33554432) {
    throw "Expected a 32 MiB runtime atlas budget."
}

Write-Host "Runtime build report test passed."
