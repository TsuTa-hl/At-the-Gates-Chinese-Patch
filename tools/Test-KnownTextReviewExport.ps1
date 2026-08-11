param(
    [string]$OutputDirectory = ".\.tmp\known-text-review-test"
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$outRoot = Join-Path $repoRoot $OutputDirectory
New-Item -ItemType Directory -Force -Path $outRoot | Out-Null

$csvPath = Join-Path $outRoot "known-texts.csv"
$catalogPath = Join-Path $outRoot "atg-catalog.sqlite"

$exportResult = & (Join-Path $PSScriptRoot "Export-KnownTextReview.ps1") `
    -CsvOutputPath $csvPath `
    -CatalogDatabasePath $catalogPath

if (!(Test-Path -LiteralPath $csvPath -PathType Leaf)) {
    throw "CSV review output was not generated: $csvPath"
}
if (!(Test-Path -LiteralPath $catalogPath -PathType Leaf)) {
    throw "SQLite review catalog was not generated: $catalogPath"
}

if ($null -eq $exportResult.CsvOutputPath -or -not (Test-Path -LiteralPath $exportResult.CsvOutputPath -PathType Leaf)) {
    throw "Exporter result must include CsvOutputPath."
}
if ($null -eq $exportResult.CatalogDatabasePath -or -not (Test-Path -LiteralPath $exportResult.CatalogDatabasePath -PathType Leaf)) {
    throw "Exporter result must include CatalogDatabasePath."
}
$knownTextExporterSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot "Export-KnownTextReview.ps1") -Raw -Encoding UTF8
if ($knownTextExporterSource -match "MarkdownOutputPath|--markdown") {
    throw "Known-text export must not generate a Markdown review view."
}
if ($knownTextExporterSource -notmatch "CompositeRulesPath|known-texts-csv") {
    throw "Known-text export must enrich the CSV from the composite rule source and SQLite catalog directly."
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
    "Locators",
    "SourceOccurrenceId",
    "SemanticGroupId",
    "CompositeReferenceCount",
    "CompositeEntryPointIds",
    "CompositeReferencesJson"
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

$apiaryKnownText = $rows | Where-Object {
    $_.Locators -eq "ID=STRUCTURE_APIARY_1; XPath=description; Index=" -and
    $_.Original -like "Apiaries are a *"
} | Select-Object -First 1
if ($null -eq $apiaryKnownText -or [int]$apiaryKnownText.CompositeReferenceCount -lt 1 -or
    [string]::IsNullOrWhiteSpace([string]$apiaryKnownText.CompositeEntryPointIds) -or
    $apiaryKnownText.CompositeReferencesJson -notmatch 'ConfigIdXPathIndexLocator') {
    throw "Known-text CSV must expose the exact reverse Composite link for the Apiary config description."
}

$creditsKnownText = $rows | Where-Object {
    $_.Locators -eq "TEXT.Credits.Conifer"
} | Select-Object -First 1
if ($null -eq $creditsKnownText -or [int]$creditsKnownText.CompositeReferenceCount -lt 1 -or
    $creditsKnownText.CompositeReferencesJson -notmatch 'TextKeyExactLocator') {
    throw "Known-text CSV must expose English text-key Composite links without a heuristic text join."
}

$runtimeMapKnownTexts = @($rows | Where-Object {
    $_.SourceFile -eq "translations\runtime-display-strings.json"
})
$runtimeDisplayMap = Get-Content -LiteralPath (Join-Path $repoRoot "translations\runtime-display-strings.json") -Raw -Encoding UTF8 | ConvertFrom-Json
$expectedRuntimeMapBindings = @(
    foreach ($section in @("Exact", "PlainText", "PlainTextFragments", "RichTextFragments", "BareTags", "Templates", "ConceptDisplay")) {
        foreach ($entry in @($runtimeDisplayMap.$section)) {
            if ($null -ne $entry -and ![string]::IsNullOrWhiteSpace([string]$entry.Original) -and
                $null -ne $entry.Translation) {
                $entry
            }
        }
    }
)
if ($runtimeMapKnownTexts.Count -ne $expectedRuntimeMapBindings.Count -or @($runtimeMapKnownTexts | Where-Object {
    $_.Kind -notmatch '^Runtime display map \(' -or
    $_.Status -ne "Translated" -or
    $_.ReviewState -ne "Translated" -or
    $_.Locators -notmatch '^RuntimeMapSection=.*; RuntimeMapOriginal=' -or
    [int]$_.CompositeReferenceCount -ne 1 -or
    $_.CompositeReferencesJson -notmatch 'RuntimeMapExactLocator'
}).Count -gt 0) {
    throw "Known-text CSV must include all $($expectedRuntimeMapBindings.Count) runtime-display-map bindings as exact Composite-linked KnownTexts."
}
$activeRuntimeConcept = @($runtimeMapKnownTexts | Where-Object {
    $_.Locators -eq "RuntimeMapSection=ConceptDisplay; RuntimeMapOriginal=Active; RuntimeMapConceptKey=ACTIVE"
})
if ($activeRuntimeConcept.Count -ne 1 -or $activeRuntimeConcept[0].Original -ne "[Active|ACTIVE]") {
    throw "Known-text CSV must retain the concept wrapper and stable map locator for the Active runtime binding."
}

$allowedReviewStates = @("Translated", "ReviewRequired", "Skipped", "Rejected")
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
    "RejectedByTest",
    "UnverifiedDisplayRoute"
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
    "source\Content\Config\Misc\Religions.original.xml",
    "source\AtTheGatesUI.original.dll",
    "source\AtTheGatesCommon.original.dll",
    "source\AtTheGatesGame.original.exe",
    "source\ElfTools.original.dll",
    "translations\runtime-display-strings.json"
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
        throw "CSV must classify ElfTools internal exception text as Skipped/TechnicalInternal, not a display-review candidate."
    }
}

