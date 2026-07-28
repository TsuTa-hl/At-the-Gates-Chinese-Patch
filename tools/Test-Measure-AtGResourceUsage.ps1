$ErrorActionPreference = "Stop"

$root = Join-Path $PSScriptRoot ("..\.tmp\resource-monitor-test\" + [guid]::NewGuid().ToString("N"))

& (Join-Path $PSScriptRoot "Measure-AtGResourceUsage.ps1") `
    -Once `
    -OutputDirectory $root | Out-Null

$summaryPath = Join-Path $root "summary.json"
$samplesPath = Join-Path $root "samples.jsonl"
if (!(Test-Path -LiteralPath $summaryPath)) { throw "Resource monitor did not write summary.json." }
if (!(Test-Path -LiteralPath $samplesPath)) { throw "Resource monitor did not write samples.jsonl." }

$summary = Get-Content -LiteralPath $summaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($summary.SampleCount -ne 1) { throw "Expected exactly one monitor sample." }
if ($summary.SystemMemory.TotalPhysicalBytes -le 0) { throw "System memory total was not recorded." }
if ([string]::IsNullOrWhiteSpace([string]$summary.Network.Attribution)) {
    throw "Network attribution disclaimer was not recorded."
}
$codex = @($summary.ProcessGroups | Where-Object { $_.Name -eq "CodexDesktop" })
if ($codex.Count -ne 1) { throw "CodexDesktop process group was not recorded." }

$defaultOutput = & (Join-Path $PSScriptRoot "Measure-AtGResourceUsage.ps1") -Once | ConvertFrom-Json
if ([string]::IsNullOrWhiteSpace([string]$defaultOutput.OutputDirectory)) {
    throw "The resource monitor default output directory was not resolved."
}

Write-Host "Resource monitor test passed."
