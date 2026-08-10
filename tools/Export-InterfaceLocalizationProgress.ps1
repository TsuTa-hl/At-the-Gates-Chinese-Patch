[CmdletBinding()]
param(
    [string]$ProjectRoot = "",
    [string]$RoutesPath = "",
    [string]$OutputDirectory = "",
    [string]$KnownTextCsvPath = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Get-AtGFullPath {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$Root)
    if ([IO.Path]::IsPathRooted($Path)) { return [IO.Path]::GetFullPath($Path) }
    return [IO.Path]::GetFullPath((Join-Path $Root $Path))
}

function Test-AtGPathWithin {
    param([Parameter(Mandatory = $true)][string]$Candidate, [Parameter(Mandatory = $true)][string]$Parent)
    $candidateFull = [IO.Path]::GetFullPath($Candidate).TrimEnd([char[]]"\\/")
    $parentFull = [IO.Path]::GetFullPath($Parent).TrimEnd([char[]]"\\/")
    return $candidateFull.Equals($parentFull, [StringComparison]::OrdinalIgnoreCase) -or
        $candidateFull.StartsWith($parentFull + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
}

function Get-AtGProperty {
    param([object]$Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Get-AtGString {
    param([object]$Object, [string]$Name)
    $value = Get-AtGProperty -Object $Object -Name $Name
    if ($null -eq $value) { return "" }
    return [string]$value
}

function Get-AtGArray {
    param([object]$Object, [string]$Name)
    $value = Get-AtGProperty -Object $Object -Name $Name
    if ($null -eq $value) { return @() }
    return @($value)
}

function Normalize-AtGPathKey {
    param([string]$Value)
    return ([string]$Value).Replace('/', '\\').Trim().ToLowerInvariant()
}

function Get-AtGSha256 {
    param([string]$Value)
    $bytes = [Text.Encoding]::UTF8.GetBytes($Value)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Test-AtGListContains {
    param([object[]]$Values, [string]$Candidate)
    foreach ($value in @($Values)) {
        if ([string]$value -eq $Candidate) { return $true }
    }
    return $false
}

function Test-AtGLocatorPrefix {
    param([string]$Locators, [object[]]$Prefixes)
    foreach ($prefix in @($Prefixes)) {
        foreach ($locator in @($Locators -split '\s+\|\s+')) {
            if ($locator.Trim().StartsWith([string]$prefix, [StringComparison]::Ordinal)) { return $true }
        }
    }
    return $false
}

function Get-AtGLocatorValue {
    param([string]$Locators, [string]$Name)
    $match = [regex]::Match($Locators, "(?:^|[;|]\\s*)" + [regex]::Escape($Name) + "=(?<value>[^;|]*)")
    if (!$match.Success) { return "" }
    return $match.Groups['value'].Value.Trim()
}

function Test-AtGKnownTextReference {
    param([object]$Reference, [object]$Row)

    if ((Normalize-AtGPathKey (Get-AtGString $Reference 'SourceFile')) -ne (Normalize-AtGPathKey ([string]$Row.SourceFile))) {
        return $false
    }
    if ((Get-AtGString $Reference 'Original') -and (Get-AtGString $Reference 'Original') -ne [string]$Row.Original) {
        return $false
    }

    $locators = [string]$Row.Locators
    $methodToken = Get-AtGString $Reference 'MethodToken'
    if ($methodToken) {
        return (Get-AtGLocatorValue $locators 'MethodToken') -eq $methodToken -and
            (Get-AtGLocatorValue $locators 'ILOffset') -eq (Get-AtGString $Reference 'ILOffset')
    }

    $configId = Get-AtGString $Reference 'ConfigId'
    if ($configId) {
        if ((Get-AtGLocatorValue $locators 'ID') -ne $configId -or
            (Get-AtGLocatorValue $locators 'XPath') -ne (Get-AtGString $Reference 'ConfigXPath')) { return $false }
        $index = Get-AtGString $Reference 'ConfigIndex'
        return !$index -or (Get-AtGLocatorValue $locators 'Index') -eq $index
    }

    $textKey = Get-AtGString $Reference 'TextKey'
    if ($textKey) {
        return @($locators -split '\s+\|\s+') -contains $textKey
    }

    $runtimeSection = Get-AtGString $Reference 'RuntimeMapSection'
    if ($runtimeSection) {
        return (Get-AtGLocatorValue $locators 'RuntimeMapSection') -eq $runtimeSection -and
            (Get-AtGLocatorValue $locators 'RuntimeMapOriginal') -eq (Get-AtGString $Reference 'RuntimeMapOriginal') -and
            (Get-AtGLocatorValue $locators 'RuntimeMapConceptKey') -eq (Get-AtGString $Reference 'RuntimeMapConceptKey')
    }

    return $false
}

function Get-AtGSourceState {
    param([object]$Row)
    if ([string]$Row.ReviewState -eq 'Translated') {
        if ([string]::IsNullOrWhiteSpace([string]$Row.Translation)) { return 'NeedsTranslation' }
        if ([string]$Row.Translation -eq [string]$Row.Original) { return 'UnchangedTranslation' }
        return 'Localized'
    }
    if ([string]$Row.ReviewState -eq 'Rejected') { return 'Rejected' }
    if ([string]$Row.ReviewState -eq 'Skipped') { return 'Excluded' }
    return 'NeedsTranslation'
}

function Test-AtGRoute {
    param([object]$Route, [object]$Item)
    $match = $Route.Match
    $sourceFiles = Get-AtGArray $match 'SourceFiles'
    if (@($sourceFiles).Count -gt 0 -and -not (@($sourceFiles | Where-Object {
        (Normalize-AtGPathKey ([string]$_)) -eq (Normalize-AtGPathKey $Item.SourceFile)
    }).Count -gt 0)) { return $false }
    $kinds = Get-AtGArray $match 'Kinds'
    $reviewStates = Get-AtGArray $match 'ReviewStates'
    $safetyValues = Get-AtGArray $match 'SafetyValues'
    $locatorPrefixes = Get-AtGArray $match 'LocatorPrefixes'
    $typeFullNames = Get-AtGArray $match 'TypeFullNames'
    $ruleIds = Get-AtGArray $match 'RuleIds'
    if (@($kinds).Count -gt 0 -and -not (Test-AtGListContains -Values $kinds -Candidate $Item.Kind)) { return $false }
    if (@($reviewStates).Count -gt 0 -and -not (Test-AtGListContains -Values $reviewStates -Candidate $Item.ReviewState)) { return $false }
    if (@($safetyValues).Count -gt 0 -and -not (Test-AtGListContains -Values $safetyValues -Candidate $Item.Safety)) { return $false }
    if (@($locatorPrefixes).Count -gt 0 -and -not (Test-AtGLocatorPrefix -Locators $Item.Locators -Prefixes $locatorPrefixes)) { return $false }
    if (@($typeFullNames).Count -gt 0 -and -not (@($Item.TypeFullNames | Where-Object {
        Test-AtGListContains -Values $typeFullNames -Candidate ([string]$_)
    }).Count -gt 0)) { return $false }
    if (@($ruleIds).Count -gt 0 -and -not (@($Item.RuleIds | Where-Object {
        Test-AtGListContains -Values $ruleIds -Candidate ([string]$_)
    }).Count -gt 0)) { return $false }
    return $true
}

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}
else {
    $ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
}
if ([string]::IsNullOrWhiteSpace($RoutesPath)) { $RoutesPath = Join-Path $ProjectRoot 'docs\agent\interface-localization-routes.json' }
else { $RoutesPath = Get-AtGFullPath -Path $RoutesPath -Root $ProjectRoot }
if (!(Test-Path -LiteralPath $RoutesPath -PathType Leaf)) { throw "Interface route ledger was not found: $RoutesPath" }

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $runId = 'run-' + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ')
    $OutputDirectory = Join-Path $ProjectRoot (Join-Path '.tmp\interface-localization-progress' $runId)
}
else { $OutputDirectory = Get-AtGFullPath -Path $OutputDirectory -Root $ProjectRoot }
foreach ($protected in @('docs\agent', 'docs\review', 'translations', 'source', 'patch', '.cache')) {
    if (Test-AtGPathWithin -Candidate $OutputDirectory -Parent (Join-Path $ProjectRoot $protected)) {
        throw "Progress review output must stay in a task-local .tmp directory: $OutputDirectory"
    }
}
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null

$rawKnownTextPath = ''
$catalogValidationError = ''
$catalogState = 'ProvidedSnapshot'
if (![string]::IsNullOrWhiteSpace($KnownTextCsvPath)) {
    $rawKnownTextPath = Get-AtGFullPath -Path $KnownTextCsvPath -Root $ProjectRoot
    if (!(Test-Path -LiteralPath $rawKnownTextPath -PathType Leaf)) { throw "KnownText CSV was not found: $rawKnownTextPath" }
}
else {
    $catalogDirectory = Join-Path $OutputDirectory '.catalog'
    New-Item -ItemType Directory -Force -Path $catalogDirectory | Out-Null
    $rawKnownTextPath = Join-Path $catalogDirectory 'known-texts.csv'
    try {
        & (Join-Path $ProjectRoot 'tools\Export-KnownTextReview.ps1') `
            -CsvOutputPath $rawKnownTextPath `
            -DiscoveryCacheDirectory (Join-Path $catalogDirectory 'discovery') `
            -CatalogDatabasePath (Join-Path $catalogDirectory 'atg-catalog.sqlite') `
            -CompositeRulesPath (Join-Path $ProjectRoot 'translations\composite-text-rules.json') `
            -AggregateDuplicates | Out-Host
        $catalogState = 'Validated'
    }
    catch {
        $catalogValidationError = $_.Exception.Message
        $catalogState = 'ValidationFailed'
    }
    if ($catalogState -eq 'ValidationFailed' -or !(Test-Path -LiteralPath $rawKnownTextPath -PathType Leaf)) {
        $failurePath = Join-Path $OutputDirectory 'interface-localization-failure.json'
        $failure = [ordered]@{
            SchemaVersion = 1
            GeneratedAtUtc = [DateTime]::UtcNow.ToString('o')
            CatalogState = $catalogState
            Error = $catalogValidationError
            OutputDirectory = $OutputDirectory
            KnownTextPath = $rawKnownTextPath
            CompletionAllowed = $false
        }
        [IO.File]::WriteAllText($failurePath, ($failure | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding($false)))
        throw "KnownText rebuild failed: $rawKnownTextPath. $catalogValidationError"
    }
}

$knownRows = @(Import-Csv -LiteralPath $rawKnownTextPath -Encoding UTF8)
if (@($knownRows).Count -eq 0) { throw "KnownText CSV is empty: $rawKnownTextPath" }
foreach ($field in @('SourceFile', 'Kind', 'Original', 'Translation', 'Status', 'ReviewState', 'ReasonCode', 'Safety', 'Notes', 'Locators')) {
    if ($null -eq $knownRows[0].PSObject.Properties[$field]) { throw "KnownText CSV is missing required column '$field'." }
}

$routeLedger = Get-Content -LiteralPath $RoutesPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([int]$routeLedger.SchemaVersion -ne 1 -or @($routeLedger.Routes).Count -eq 0) { throw 'Interface route ledger must be schema v1 with at least one route.' }
$routes = @($routeLedger.Routes | Sort-Object Priority, RouteId)
$routeIds = @($routes | ForEach-Object { [string]$_.RouteId })
if (@($routeIds | Select-Object -Unique).Count -ne @($routeIds).Count) { throw 'Interface route ledger contains duplicate RouteId values.' }

$rulesPath = Join-Path $ProjectRoot 'translations\composite-text-rules.json'
$composite = Get-Content -LiteralPath $rulesPath -Raw -Encoding UTF8 | ConvertFrom-Json
$referencesBySourceAndOriginal = @{}
foreach ($entry in @($composite.Entries)) {
    foreach ($part in @($entry.Parts)) {
        $reference = Get-AtGProperty -Object $part -Name 'KnownTextReference'
        if ($null -eq $reference) { continue }
        $referenceOriginal = [string](Get-AtGProperty -Object $part -Name 'Value')
        $referenceSource = Normalize-AtGPathKey (Get-AtGString $reference 'SourceFile')
        if (!$referenceSource -or !$referenceOriginal) { continue }
        $key = $referenceSource + [char]31 + $referenceOriginal
        if (!$referencesBySourceAndOriginal.ContainsKey($key)) { $referencesBySourceAndOriginal[$key] = New-Object System.Collections.Generic.List[object] }
        $referencesBySourceAndOriginal[$key].Add([pscustomobject]@{
            EntryPointId = Get-AtGString $entry 'EntryPointId'
            RuleId = Get-AtGString $entry 'RuleId'
            TypeFullName = Get-AtGString $entry.Source 'TypeFullName'
            Reference = $reference
        }) | Out-Null
    }
}

. (Join-Path $ProjectRoot 'tools\AtGLocalizationInputDigest.ps1')
$localizationInputs = Get-AtGLocalizationInputDigest -ProjectRoot $ProjectRoot
$buildState = 'Unavailable'
$buildReportPath = Join-Path $ProjectRoot 'patch\.atg-build-report.json'
if (Test-Path -LiteralPath $buildReportPath -PathType Leaf) {
    $buildReport = Get-Content -LiteralPath $buildReportPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $reportInputs = Get-AtGProperty -Object $buildReport -Name 'LocalizationInputs'
    $reportDigest = Get-AtGString $reportInputs 'Digest'
    if ($reportDigest) {
        $buildState = if ($reportDigest -eq $localizationInputs.Digest) { 'Current' } else { 'Stale' }
    }
}

$items = foreach ($row in $knownRows) {
    $referenceKey = (Normalize-AtGPathKey ([string]$row.SourceFile)) + [char]31 + [string]$row.Original
    $references = @()
    if ($referencesBySourceAndOriginal.ContainsKey($referenceKey)) {
        $references = @($referencesBySourceAndOriginal[$referenceKey] | Where-Object {
            Test-AtGKnownTextReference -Reference $_.Reference -Row $row
        })
    }
    $typeFullNames = New-Object System.Collections.Generic.List[string]
    $locatorType = Get-AtGLocatorValue ([string]$row.Locators) 'TypeFullName'
    if ($locatorType) { $typeFullNames.Add($locatorType) | Out-Null }
    foreach ($type in @($references | ForEach-Object { Get-AtGString $_ 'TypeFullName' } | Where-Object { $_ })) {
        if (!$typeFullNames.Contains($type)) { $typeFullNames.Add($type) | Out-Null }
    }
    $ruleIds = @($references | ForEach-Object { Get-AtGString $_ 'RuleId' } | Where-Object { $_ } | Sort-Object -Unique)
    $entryPointIds = @($references | ForEach-Object { Get-AtGString $_ 'EntryPointId' } | Where-Object { $_ } | Sort-Object -Unique)
    $sourceTraceState = if ([string]::IsNullOrWhiteSpace([string]$row.Locators)) { 'MissingSourceLocator' } else { 'ExactSourceLocator' }
    $entryTraceState = if (@($entryPointIds).Count -eq 0) { 'NotComposite' } elseif ($catalogState -eq 'Validated') { 'Validated' } else { 'MatchedUnvalidated' }
    $candidate = [pscustomobject]@{
        SourceFile = [string]$row.SourceFile
        Kind = [string]$row.Kind
        Original = [string]$row.Original
        Translation = [string]$row.Translation
        Status = [string]$row.Status
        ReviewState = [string]$row.ReviewState
        ReasonCode = [string]$row.ReasonCode
        Safety = [string]$row.Safety
        Notes = [string]$row.Notes
        Locators = [string]$row.Locators
        TypeFullNames = @($typeFullNames | Sort-Object -Unique)
        EntryPointIds = $entryPointIds
        RuleIds = $ruleIds
        SourceTraceState = $sourceTraceState
        EntryPointTraceState = $entryTraceState
        SourceState = Get-AtGSourceState -Row $row
    }
    $routeMatches = @($routes | Where-Object { Test-AtGRoute -Route $_ -Item $candidate })
    if (@($routeMatches).Count -gt 1 -and [int]$routeMatches[0].Priority -eq [int]$routeMatches[1].Priority) {
        throw "Known text '$($candidate.SourceFile):$($candidate.Locators)' matches multiple routes at priority $($routeMatches[0].Priority): $($routeMatches[0].RouteId), $($routeMatches[1].RouteId)."
    }
    $route = if (@($routeMatches).Count -gt 0) { $routeMatches[0] } else { $null }
    $routeId = if ($null -ne $route) { [string]$route.RouteId } else { 'Unclassified' }
    $interface = if ($null -ne $route) { [string]$route.Interface } else { 'Unclassified' }
    $surface = if ($null -ne $route) { [string]$route.Surface } else { 'Unknown' }
    $trigger = if ($null -ne $route) { [string]$route.Trigger } else { 'Unknown' }
    $playerVisible = $null -ne $route -and [bool]$route.PlayerVisible
    $needsTranslation = $null -ne $route -and [bool]$route.NeedsTranslation
    $visibleCandidate = $playerVisible -and $needsTranslation -and $candidate.SourceState -notin @('Excluded')
    [pscustomobject][ordered]@{
        ItemId = 'ILP-' + (Get-AtGSha256 ($candidate.SourceFile + "`n" + $candidate.Kind + "`n" + $candidate.Locators + "`n" + $candidate.Original + "`n" + $candidate.Translation + "`n" + $candidate.Status)).Substring(0, 16)
        RouteId = $routeId
        Interface = $interface
        Surface = $surface
        Trigger = $trigger
        PlayerVisible = $playerVisible
        NeedsTranslation = $needsTranslation
        VisibleTranslatableCandidate = $visibleCandidate
        SourceState = $candidate.SourceState
        SourceTraceState = $candidate.SourceTraceState
        EntryPointTraceState = $candidate.EntryPointTraceState
        BuildArtifactState = $buildState
        SourceFile = $candidate.SourceFile
        Kind = $candidate.Kind
        Original = $candidate.Original
        Translation = $candidate.Translation
        Status = $candidate.Status
        ReviewState = $candidate.ReviewState
        ReasonCode = $candidate.ReasonCode
        Safety = $candidate.Safety
        Locators = $candidate.Locators
        TypeFullNames = ($candidate.TypeFullNames -join ';')
        EntryPointIds = ($candidate.EntryPointIds -join ';')
        RuleIds = ($candidate.RuleIds -join ';')
        Notes = $candidate.Notes
    }
}

$summary = foreach ($group in @($items | Group-Object RouteId, Interface, Surface, Trigger | Sort-Object Name)) {
    $groupItems = @($group.Group)
    $allKnown = @($groupItems).Count
    $tracked = @($groupItems | Where-Object { $_.RouteId -ne 'Unclassified' }).Count
    $visible = @($groupItems | Where-Object { $_.VisibleTranslatableCandidate }).Count
    $localized = @($groupItems | Where-Object { $_.VisibleTranslatableCandidate -and $_.SourceState -eq 'Localized' -and $_.SourceTraceState -eq 'ExactSourceLocator' }).Count
    [pscustomobject][ordered]@{
        RouteId = $groupItems[0].RouteId
        Interface = $groupItems[0].Interface
        Surface = $groupItems[0].Surface
        Trigger = $groupItems[0].Trigger
        AllKnownCount = $allKnown
        AllKnownTrackedCount = $tracked
        AllKnownTrackingRate = if ($allKnown -eq 0) { 0 } else { [math]::Round(100 * $tracked / $allKnown, 2) }
        VisibleTranslatableCount = $visible
        VisibleLocalizedCount = $localized
        VisibleLocalizationRate = if ($visible -eq 0) { $null } else { [math]::Round(100 * $localized / $visible, 2) }
        NeedsTranslationCount = @($groupItems | Where-Object { $_.SourceState -eq 'NeedsTranslation' }).Count
        UnchangedTranslationCount = @($groupItems | Where-Object { $_.SourceState -eq 'UnchangedTranslation' }).Count
        ExcludedCount = @($groupItems | Where-Object { $_.SourceState -eq 'Excluded' }).Count
        RejectedCount = @($groupItems | Where-Object { $_.SourceState -eq 'Rejected' }).Count
        ValidatedEntryPointCount = @($groupItems | Where-Object { $_.EntryPointTraceState -eq 'Validated' }).Count
        MatchedUnvalidatedEntryPointCount = @($groupItems | Where-Object { $_.EntryPointTraceState -eq 'MatchedUnvalidated' }).Count
        BuildArtifactState = $buildState
    }
}

$summaryPath = Join-Path $OutputDirectory 'interface-localization-summary.csv'
$itemsPath = Join-Path $OutputDirectory 'interface-localization-items.csv'
$metadataPath = Join-Path $OutputDirectory 'interface-localization-metadata.json'
$summary | Export-Csv -LiteralPath $summaryPath -NoTypeInformation -Encoding UTF8
$items | Export-Csv -LiteralPath $itemsPath -NoTypeInformation -Encoding UTF8
$metadata = [ordered]@{
    SchemaVersion = 1
    GeneratedAtUtc = [DateTime]::UtcNow.ToString('o')
    ProjectRoot = $ProjectRoot
    RouteLedger = (Resolve-Path -LiteralPath $RoutesPath).Path
    KnownTextCsv = (Resolve-Path -LiteralPath $rawKnownTextPath).Path
    CatalogState = $catalogState
    CatalogValidationError = $catalogValidationError
    LocalizationInputs = $localizationInputs
    BuildArtifactState = $buildState
    BuildReportPath = if (Test-Path -LiteralPath $buildReportPath -PathType Leaf) { $buildReportPath } else { $null }
    Totals = [ordered]@{
        AllKnownCount = @($items).Count
        AllKnownTrackedCount = @($items | Where-Object { $_.RouteId -ne 'Unclassified' }).Count
        VisibleTranslatableCount = @($items | Where-Object { $_.VisibleTranslatableCandidate }).Count
        VisibleLocalizedCount = @($items | Where-Object { $_.VisibleTranslatableCandidate -and $_.SourceState -eq 'Localized' -and $_.SourceTraceState -eq 'ExactSourceLocator' }).Count
        UnclassifiedCount = @($items | Where-Object { $_.RouteId -eq 'Unclassified' }).Count
    }
    CompletionFormula = [ordered]@{
        VisibleLocalization = 'VisibleLocalizedCount / VisibleTranslatableCount; excludes SourceState=Excluded and never uses black-box evidence.'
        AllKnownTracking = 'AllKnownTrackedCount / AllKnownCount; Unclassified remains in the denominator.'
    }
    Outputs = [ordered]@{ SummaryCsv = $summaryPath; ItemsCsv = $itemsPath; MetadataJson = $metadataPath }
}
[IO.File]::WriteAllText($metadataPath, ($metadata | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($false)))

[pscustomobject]@{
    OutputDirectory = $OutputDirectory
    SummaryCsv = $summaryPath
    ItemsCsv = $itemsPath
    MetadataJson = $metadataPath
    CatalogState = $catalogState
    BuildArtifactState = $buildState
    AllKnownCount = @($items).Count
    VisibleTranslatableCount = $metadata.Totals.VisibleTranslatableCount
    VisibleLocalizedCount = $metadata.Totals.VisibleLocalizedCount
    UnclassifiedCount = $metadata.Totals.UnclassifiedCount
}
