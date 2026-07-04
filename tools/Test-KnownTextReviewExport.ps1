param(
    [string]$OutputDirectory = ".\.tmp\known-text-review-test"
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$outRoot = Join-Path $repoRoot $OutputDirectory
New-Item -ItemType Directory -Force -Path $outRoot | Out-Null

$csvPath = Join-Path $outRoot "known-texts.csv"

& (Join-Path $PSScriptRoot "Export-KnownTextReview.ps1") `
    -CsvOutputPath $csvPath | Out-Null

if (!(Test-Path -LiteralPath $csvPath -PathType Leaf)) {
    throw "CSV review output was not generated: $csvPath"
}

$rows = @(Import-Csv -LiteralPath $csvPath -Encoding UTF8)
if ($rows.Count -lt 1000) {
    throw "CSV review output has too few rows: $($rows.Count)"
}

if ($rows.Count -lt 7000) {
    throw "CSV review output is missing discovered source rows: $($rows.Count). The exporter must rebuild discovery inputs and must not collapse the review table to mapped strings only."
}

$requiredColumns = @(
    "SourceFile",
    "Kind",
    "Original",
    "Translation",
    "Status",
    "ReviewState",
    "ReasonCode",
    "Safety",
    "Locators"
)

$columns = @($rows[0].PSObject.Properties.Name)
foreach ($column in $requiredColumns) {
    if ($columns -notcontains $column) {
        throw "CSV review output is missing required column: $column"
    }
}

$removedColumns = @(
    "LocalizationAttempted",
    "AttemptStatus",
    "FailureReason"
)

foreach ($column in $removedColumns) {
    if ($columns -contains $column) {
        throw "CSV review output still contains removed column: $column"
    }
}

$allowedReviewStates = @("Translated", "NeedsTrial", "Skipped", "RecheckedSkipped", "Rejected")
$badReviewState = $rows | Where-Object {
    $allowedReviewStates -notcontains $_.ReviewState
} | Select-Object -First 1
if ($null -ne $badReviewState) {
    throw "CSV contains invalid ReviewState '$($badReviewState.ReviewState)' for '$($badReviewState.Original)'."
}

$allowedReasonCodes = @(
    "",
    "TechnicalInternal",
    "LogicSensitive",
    "FragmentOrToken",
    "OutOfScope",
    "PatchConflict",
    "RejectedByTest"
)
$badReasonCode = $rows | Where-Object {
    $allowedReasonCodes -notcontains $_.ReasonCode
} | Select-Object -First 1
if ($null -ne $badReasonCode) {
    throw "CSV contains invalid ReasonCode '$($badReasonCode.ReasonCode)' for '$($badReasonCode.Original)'."
}

$requiredSources = @(
    "source\English.original.xml",
    "source\Content\Config\Primary\ClanTraits.original.xml",
    "source\Content\Config\Primary\Factions.original.xml",
    "source\Content\Config\Primary\FactionTraits.original.xml",
    "source\Content\Config\Primary\Techs.original.xml",
    "source\AtTheGatesUI.original.dll",
    "source\AtTheGatesCommon.original.dll",
    "source\AtTheGatesGame.original.exe",
    "source\ElfTools.original.dll"
)

$sourceSet = @{}
foreach ($row in $rows) {
    $sourceSet[[string]$row.SourceFile] = $true
}
foreach ($source in $requiredSources) {
    if (-not $sourceSet.ContainsKey($source)) {
        throw "CSV review output is missing known text source: $source"
    }
}

$duplicateSourceOccurrences = @($rows | Where-Object {
    $_.SourceFile -eq "source\AtTheGatesUI.original.dll" -and
    $_.Original -eq "a" -and
    $_.Locators -match "MethodToken="
})
if ($duplicateSourceOccurrences.Count -lt 2) {
    throw "CSV review output appears to deduplicate repeated DLL source occurrences for original ' a '."
}

$expectedLoginTranslation = ([string][char]0x767b) + ([string][char]0x5f55)
$translatedAttempt = $rows | Where-Object {
    $_.Original -eq "Log In" -and
    $_.Translation -eq $expectedLoginTranslation -and
    $_.ReviewState -eq "Translated"
} | Select-Object -First 1
if ($null -eq $translatedAttempt) {
    throw "CSV does not mark accepted translated entry 'Log In' as attempted."
}

$rejectedAttempt = $rows | Where-Object {
    $_.Original -eq "Leave" -and
    $_.ReviewState -eq "Rejected" -and
    $_.ReasonCode -eq "PatchConflict" -and
    $_.Locators -match "ILOffset=1774"
} | Select-Object -First 1
if ($null -eq $rejectedAttempt) {
    throw "CSV does not include rejected 'Leave ' attempt with offset-conflict failure reason."
}

$elfToolsCatalog = Join-Path $repoRoot ".tmp\elftools-ldstr-catalog.csv"
if (Test-Path -LiteralPath $elfToolsCatalog -PathType Leaf) {
    $elfToolsCandidate = $rows | Where-Object {
        $_.SourceFile -eq "source\ElfTools.original.dll" -and
        $_.Original -eq "Click to select..." -and
        $_.Locators -match "MethodToken=0x060006b3"
    } | Select-Object -First 1
    if ($null -eq $elfToolsCandidate) {
        throw "CSV does not include unmapped ElfTools catalog candidates."
    }

    $elfToolsInternal = $rows | Where-Object {
        $_.SourceFile -eq "source\ElfTools.original.dll" -and
        $_.Original -eq "Capacity may not be negative." -and
        $_.ReviewState -eq "Skipped" -and
        $_.ReasonCode -eq "TechnicalInternal"
    } | Select-Object -First 1
    if ($null -eq $elfToolsInternal) {
        throw "CSV must classify ElfTools internal exception text as Skipped/TechnicalInternal, not TrialCandidate."
    }
}

$gameReadyMarker = $rows | Where-Object {
    $_.SourceFile -eq "source\AtTheGatesGame.original.exe" -and
    $_.Original -eq "- Giving Control to Human" -and
    $_.ReviewState -eq "Skipped" -and
    $_.ReasonCode -eq "TechnicalInternal"
} | Select-Object -First 1
if ($null -eq $gameReadyMarker) {
    throw "CSV must classify the game ready-marker log string '- Giving Control to Human' as Skipped/TechnicalInternal, not NeedsTrial."
}

$gameComponentDiagnostic = $rows | Where-Object {
    $_.SourceFile -eq "source\AtTheGatesGame.original.exe" -and
    $_.Original -eq "CCanPillage component's parent lacks the required CCanAct component." -and
    $_.ReviewState -eq "Skipped" -and
    $_.ReasonCode -eq "TechnicalInternal"
} | Select-Object -First 1
if ($null -eq $gameComponentDiagnostic) {
    throw "CSV must classify Game component diagnostics as Skipped/TechnicalInternal, not NeedsTrial."
}

$gamePlagueDiagnostic = $rows | Where-Object {
    $_.SourceFile -eq "source\AtTheGatesGame.original.exe" -and
    $_.Original -eq "PlagueMgr.ApplyUnitPlagueDeath (1)" -and
    $_.ReviewState -eq "Skipped" -and
    $_.ReasonCode -eq "TechnicalInternal"
} | Select-Object -First 1
if ($null -eq $gamePlagueDiagnostic) {
    throw "CSV must classify Game PlagueMgr diagnostics as Skipped/TechnicalInternal, not NeedsTrial."
}

$trialStatePath = Join-Path $repoRoot "docs\agent\trial-localization-state.json"
$expectedNotAttemptedRows = $null
if (Test-Path -LiteralPath $trialStatePath -PathType Leaf) {
    $trialState = Get-Content -LiteralPath $trialStatePath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($null -ne $trialState.reviewSnapshot -and
        $null -ne $trialState.reviewSnapshot.PSObject.Properties["notAttemptedRows"]) {
        $expectedNotAttemptedRows = [int]$trialState.reviewSnapshot.notAttemptedRows
    }
}

$notAttemptedRows = @($rows | Where-Object { $_.ReviewState -in @("NeedsTrial", "Skipped", "RecheckedSkipped") })
if ($notAttemptedRows.Count -eq 0) {
    if ($null -ne $expectedNotAttemptedRows -and $expectedNotAttemptedRows -gt 0) {
        throw "CSV has no unattempted rows, but trial-localization-state.json expects $expectedNotAttemptedRows."
    }
}
else {
    $missingReason = $notAttemptedRows | Where-Object {
        [string]::IsNullOrWhiteSpace($_.ReviewState) -or
        ($_.ReviewState -in @("Skipped", "RecheckedSkipped") -and [string]::IsNullOrWhiteSpace($_.ReasonCode))
    } | Select-Object -First 1
    if ($null -ne $missingReason) {
        throw "CSV contains unattempted text without explicit attempt status or skip reason."
    }
}

[pscustomobject]@{
    CsvPath = (Resolve-Path -LiteralPath $csvPath).Path
    RowCount = $rows.Count
}

Write-Host "Known text review export validation passed."
