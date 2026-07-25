$ErrorActionPreference = "Stop"

$root = Join-Path $PSScriptRoot ("..\.tmp\runtime-glyph-performance-test\" + [guid]::NewGuid().ToString("N"))
[IO.Directory]::CreateDirectory($root) | Out-Null
$tracePath = Join-Path $root "runtime-performance.jsonl"
$summaryPath = Join-Path $root "summary.json"
$legacyPath = Join-Path $root "legacy-summary.json"

$lines = @(
    '{"time":"2026-07-24T00:00:00Z","frame":1,"mode":"Budgeted","mainThreadMs":0.5,"uploadMs":0.2,"maxUploadMs":0.2,"rasterMs":1.0,"uploads":1,"rasterized":2,"requests":3,"lookups":10,"hits":8,"misses":2,"hitRate":0.8,"fallbacks":0,"warmSkips":0,"budgetStops":0,"pageCreations":1,"deviceResets":0,"maxPending":20,"maxReady":5,"atlasPages":1}',
    '{"time":"2026-07-24T00:00:01Z","frame":2,"mode":"Budgeted","mainThreadMs":1.0,"uploadMs":0.3,"maxUploadMs":0.3,"rasterMs":0.5,"uploads":1,"rasterized":1,"requests":1,"lookups":10,"hits":9,"misses":1,"hitRate":0.9,"fallbacks":0,"warmSkips":0,"budgetStops":0,"pageCreations":0,"deviceResets":0,"maxPending":10,"maxReady":4,"atlasPages":1}',
    '{"time":"2026-07-24T00:00:02Z","frame":3,"mode":"Budgeted","mainThreadMs":1.5,"uploadMs":0.4,"maxUploadMs":0.4,"rasterMs":0.0,"uploads":1,"rasterized":0,"requests":0,"lookups":10,"hits":9,"misses":1,"hitRate":0.9,"fallbacks":0,"warmSkips":0,"budgetStops":0,"pageCreations":0,"deviceResets":0,"maxPending":5,"maxReady":3,"atlasPages":1}',
    '{"time":"2026-07-24T00:00:03Z","frame":4,"mode":"Budgeted","mainThreadMs":2.0,"uploadMs":0.5,"maxUploadMs":0.5,"rasterMs":0.0,"uploads":1,"rasterized":0,"requests":0,"lookups":10,"hits":9,"misses":1,"hitRate":0.9,"fallbacks":0,"warmSkips":0,"budgetStops":1,"pageCreations":0,"deviceResets":0,"maxPending":4,"maxReady":2,"atlasPages":1}',
    '{"time":"2026-07-24T00:00:04Z","frame":5,"mode":"Budgeted","mainThreadMs":2.0,"uploadMs":0.6,"maxUploadMs":0.6,"rasterMs":0.0,"uploads":1,"rasterized":0,"requests":0,"lookups":10,"hits":10,"misses":0,"hitRate":1.0,"fallbacks":0,"warmSkips":0,"budgetStops":0,"pageCreations":0,"deviceResets":0,"maxPending":1,"maxReady":1,"atlasPages":1}'
)
[IO.File]::WriteAllLines($tracePath, $lines, [Text.UTF8Encoding]::new($false))

@{
    MainThreadMs = @{
        Maximum = 10.0
    }
} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $legacyPath -Encoding UTF8

$summary = & (Join-Path $PSScriptRoot "Measure-RuntimeGlyphPerformance.ps1") `
    -TracePath $tracePath `
    -ExpectedMode Budgeted `
    -MinimumFrames 5 `
    -RequireNoFallback `
    -EnforceBudgetedThresholds `
    -LegacySummaryPath $legacyPath `
    -OutputPath $summaryPath

if ($summary.FrameCount -ne 5) { throw "Expected five analyzed frames." }
if ($summary.MainThreadMs.P95 -ne 2.0) { throw "Unexpected main-thread P95." }
if ($summary.UploadMs.MaximumSingleOperation -ne 0.6) {
    throw "Unexpected single-operation upload maximum."
}
if ($summary.HitRate -ne 0.9) { throw "Expected aggregate hit rate 0.9." }
if ($summary.Totals.Uploads -ne 5) { throw "Expected five uploads." }
if (!(Test-Path -LiteralPath $summaryPath)) { throw "Performance summary was not written." }

$failedAsExpected = $false
try {
    & (Join-Path $PSScriptRoot "Measure-RuntimeGlyphPerformance.ps1") `
        -TracePath $tracePath `
        -ExpectedMode LegacySync | Out-Null
}
catch {
    $failedAsExpected = $_.Exception.Message -match "expected 'LegacySync'"
}
if (!$failedAsExpected) { throw "Mode mismatch should fail verification." }

$failedAsExpected = $false
try {
    & (Join-Path $PSScriptRoot "Measure-RuntimeGlyphPerformance.ps1") `
        -TracePath $tracePath `
        -RequireNoRasterOrUpload | Out-Null
}
catch {
    $failedAsExpected = $_.Exception.Message -match "Hot replay performed"
}
if (!$failedAsExpected) { throw "Hot replay activity should fail verification." }

Write-Host "Runtime glyph performance measurement test passed."
