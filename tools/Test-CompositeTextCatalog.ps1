param(
    [string]$RulesPath = "$PSScriptRoot\..\translations\composite-text-rules.json",
    [string]$OutputDirectory = "$PSScriptRoot\..\.tmp\composite-text-catalog-test"
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$OutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
$reviewViewGeneratorPath = Join-Path $repoRoot "docs\review\Generate-ReviewViews.ps1"
$CsvPath = Join-Path $OutputDirectory "composite-text-localization.csv"

if (!(Test-Path -LiteralPath $RulesPath -PathType Leaf)) {
    throw "Composite text rules were not generated: $RulesPath"
}

& $reviewViewGeneratorPath -View Composite -OutputDirectory $OutputDirectory | Out-Host
if (!(Test-Path -LiteralPath $CsvPath -PathType Leaf)) {
    throw "Composite text CSV view was not generated: $CsvPath"
}
if ((Test-Path -LiteralPath (Join-Path $OutputDirectory "composite-text-localization.md") -PathType Leaf) -or
    (Test-Path -LiteralPath (Join-Path $OutputDirectory "composite-text") -PathType Container)) {
    throw "Composite review view generation must not emit Markdown indexes or shards."
}

$catalog = Get-Content -LiteralPath $RulesPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([int]$catalog.SchemaVersion -lt 2) {
    throw "Composite text catalog schema must be at least version 2; found '$($catalog.SchemaVersion)'."
}

$entries = @($catalog.Entries)
$rules = @($catalog.Rules)
if ($entries.Count -lt 1000) {
    throw "Composite text catalog has too few entries: $($entries.Count)."
}
if ($rules.Count -eq 0) {
    throw "Composite text catalog has no reusable rules."
}

$entryIds = @($entries | ForEach-Object { [string]$_.EntryPointId })
if (($entryIds | Sort-Object -Unique).Count -ne $entryIds.Count) {
    throw "Composite text catalog contains duplicate EntryPointId values."
}

$ruleIds = @($rules | ForEach-Object { [string]$_.RuleId })
if (($ruleIds | Sort-Object -Unique).Count -ne $ruleIds.Count) {
    throw "Composite text catalog contains duplicate RuleId values."
}

$invalidRuleBindings = @($entries | Where-Object {
    -not [string]::IsNullOrWhiteSpace([string]$_.RuleId) -and
    $ruleIds -notcontains [string]$_.RuleId
})
if ($invalidRuleBindings.Count -gt 0) {
    $sample = $invalidRuleBindings | Select-Object -First 5 | ForEach-Object {
        "$($_.EntryPointId) -> $($_.RuleId)"
    }
    throw "Composite text catalog has $($invalidRuleBindings.Count) invalid RuleId binding(s): $($sample -join '; ')"
}

if ($ruleIds -notcontains "runtime-richtext-final-process") {
    throw "Composite text catalog is missing the runtime-richtext-final-process rule."
}
if ($ruleIds -notcontains "runtime-display-template") {
    throw "Composite text catalog is missing the runtime-display-template rule."
}

$missingAudit = @($entries | Where-Object {
    [string]::IsNullOrWhiteSpace([string]$_.AuditStatus) -or
    [string]::IsNullOrWhiteSpace([string]$_.RuleScope)
})
if ($missingAudit.Count -gt 0) {
    throw "Composite text catalog has $($missingAudit.Count) entry point(s) without audit status or rule scope."
}

$unreviewedCompositions = @($entries | Where-Object {
    [string]$_.Source.Kind -eq "Managed" -and @($_.Parts).Count -gt 1 -and
    [string]$_.AuditStatus -eq "Unreviewed"
})
if ($unreviewedCompositions.Count -gt 0) {
    throw "Composite text catalog has $($unreviewedCompositions.Count) unreviewed managed composition entry point(s)."
}

$rewriteEntries = @($entries | Where-Object {
    [string]$_.Source.Kind -eq "ManagedRewriteMap" -and
    ![string]::IsNullOrWhiteSpace([string]$_.LocalizedFormat)
})
$unruledConflicts = @()
foreach ($entry in @($entries | Where-Object {
    [string]$_.Source.Kind -eq "Managed" -and @($_.Parts).Count -gt 1 -and
    [string]$_.AuditStatus -eq "ReviewedNoSafeRule"
})) {
    foreach ($part in @($entry.Parts | Where-Object {
        [string]$_.Kind -eq "Literal" -and [string]$_.Value -match "[A-Za-z]" -and
        [string]$_.Value -notmatch "[\[\]\|]"
    })) {
        $translations = @($rewriteEntries | Where-Object {
            [string]$_.OriginalFormat -ceq [string]$part.Value
        } | ForEach-Object { [string]$_.LocalizedFormat } | Sort-Object -Unique)
        if ($translations.Count -gt 1) {
            $unruledConflicts += "$($entry.EntryPointId) :: $($part.Value)"
        }
    }
}
if ($unruledConflicts.Count -gt 0) {
    throw "Composite text catalog has conflicting fragments without an entry-specific rule: $($unruledConflicts -join '; ')"
}

$legacyEnnobleTranslation = "[" + [char]0x518C + [char]0x5C01 + "|NOBLE]"
$legacyEnnoble = @($entries | Where-Object {
    [string]$_.OriginalFormat -eq "[Ennoble]" -and
    [string]$_.LocalizedFormat -eq $legacyEnnobleTranslation
})
if ($legacyEnnoble.Count -eq 0) {
    throw "Composite text catalog must preserve the legacy [Ennoble] NOBLE concept alias."
}

$csvRows = @(Import-Csv -LiteralPath $CsvPath -Encoding UTF8)
if ($csvRows.Count -ne ($entries.Count + $rules.Count)) {
    throw "Composite text CSV row count $($csvRows.Count) does not match JSON entries plus rules ($($entries.Count + $rules.Count))."
}
$entryRows = @($csvRows | Where-Object { $_.RowKind -eq "Entry" })
$ruleRows = @($csvRows | Where-Object { $_.RowKind -eq "Rule" })
if ($entryRows.Count -ne $entries.Count -or $ruleRows.Count -ne $rules.Count) {
    throw "Composite text CSV must retain every entry and every reusable rule."
}
foreach ($column in @("RowKind", "EntryPointId", "OriginalFormat", "LocalizedFormat", "RuleId", "AuditStatus", "PartsJson")) {
    if ($csvRows.Count -gt 0 -and -not $csvRows[0].PSObject.Properties[$column]) {
        throw "Composite text CSV is missing required column: $column"
    }
}
if (@($csvRows | Where-Object { $_.RowKind -eq "Rule" -and $_.RuleId -eq "runtime-richtext-final-process" }).Count -eq 0) {
    throw "Composite text CSV is missing the runtime rich-text rule."
}
if (@($csvRows | Where-Object {
    $_.RowKind -eq "Entry" -and [string]::IsNullOrWhiteSpace([string]$_.EntryPointId)
}).Count -gt 0) {
    throw "Composite text CSV contains a row without EntryPointId."
}

Write-Host "Composite text catalog validation passed: $($entries.Count) entries, $($rules.Count) rules, schema $($catalog.SchemaVersion)."
