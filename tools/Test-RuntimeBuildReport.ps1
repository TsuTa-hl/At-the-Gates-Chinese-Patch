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
if ([int]$report.RuntimeText.FrameBoundaryHookCount -ne 1) {
    throw "Expected one runtime frame-boundary hook, got $($report.RuntimeText.FrameBoundaryHookCount)."
}
if ([int]$report.RuntimeText.WarmsetStartupHookCount -ne 1) {
    throw "Expected one runtime warmset startup hook, got $($report.RuntimeText.WarmsetStartupHookCount)."
}
if ([int]$report.RuntimeText.StartupGraphicsHookCount -ne 1) {
    throw "Expected one runtime startup graphics hook, got $($report.RuntimeText.StartupGraphicsHookCount)."
}
if ([int]$report.RuntimeText.ConceptKeyCount -ne 113) {
    throw "Expected 113 concept keys, got $($report.RuntimeText.ConceptKeyCount)."
}
if ([int]$report.RuntimeText.ConceptDisplayCount -lt 31) {
    throw "Expected at least 31 concept display mappings, got $($report.RuntimeText.ConceptDisplayCount)."
}
if ([int]$report.RuntimeText.TemplateCount -lt 20) {
    throw "Expected at least 20 entry-specific display templates, got $($report.RuntimeText.TemplateCount)."
}
if ([int64]$report.RuntimeText.AtlasBudgetBytes -ne 33554432) {
    throw "Expected a 32 MiB runtime atlas budget."
}
if ([int]$report.RuntimeText.MaximumWarmAtlasPages -ne 6) {
    throw "Expected runtime prewarming to stop at six atlas pages."
}
if ([double]$report.RuntimeText.UploadBudgetMilliseconds -ne 2) {
    throw "Expected a 2 ms runtime glyph upload budget."
}
if ([int]$report.RuntimeText.MaximumUploadsPerFrame -ne 16) {
    throw "Expected at most 16 runtime glyph uploads per frame."
}
if ([int]$report.RuntimeText.WarmsetVersion -ne 1) {
    throw "Expected runtime glyph warmset v1."
}
if ([int]$report.RuntimeText.WarmGlyphPairCount -lt 0) {
    throw "Runtime warm glyph pair count cannot be negative."
}

Write-Host "Runtime build report test passed."