$gameReadyMarker = $rows | Where-Object {
    $_.SourceFile -eq "source\AtTheGatesGame.original.exe" -and
    $_.Original -eq "- Giving Control to Human" -and
    $_.ReviewState -eq "Skipped" -and
    $_.ReasonCode -eq "TechnicalInternal"
} | Select-Object -First 1
if ($null -eq $gameReadyMarker) {
    throw "CSV must classify the game ready-marker log string '- Giving Control to Human' as Skipped/TechnicalInternal, not ReviewRequired."
}

$gameComponentDiagnostic = $rows | Where-Object {
    $_.SourceFile -eq "source\AtTheGatesGame.original.exe" -and
    $_.Original -eq "CCanPillage component's parent lacks the required CCanAct component." -and
    $_.ReviewState -eq "Skipped" -and
    $_.ReasonCode -eq "TechnicalInternal"
} | Select-Object -First 1
if ($null -eq $gameComponentDiagnostic) {
    throw "CSV must classify Game component diagnostics as Skipped/TechnicalInternal, not ReviewRequired."
}

$gamePlagueDiagnostic = $rows | Where-Object {
    $_.SourceFile -eq "source\AtTheGatesGame.original.exe" -and
    $_.Original -eq "PlagueMgr.ApplyUnitPlagueDeath (1)" -and
    $_.ReviewState -eq "Skipped" -and
    $_.ReasonCode -eq "TechnicalInternal"
} | Select-Object -First 1
if ($null -eq $gamePlagueDiagnostic) {
    throw "CSV must classify Game PlagueMgr diagnostics as Skipped/TechnicalInternal, not ReviewRequired."
}

$registryPath = Join-Path $repoRoot "translations\localization-safety-registry.json"
if (!(Test-Path -LiteralPath $registryPath -PathType Leaf)) {
    throw "Canonical localization safety registry is missing: $registryPath"
}

$unresolvedRows = @($rows | Where-Object { $_.ReviewState -in @("ReviewRequired", "Skipped") })
if ($unresolvedRows.Count -eq 0) {
    throw "CSV must retain unresolved source rows for safety-first review."
}

$missingReason = $unresolvedRows | Where-Object {
    [string]::IsNullOrWhiteSpace($_.ReviewState) -or [string]::IsNullOrWhiteSpace($_.ReasonCode)
} | Select-Object -First 1
if ($null -ne $missingReason) {
    throw "CSV contains unresolved text without an explicit safety reason."
}

[pscustomobject]@{
    CsvPath = (Resolve-Path -LiteralPath $csvPath).Path
    RowCount = $rows.Count
}

Write-Host "Known text review export validation passed."
