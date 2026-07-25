$ErrorActionPreference = "Stop"
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("atg-warmset-test-" + [Guid]::NewGuid().ToString("N"))
[IO.Directory]::CreateDirectory($tempRoot) | Out-Null
try {
    $traceA = Join-Path $tempRoot "load.jsonl"
    $traceB = Join-Path $tempRoot "knowledge.jsonl"
    $output = Join-Path $tempRoot "warmset.tsv"
    $font = "SegoeUI_15_Bold|15|True|cjk=1.15"
    $firstText = -join ([char[]](0x4E2D, 0x6587, 0x7532, 0x65B0))
    $secondText = -join ([char[]](0x6587, 0x4E59))
    $linesA = @(
        (@{
            event = "draw"
            text = $firstText
            font = $font
        } | ConvertTo-Json -Compress)
    )
    $linesB = @(
        (@{
            event = "measure"
            text = $secondText
            font = $font
        } | ConvertTo-Json -Compress)
    )
    [IO.File]::WriteAllLines($traceA, $linesA, [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllLines($traceB, $linesB, [Text.UTF8Encoding]::new($false))

    $result = & "$PSScriptRoot\Export-RuntimeGlyphWarmset.ps1" `
        -TracePath @($traceA, $traceB) `
        -ScenarioId @(
            "load-save-main-loop-tile-tooltip-20260702",
            "knowledge-screen-hovers"
        ) `
        -OutputPath $output
    if ($result.PairCount -ne 5) {
        throw "Expected five distinct font/glyph pairs, got $($result.PairCount)."
    }
    & "$PSScriptRoot\Test-RuntimeGlyphWarmset.ps1" -WarmsetPath $output -MinimumPairCount 5
    $records = @([IO.File]::ReadAllLines($output, [Text.Encoding]::UTF8) |
        Where-Object { $_.StartsWith("W`t") })
    if ($records.Count -ne 3) {
        throw "Expected three priority groups, got $($records.Count)."
    }
    $startupRecords = @($records | Where-Object { ($_ -split "`t")[1] -eq "0" })
    if ($startupRecords.Count -ne 1) {
        throw "Expected one trace-observed startup glyph priority group, got $($startupRecords.Count)."
    }
    Write-Host "Runtime glyph warmset exporter test passed."
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
