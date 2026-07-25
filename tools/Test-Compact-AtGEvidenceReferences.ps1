[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

function Assert-AtGCondition {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (!$Condition) {
        throw $Message
    }
}

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$fixtureRoot = Join-Path $projectRoot ".tmp\evidence-reference-compaction-test"
$agentRoot = Join-Path $fixtureRoot "docs\agent"

if (Test-Path -LiteralPath $fixtureRoot) {
    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $agentRoot | Out-Null

$scenario = @{
    FullRegression = @(
        @{
            Id = "fixture"
            Evidence = @{
                LastStatus = "Passed"
                LastRunDir = ".tmp/runs/fixture"
                LastScreenshot = ".tmp/runs/fixture/window.png"
            }
        }
    )
    Incremental = @()
}
$traits = @{
    Traits = @(
        @{ ID = "TRAIT_Test"; EvidenceDir = ".tmp/runs/trait" },
        @{ ID = "TRAIT_None"; EvidenceDir = $null }
    )
}
$trialState = @{
    batches = @(
        @{ batchId = "trial"; runRoot = ".tmp\trial-localization\fixture"; status = "accepted-smoke" },
        @{ batchId = "empty"; runRoot = $null; status = "accepted-smoke" }
    )
    latestSmoke = @{ notes = "Latest accepted pass: fixture (1/0), run .tmp\trial-localization\fixture." }
    latestSparkAudit = @{ postCleanupSmoke = @{ screenshot = ".tmp/game-smoke.png" } }
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
foreach ($entry in @(
    @{ Path = (Join-Path $agentRoot "black-box-scenarios.json"); Value = $scenario },
    @{ Path = (Join-Path $agentRoot "clan-trait-verification.json"); Value = $traits },
    @{ Path = (Join-Path $agentRoot "trial-localization-state.json"); Value = $trialState }
)) {
    [IO.File]::WriteAllText($entry.Path, ($entry.Value | ConvertTo-Json -Depth 20), $utf8NoBom)
}

try {
    $result = & (Join-Path $projectRoot "tools\Compact-AtGEvidenceReferences.ps1") -ProjectRoot $fixtureRoot -HandoffId "fixture-cleanup" | Select-Object -Last 1
    Assert-AtGCondition ($result.ScenarioChanges -eq 1) "Expected one scenario evidence migration."
    Assert-AtGCondition ($result.TraitChanges -eq 2) "Expected both trait evidence fields to be compacted."
    Assert-AtGCondition ($result.TrialStateChanges -ge 2) "Expected trial batch and latest-smoke compaction."

    $actualScenario = Get-Content -LiteralPath (Join-Path $agentRoot "black-box-scenarios.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    $evidence = $actualScenario.FullRegression[0].Evidence
    Assert-AtGCondition ($null -eq $evidence.PSObject.Properties["LastRunDir"]) "Scenario still retains LastRunDir."
    Assert-AtGCondition ($null -eq $evidence.PSObject.Properties["LastScreenshot"]) "Scenario still retains LastScreenshot."
    Assert-AtGCondition ([string]$evidence.EvidenceHandoff -eq "fixture-cleanup") "Scenario did not retain the handoff ID."

    $actualTraits = Get-Content -LiteralPath (Join-Path $agentRoot "clan-trait-verification.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-AtGCondition ($null -eq $actualTraits.Traits[0].PSObject.Properties["EvidenceDir"]) "Trait still retains EvidenceDir."
    Assert-AtGCondition ([string]$actualTraits.Traits[0].EvidenceHandoff -eq "fixture-cleanup") "Trait did not retain handoff ID."
    Assert-AtGCondition ($null -eq $actualTraits.Traits[1].PSObject.Properties["EvidenceDir"]) "Null trait EvidenceDir was not removed."

    $actualTrials = Get-Content -LiteralPath (Join-Path $agentRoot "trial-localization-state.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-AtGCondition ($null -eq $actualTrials.batches[0].PSObject.Properties["runRoot"]) "Trial batch still retains runRoot."
    Assert-AtGCondition ([string]$actualTrials.batches[0].evidenceHandoff -eq "fixture-cleanup") "Trial batch did not retain handoff ID."
    Assert-AtGCondition ($null -eq $actualTrials.batches[1].PSObject.Properties["runRoot"]) "Null trial runRoot was not removed."
    Assert-AtGCondition ([string]$actualTrials.latestSmoke.notes -notmatch '\.tmp') "Latest smoke still contains a temporary path."
    Assert-AtGCondition ($null -eq $actualTrials.latestSparkAudit.postCleanupSmoke.PSObject.Properties["screenshot"]) "Nested Spark screenshot was not removed."

    foreach ($jsonPath in @(
        (Join-Path $agentRoot "black-box-scenarios.json"),
        (Join-Path $agentRoot "clan-trait-verification.json"),
        (Join-Path $agentRoot "trial-localization-state.json")
    )) {
        $rawJson = [IO.File]::ReadAllText($jsonPath)
        Assert-AtGCondition (!$rawJson.Contains("`r")) "Compacted JSON must use stable LF line endings: $jsonPath"
    }

    $idempotent = & (Join-Path $projectRoot "tools\Compact-AtGEvidenceReferences.ps1") -ProjectRoot $fixtureRoot -HandoffId "fixture-cleanup" | Select-Object -Last 1
    Assert-AtGCondition ($idempotent.ScenarioChanges -eq 0) "Second scenario compaction was not idempotent."
    Assert-AtGCondition ($idempotent.TraitChanges -eq 0) "Second trait compaction was not idempotent."
    Assert-AtGCondition ($idempotent.TrialStateChanges -eq 0) "Second trial-state compaction was not idempotent."
}
finally {
    if (Test-Path -LiteralPath $fixtureRoot) {
        Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
    }
}

Write-Host "Evidence-reference compaction tests passed."
