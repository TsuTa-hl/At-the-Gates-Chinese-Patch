param()

$ErrorActionPreference = 'Stop'

$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$registryPath = Join-Path $root 'translations\localization-safety-registry.json'
if (!(Test-Path -LiteralPath $registryPath -PathType Leaf)) {
    throw "Localization safety registry is missing: $registryPath"
}

$bytes = [IO.File]::ReadAllBytes($registryPath)
if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xef -and $bytes[1] -eq 0xbb -and $bytes[2] -eq 0xbf) {
    throw 'Localization safety registry must be UTF-8 without BOM.'
}

$registry = Get-Content -LiteralPath $registryPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([int]$registry.SchemaVersion -ne 1) { throw 'Localization safety registry must use schema v1.' }
if ([string]$registry.CurrentPolicy.Strategy -ne 'SafetyFirst') { throw 'Safety registry must declare the safety-first policy.' }
if ([string]$registry.CurrentPolicy.ExploratoryBatchWorkflow -ne 'Retired') { throw 'Exploratory trial batches must remain retired.' }
if ([int]$registry.AcceptedCoverage.RetiredBatchCount -lt 1 -or [int]$registry.AcceptedCoverage.AcceptedEntries -lt 1) {
    throw 'Safety registry must retain the accepted historical coverage summary.'
}

foreach ($entry in @($registry.RejectedOperands)) {
    foreach ($field in @('Assembly', 'MethodToken', 'ILOffset', 'Original', 'Risk', 'Reason')) {
        if ($null -eq $entry.PSObject.Properties[$field] -or [string]::IsNullOrWhiteSpace([string]$entry.$field)) {
            throw "Rejected safety record is missing $field."
        }
    }
}

foreach ($mapName in @($registry.AcceptedCoverage.ActiveMapFamilies)) {
    $translationDirectory = Join-Path $root 'translations'
    if ($mapName.Contains('*')) {
        if (@(Get-ChildItem -LiteralPath $translationDirectory -Filter $mapName -File).Count -eq 0) {
            throw "Safety registry wildcard matched no active maps: $mapName"
        }
        continue
    }

    $path = Join-Path $translationDirectory $mapName
    if (!(Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Safety registry references a missing active map: $mapName"
    }
}

$retiredBatches = @(Get-ChildItem -LiteralPath (Join-Path $root 'translations') -Filter 'trial-*.json' -File)
if ($retiredBatches.Count -ne 0) {
    throw "Retired trial batch files remain in translations: $($retiredBatches.Name -join ', ')"
}

$strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
foreach ($jsonFile in @(Get-ChildItem -LiteralPath (Join-Path $root 'translations') -Filter '*.json' -File)) {
    $jsonBytes = [IO.File]::ReadAllBytes($jsonFile.FullName)
    if ($jsonBytes.Length -ge 3 -and $jsonBytes[0] -eq 0xef -and $jsonBytes[1] -eq 0xbb -and $jsonBytes[2] -eq 0xbf) {
        throw "Active JSON must be UTF-8 without BOM: $($jsonFile.Name)"
    }
    try {
        $jsonText = $strictUtf8.GetString($jsonBytes)
        $null = $jsonText | ConvertFrom-Json
    }
    catch {
        throw "Active JSON must be valid strict UTF-8 JSON: $($jsonFile.Name). $($_.Exception.Message)"
    }
}

$activeRewriteMaps = @(Get-ChildItem -LiteralPath (Join-Path $root 'translations') -Filter 'hardcoded-*-il-rewrite.json' -File)
foreach ($map in $activeRewriteMaps) {
    $mapText = [IO.File]::ReadAllText($map.FullName, $strictUtf8)
    if ($mapText -match '"EvidenceScenario"') {
        throw "Active rewrite map retains retired per-scenario evidence: $($map.Name)"
    }
    if ($mapText -match '(?im)^\s*"Note"\s*:\s*"[^\r\n"]*(?:\btrial\b|NeedsTrial|\bbatch\b|\b20\d\d-\d\d-\d\d\b)') {
        throw "Active rewrite map retains retired batch provenance in Note metadata: $($map.Name)"
    }
}

$compositePath = Join-Path $root 'translations\composite-text-rules.json'
$compositeText = [IO.File]::ReadAllText($compositePath, $strictUtf8)
if ($compositeText -match '(?im)^\s*"Notes"\s*:\s*"[^\r\n"]*(?:\btrial\b|NeedsTrial|\bbatch\b|\b20\d\d-\d\d-\d\d\b)') {
    throw 'Composite catalog retains retired batch provenance in Notes metadata.'
}

$knownTextExporter = Get-Content -LiteralPath (Join-Path $root 'tools\Export-KnownTextReview.ps1') -Raw -Encoding UTF8
if ($knownTextExporter -match 'trialBatchPaths|trial-localization-state|New-TrialAttemptIndex|EvidenceScenario') {
    throw 'Known-text export must read only the canonical safety registry, not retired trial batches.'
}

$compositeBuilder = Get-Content -LiteralPath (Join-Path $root 'tools\AtG.ManagedRewrite\CompositeTextCatalog.cs') -Raw -Encoding UTF8
if ($compositeBuilder -match 'trial-localization-state|knownRejectedSingles') {
    throw 'Composite catalog must derive rejected entries from the canonical safety registry.'
}

'Localization safety registry validation passed.'
