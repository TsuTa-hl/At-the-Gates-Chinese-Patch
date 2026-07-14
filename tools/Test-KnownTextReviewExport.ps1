param(
    [string]$OutputDirectory = ".\.tmp\known-text-review-test"
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$outRoot = Join-Path $repoRoot $OutputDirectory
New-Item -ItemType Directory -Force -Path $outRoot | Out-Null

$csvPath = Join-Path $outRoot "known-texts.csv"
$mdPath = Join-Path $outRoot "known-texts.md"
$catalogPath = Join-Path $outRoot "atg-catalog.sqlite"

$exportResult = & (Join-Path $PSScriptRoot "Export-KnownTextReview.ps1") `
    -MarkdownOutputPath $mdPath `
    -CsvOutputPath $csvPath `
    -CatalogDatabasePath $catalogPath

if (!(Test-Path -LiteralPath $mdPath -PathType Leaf)) {
    throw "Markdown review output was not generated: $mdPath"
}
if (!(Test-Path -LiteralPath $csvPath -PathType Leaf)) {
    throw "CSV review output was not generated: $csvPath"
}
if (!(Test-Path -LiteralPath $catalogPath -PathType Leaf)) {
    throw "SQLite review catalog was not generated: $catalogPath"
}

$mdRaw = Get-Content -LiteralPath $mdPath -Raw -Encoding UTF8
if ($mdRaw -notmatch "# Known Texts AI Index") {
    throw "Markdown review output is missing the AI index header."
}
if ($mdRaw -notmatch "Query the SQLite catalog first") {
    throw "Markdown review output must direct workflow matching to SQLite first."
}
if ($mdRaw -notmatch "Use this Markdown for grouped source context") {
    throw "Markdown review output must identify itself as the grouped context view."
}
if ($mdRaw -match "Use this Markdown first for agent/workflow text matching") {
    throw "Markdown review output must not supersede the SQLite primary query path."
}
if ($mdRaw -notmatch "## Source: source\\English\.original\.xml") {
    throw "Markdown review output must group rows by source file."
}
if ($mdRaw -notmatch 'Original:\r?\n```text' -or $mdRaw -notmatch 'Translation:\r?\n```text') {
    throw "Markdown review output must expose original and translation text blocks."
}
if ($mdRaw -notmatch "Locators:") {
    throw "Markdown review output must include locators for workflow matching."
}
if ($mdRaw -notmatch "SourceOccurrenceId:" -or $mdRaw -notmatch "SemanticGroupId:") {
    throw "Markdown review output must expose SQLite occurrence and semantic-group identifiers."
}
if ($null -eq $exportResult.MarkdownOutputPath -or -not (Test-Path -LiteralPath $exportResult.MarkdownOutputPath -PathType Leaf)) {
    throw "Exporter result must include MarkdownOutputPath."
}
if ($null -eq $exportResult.CsvOutputPath -or -not (Test-Path -LiteralPath $exportResult.CsvOutputPath -PathType Leaf)) {
    throw "Exporter result must include CsvOutputPath."
}
if ($null -eq $exportResult.CatalogDatabasePath -or -not (Test-Path -LiteralPath $exportResult.CatalogDatabasePath -PathType Leaf)) {
    throw "Exporter result must include CatalogDatabasePath."
}

$rows = @(Import-Csv -LiteralPath $csvPath -Encoding UTF8)
if ($rows.Count -lt 1000) {
    throw "CSV review output has too few rows: $($rows.Count)"
}

if ($rows.Count -lt 7000) {
    throw "CSV review output is missing discovered source rows: $($rows.Count). The exporter must rebuild discovery inputs and must not collapse the review table to mapped strings only."
}

$catalogQueryOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "Invoke-AtGPatchCli.ps1") `
    -Command catalog `
    -CatalogAction search `
    -CatalogDatabasePath $catalogPath `
    -CatalogText "Log In" `
    -CatalogSource "AtTheGatesUI" `
    -CatalogLimit 5
if ($LASTEXITCODE -ne 0) {
    throw "Catalog search command failed with exit code $LASTEXITCODE."
}
$catalogMatches = (($catalogQueryOutput | Out-String) | ConvertFrom-Json)
if (@($catalogMatches).Count -eq 0 -or @($catalogMatches | Where-Object { $_.Original -eq "Log In" }).Count -eq 0) {
    throw "Catalog search command did not return the expected exact known-text match."
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
    MarkdownPath = (Resolve-Path -LiteralPath $mdPath).Path
    CsvPath = (Resolve-Path -LiteralPath $csvPath).Path
    RowCount = $rows.Count
}

Write-Host "Known text review export validation passed."
