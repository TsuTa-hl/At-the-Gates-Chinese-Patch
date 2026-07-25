[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$cleaner = Join-Path $PSScriptRoot "Clear-AtGWorkspace.ps1"
$fixture = Join-Path $repoRoot (".tmp\cleanup-workspace-test-" + [guid]::NewGuid().ToString("N"))
$cacheSentinel = Join-Path $repoRoot (".cache\cleanup-sentinel-" + [guid]::NewGuid().ToString("N") + ".txt")

function Assert-AtGTrue {
    param([bool]$Condition, [string]$Message)
    if (!$Condition) { throw $Message }
}

try {
    New-Item -ItemType Directory -Force -Path (Join-Path $fixture "runs\finished") | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $fixture "trial-localization\active") | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $fixture "trial-game-archive") | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $fixture "font-compare") | Out-Null
    Set-Content -LiteralPath (Join-Path $fixture "runs\finished\run-summary.json") -Encoding UTF8 -Value '{"Scenario":"cleanup-fixture","Status":"Failed","SaveName":"Fixture.AtGSave","Clicks":3,"Hovers":2}'
    Set-Content -LiteralPath (Join-Path $fixture "runs\finished\smoke.log") -Encoding UTF8 -Value "first`nsecond`nCrash summary"
    Set-Content -LiteralPath (Join-Path $fixture "runs\finished\shot.png") -Encoding ASCII -Value "not-a-real-image"
    Set-Content -LiteralPath (Join-Path $fixture "trial-localization\active-run.json") -Encoding UTF8 -Value '{"RunRoot":"active"}'
    Set-Content -LiteralPath (Join-Path $fixture "trial-localization\active\baseline.json") -Encoding UTF8 -Value '{"resume":true}'
    Set-Content -LiteralPath (Join-Path $fixture "font-compare\compare.png") -Encoding ASCII -Value "not-a-real-image"
    Set-Content -LiteralPath (Join-Path $fixture "scratch.log") -Encoding UTF8 -Value "scratch"
    Set-Content -LiteralPath $cacheSentinel -Encoding UTF8 -Value "must survive"

    $whatIf = & $cleaner -TempRoot $fixture -WhatIf | ConvertFrom-Json
    Assert-AtGTrue (Test-Path -LiteralPath (Join-Path $fixture "runs\finished\shot.png")) "WhatIf deleted a run screenshot."
    Assert-AtGTrue (!(Test-Path -LiteralPath (Join-Path $fixture "cleanup-handoffs"))) "WhatIf created a handoff directory."
    Assert-AtGTrue ($whatIf.CandidateCount -ge 3) "WhatIf did not classify expected temporary artifacts."

    $emptyActiveFixture = Join-Path $fixture "font-references"
    New-Item -ItemType Directory -Force -Path $emptyActiveFixture | Out-Null
    Set-Content -LiteralPath (Join-Path $emptyActiveFixture "scratch.txt") -Encoding UTF8 -Value "no active recovery marker"
    $emptyActive = & $cleaner -TempRoot $fixture -WhatIf | ConvertFrom-Json
    Assert-AtGTrue ($emptyActive.CandidateCount -ge 4) "WhatIf did not handle an empty active-root list."

    $result = & $cleaner -TempRoot $fixture -TaskId "cleanup-test" -Apply | ConvertFrom-Json
    Assert-AtGTrue ($result.Deleted) "Apply did not report deletion."
    Assert-AtGTrue (!(Test-Path -LiteralPath (Join-Path $fixture "runs\finished"))) "Completed run was not removed."
    Assert-AtGTrue (!(Test-Path -LiteralPath (Join-Path $fixture "font-compare"))) "Known visual artifact was not removed."
    Assert-AtGTrue (!(Test-Path -LiteralPath (Join-Path $fixture "trial-game-archive"))) "Empty known temporary directory was not removed."
    Assert-AtGTrue (Test-Path -LiteralPath (Join-Path $fixture "trial-localization\active-run.json")) "Active recovery marker was removed."
    Assert-AtGTrue (Test-Path -LiteralPath (Join-Path $fixture "trial-localization\active\baseline.json")) "Active recovery data was removed."
    Assert-AtGTrue (Test-Path -LiteralPath $cacheSentinel) ".cache sentinel was removed."
    $handoffPath = Join-Path $fixture "cleanup-handoffs\cleanup-test\cleanup-handoff.json"
    Assert-AtGTrue (Test-Path -LiteralPath $handoffPath) "Cleanup handoff was not written."
    $handoff = Get-Content -LiteralPath $handoffPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-AtGTrue ($handoff.JsonSummaries.Count -ge 1) "Cleanup handoff did not preserve the structured run summary."
    Assert-AtGTrue ($handoff.LogExcerpts.Count -ge 1) "Cleanup handoff did not preserve a log excerpt."

    New-Item -ItemType Directory -Force -Path (Join-Path $fixture "runs\keep-visual") | Out-Null
    Set-Content -LiteralPath (Join-Path $fixture "runs\keep-visual\run-summary.json") -Encoding UTF8 -Value '{"Scenario":"keep-visual"}'
    Set-Content -LiteralPath (Join-Path $fixture "runs\keep-visual\shot.png") -Encoding ASCII -Value "not-a-real-image"
    $preserved = & $cleaner -TempRoot $fixture -TaskId "cleanup-keep-visual" -Apply -KeepVisualEvidence | ConvertFrom-Json
    Assert-AtGTrue ($preserved.Deleted) "KeepVisualEvidence cleanup did not report deletion."
    Assert-AtGTrue (Test-Path -LiteralPath (Join-Path $fixture "runs\keep-visual\shot.png")) "KeepVisualEvidence removed the screenshot."

    Write-Host "Clear-AtGWorkspace tests passed."
}
finally {
    if (Test-Path -LiteralPath $fixture) {
        Remove-Item -LiteralPath $fixture -Recurse -Force
    }
    if (Test-Path -LiteralPath $cacheSentinel) {
        Remove-Item -LiteralPath $cacheSentinel -Force
    }
}
