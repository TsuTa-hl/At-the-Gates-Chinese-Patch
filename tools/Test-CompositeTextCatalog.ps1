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
if ([int]$catalog.SchemaVersion -lt 7) {
    throw "Composite text catalog schema must be at least version 7; found '$($catalog.SchemaVersion)'."
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

$knownTextReferenceParts = @(
    foreach ($entry in $entries) {
        foreach ($part in @($entry.Parts | Where-Object { $null -ne $_.KnownTextReference })) {
            [pscustomobject]@{
                EntryPointId = [string]$entry.EntryPointId
                SourceKind = [string]$entry.Source.Kind
                Part = $part
                Reference = $part.KnownTextReference
            }
        }
    }
)
if ($knownTextReferenceParts.Count -eq 0) {
    throw "Composite text catalog has no durable KnownTextReference records."
}
$literalPartsWithoutReference = @(
    foreach ($entry in $entries) {
        foreach ($part in @($entry.Parts | Where-Object {
            [string]$_.Kind -eq "Literal" -and $null -eq $_.KnownTextReference
        })) {
            [pscustomobject]@{
                EntryPointId = [string]$entry.EntryPointId
                SourceKind = [string]$entry.Source.Kind
                Part = $part
            }
        }
    }
)
if ($literalPartsWithoutReference.Count -gt 0) {
    throw "Composite text catalog has $($literalPartsWithoutReference.Count) literal part(s) without a durable KnownText reference."
}
$runtimeMapKnownTextParts = @($knownTextReferenceParts | Where-Object {
    [string]$_.SourceKind -eq "RuntimeMap"
})
$runtimeDisplayMap = Get-Content -LiteralPath (Join-Path $repoRoot "translations\runtime-display-strings.json") -Raw -Encoding UTF8 | ConvertFrom-Json
$expectedRuntimeMapBindings = @(
    foreach ($section in @("Exact", "PlainText", "PlainTextFragments", "RichTextFragments", "Templates", "ConceptDisplay")) {
        foreach ($entry in @($runtimeDisplayMap.$section)) {
            if ($null -ne $entry -and ![string]::IsNullOrWhiteSpace([string]$entry.Original) -and
                $null -ne $entry.Translation) {
                $entry
            }
        }
    }
)
if ($runtimeMapKnownTextParts.Count -ne $expectedRuntimeMapBindings.Count -or @($runtimeMapKnownTextParts | Where-Object {
    $reference = $_.Reference
    ([string]$reference.SourceFile).Replace("\", "/") -cne "translations/runtime-display-strings.json" -or
    [string]::IsNullOrWhiteSpace([string]$reference.RuntimeMapSection) -or
    [string]::IsNullOrWhiteSpace([string]$reference.RuntimeMapOriginal) -or
    (([string]$reference.RuntimeMapSection -eq "ConceptDisplay") -and
        [string]::IsNullOrWhiteSpace([string]$reference.RuntimeMapConceptKey)) -or
    (([string]$reference.RuntimeMapSection -ne "ConceptDisplay") -and
        -not [string]::IsNullOrWhiteSpace([string]$reference.RuntimeMapConceptKey))
}).Count -gt 0) {
    throw "Every runtime-map literal must persist a stable runtime-display-map KnownText locator (expected $($expectedRuntimeMapBindings.Count), found $($runtimeMapKnownTextParts.Count))."
}
$invalidKnownTextReference = @($knownTextReferenceParts | Where-Object {
    $reference = $_.Reference
    $hasManaged = ![string]::IsNullOrWhiteSpace([string]$reference.MethodToken) -or $null -ne $reference.ILOffset
    $hasXml = ![string]::IsNullOrWhiteSpace([string]$reference.XPath)
    $hasKey = ![string]::IsNullOrWhiteSpace([string]$reference.TextKey)
    $hasConfig = ![string]::IsNullOrWhiteSpace([string]$reference.ConfigId) -or
        ![string]::IsNullOrWhiteSpace([string]$reference.ConfigXPath) -or $null -ne $reference.ConfigIndex
    $hasRuntimeMap = ![string]::IsNullOrWhiteSpace([string]$reference.RuntimeMapSection) -or
        ![string]::IsNullOrWhiteSpace([string]$reference.RuntimeMapOriginal) -or
        ![string]::IsNullOrWhiteSpace([string]$reference.RuntimeMapConceptKey)
    [string]$_.Part.Kind -ne "Literal" -or
    [string]::IsNullOrWhiteSpace([string]$reference.SourceFile) -or
    [string]$reference.Original -cne [string]$_.Part.Value -or
    (([int]$hasManaged + [int]$hasXml + [int]$hasKey + [int]$hasConfig + [int]$hasRuntimeMap) -ne 1) -or
    ($hasManaged -and ([string]::IsNullOrWhiteSpace([string]$reference.MethodToken) -or $null -eq $reference.ILOffset)) -or
    ($hasKey -and [string]$reference.TextKey -notmatch '^(TEXT|TRAIT|FACTION|DISCIPLINE|UNIT|RESOURCE|TERRAIN|RIVER|BONUS|JOB|PROFESSION)[\._]') -or
    ($hasConfig -and ([string]::IsNullOrWhiteSpace([string]$reference.ConfigId) -or
        [string]::IsNullOrWhiteSpace([string]$reference.ConfigXPath))) -or
    ($hasRuntimeMap -and (
        ([string]$reference.SourceFile).Replace("\", "/") -cne "translations/runtime-display-strings.json" -or
        [string]::IsNullOrWhiteSpace([string]$reference.RuntimeMapSection) -or
        [string]::IsNullOrWhiteSpace([string]$reference.RuntimeMapOriginal) -or
        (([string]$reference.RuntimeMapSection -eq "ConceptDisplay") -and
            [string]::IsNullOrWhiteSpace([string]$reference.RuntimeMapConceptKey)) -or
        (([string]$reference.RuntimeMapSection -ne "ConceptDisplay") -and
            -not [string]::IsNullOrWhiteSpace([string]$reference.RuntimeMapConceptKey))))
})
if ($invalidKnownTextReference.Count -gt 0) {
    throw "Composite text catalog has $($invalidKnownTextReference.Count) invalid durable KnownTextReference record(s)."
}

$apiaryEntry = @($entries | Where-Object {
    [string]$_.OriginalFormat -like "Apiaries are a *"
} | Select-Object -First 1)
if ($apiaryEntry.Count -ne 1 -or
    [string]$apiaryEntry[0].Parts[0].KnownTextReference.ConfigId -ne "STRUCTURE_APIARY_1" -or
    [string]$apiaryEntry[0].Parts[0].KnownTextReference.ConfigXPath -ne "description") {
    throw "Composite text catalog must persist the config ID/XPath locator for the Apiary description."
}

$englishTextKeyReference = @($knownTextReferenceParts | Where-Object {
    [string]$_.Reference.TextKey -eq "TEXT.Credits.Conifer" -and
    [string]$_.Part.Value -like "*Designer and Gameplay Programmer*"
})
if ($englishTextKeyReference.Count -eq 0) {
    throw "Composite text catalog must persist the English text-key locator for TEXT.Credits.Conifer."
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

$auditedCompositions = @($entries | Where-Object {
    ([string]$_.Source.Kind -eq "Managed" -and @($_.Parts).Count -gt 1) -or
    # XML source files are a complete static inventory. Only XML nodes that
    # already bind to a patch rule are active composition entry points here;
    # untouched config prose remains reviewable in the static source catalog
    # and must not make a narrow, ID-scoped config patch look complete.
    ([string]$_.Source.Kind -eq "Xml" -and
        [string]$_.Classification -eq "DisplayComposite" -and
        (-not [string]::IsNullOrWhiteSpace([string]$_.RuleId) -or
            $null -ne $_.LocalizedFormat))
})
$unreviewedCompositions = @($auditedCompositions | Where-Object {
    [string]$_.AuditStatus -eq "Unreviewed"
})
if ($unreviewedCompositions.Count -gt 0) {
    throw "Composite text catalog has $($unreviewedCompositions.Count) unreviewed Managed or XML composition entry point(s)."
}

$nonterminalCompositions = @($auditedCompositions | Where-Object {
    [string]$_.AuditStatus -notin @("Localized", "RejectedBySmoke")
})
if ($nonterminalCompositions.Count -gt 0) {
    throw "Composite text catalog has $($nonterminalCompositions.Count) Managed or XML composition entry point(s) without a Chinese template, resolved text-key translation, or recorded smoke rollback."
}
$argumentOnlyCompositions = @($entries | Where-Object {
    [string]$_.Source.Kind -eq "Managed" -and @($_.Parts).Count -gt 1 -and
    [string]$_.RuleId -eq "runtime-display-argument-only"
})
if (@($argumentOnlyCompositions | Where-Object {
    [string]$_.AuditStatus -ne "Localized" -or
    [string]$_.RuleScope -ne "ArgumentOrTokenOnly" -or
    [string]$_.LocalizedFormat -cne [string]$_.OriginalFormat
}).Count -gt 0) {
    throw "Argument-only composite entries must remain auditable pass-through records rather than runtime templates."
}

$smokeRejectedComposites = @($entries | Where-Object {
    [string]$_.AuditStatus -eq "RejectedBySmoke"
})
$expectedSmokeRejectedEntries = @(
    "managed:source/AtTheGatesCommon.original.dll:06000207:IL_0188",
    "managed:source/AtTheGatesCommon.original.dll:060003EA:IL_0025",
    "managed:source/AtTheGatesUI.original.dll:06000125:IL_06F3"
)
$actualSmokeRejectedIds = (@($smokeRejectedComposites | ForEach-Object {
    [string]$_.EntryPointId
} | Sort-Object) -join "`n")
$expectedSmokeRejectedIds = (($expectedSmokeRejectedEntries | Sort-Object) -join "`n")
if ($smokeRejectedComposites.Count -ne $expectedSmokeRejectedEntries.Count -or
    $actualSmokeRejectedIds -ne $expectedSmokeRejectedIds -or
    @($smokeRejectedComposites | Where-Object {
        ![string]::IsNullOrWhiteSpace([string]$_.LocalizedFormat) -or
        [string]$_.RuleScope -ne "None"
    }).Count -gt 0) {
    throw "Composite catalog must retain every exact KnownText entry with a recorded post-localization smoke failure as an untranslated RejectedBySmoke entry."
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
foreach ($column in @("RowKind", "EntryPointId", "OriginalFormat", "LocalizedFormat", "RuleId", "AuditStatus", "KnownTextReferenceStatus", "KnownTextExcludedLiteralCount", "KnownTextReferencesJson", "KnownTextUnresolvedReferencesJson", "KnownTextReferenceExclusionsJson", "PartsJson")) {
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
$apiaryCsv = @($entryRows | Where-Object { $_.EntryPointId -eq [string]$apiaryEntry[0].EntryPointId })
if ($apiaryCsv.Count -ne 1 -or $apiaryCsv[0].KnownTextReferenceStatus -ne "Resolved" -or
    [string]::IsNullOrWhiteSpace([string]$apiaryCsv[0].KnownTextOccurrenceIds) -or
    $apiaryCsv[0].KnownTextReferencesJson -notmatch 'ConfigIdXPathIndexLocator') {
    throw "Composite CSV must resolve the Apiary config locator to an exact KnownText occurrence."
}
$runtimeMapCsv = @($entryRows | Where-Object { $_.SourceKind -eq "RuntimeMap" })
if ($runtimeMapCsv.Count -ne $runtimeMapKnownTextParts.Count -or @($runtimeMapCsv | Where-Object {
    $_.KnownTextReferenceStatus -ne "Resolved" -or
    [int]$_.KnownTextExcludedLiteralCount -ne 0 -or
    $_.KnownTextReferencesJson -notmatch "RuntimeMapExactLocator"
}).Count -gt 0) {
    throw "Composite CSV must resolve every runtime-map definition to its runtime-display-map KnownText occurrence."
}

Write-Host "Composite text catalog validation passed: $($entries.Count) entries, $($rules.Count) rules, schema $($catalog.SchemaVersion)."
