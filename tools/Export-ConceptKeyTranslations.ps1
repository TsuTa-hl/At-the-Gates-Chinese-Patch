[CmdletBinding()]
param(
    [switch]$Check
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$root = Split-Path -Parent $PSScriptRoot
$sourceXmlPath = Join-Path $root "source\English.original.xml"
$localizedXmlPath = Join-Path $root "patch\Content\Text\English.xml"
$compositeRulesPath = Join-Path $root "translations\composite-text-rules.json"
$outputPath = Join-Path $root "translations\concept-key-translations.json"
$commonDllPath = Join-Path $root "source\AtTheGatesCommon.original.dll"

foreach ($path in @($sourceXmlPath, $localizedXmlPath, $compositeRulesPath, $commonDllPath)) {
    if (!(Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Static concept-key input is missing: $path"
    }
}

$formatPairPattern = [regex]'(?s)"OriginalFormat"\s*:\s*"(?<original>(?:\\.|[^"\\])*)"\s*,\s*"LocalizedFormat"\s*:\s*"(?<localized>(?:\\.|[^"\\])*)"'
$conceptPattern = [regex]'\[(?<label>[^\[\]|]+)\|(?<key>[A-Z][A-Z0-9-]*)\]'
$unicodeEscapePattern = [regex]'\\u(?<hex>[0-9A-Fa-f]{4})'
$hanPattern = [regex]'\p{IsCJKUnifiedIdeographs}'
$labelsByKey = @{}
. "$PSScriptRoot\AtGManagedMetadata.ps1"

function Normalize-ConceptDisplay {
    param([string]$Display)

    $normalized = $Display.ToLowerInvariant() -replace "[^a-z]", ""
    if ($normalized.EndsWith("ies") -and $normalized.Length -gt 3) {
        return $normalized.Substring(0, $normalized.Length - 3) + "y"
    }
    if ($normalized.EndsWith("s") -and $normalized.Length -gt 1) {
        return $normalized.Substring(0, $normalized.Length - 1)
    }
    return $normalized
}

$validConceptKeys = @{}
$conceptKeysByDisplay = @{}
foreach ($record in [AtG.ManagedMetadataReader]::GetLdstrRecords($commonDllPath)) {
    if ($record.TypeFullName -ne "AtTheGatesCommon.ns_UI.Concepts" -or $record.MethodName -ne ".cctor") {
        continue
    }

    foreach ($match in $conceptPattern.Matches([string]$record.Value)) {
        $key = $match.Groups['key'].Value
        $validConceptKeys[$key] = $true
        $displayKey = Normalize-ConceptDisplay $match.Groups['label'].Value
        if ($displayKey -and !$conceptKeysByDisplay.ContainsKey($displayKey)) {
            $conceptKeysByDisplay[$displayKey] = $key
        }
    }
    if ([string]$record.Value -match "^[A-Z][A-Z0-9-]{1,}$") {
        $validConceptKeys[[string]$record.Value] = $true
    }
}
if ($validConceptKeys.Count -eq 0) {
    throw "No canonical concept keys were discovered from $commonDllPath"
}

function Convert-JsonEscapedText {
    param([string]$Text)

    if ($null -eq $Text) {
        return $null
    }

    return $unicodeEscapePattern.Replace($Text, {
        param($match)
        [char][Convert]::ToInt32($match.Groups['hex'].Value, 16)
    })
}

function Resolve-ConceptKey {
    param(
        [string]$Key,
        [string]$Label
    )

    if ($validConceptKeys.ContainsKey($Key)) {
        return $Key
    }

    $displayKey = Normalize-ConceptDisplay $Label
    if ($displayKey -and $conceptKeysByDisplay.ContainsKey($displayKey)) {
        return [string]$conceptKeysByDisplay[$displayKey]
    }

    # Bracketed text with an unknown target is not a runtime concept link.
    # Excluding it keeps this audit aligned with Test-ConceptLinkTargets.
    return $null
}

function Get-ConceptTags {
    param([string]$Text)

    if ([string]::IsNullOrEmpty($Text)) {
        return
    }

    foreach ($match in $conceptPattern.Matches($Text)) {
        $label = Convert-JsonEscapedText $match.Groups['label'].Value
        $key = Resolve-ConceptKey -Key $match.Groups['key'].Value -Label $label
        if ([string]::IsNullOrWhiteSpace($key)) {
            continue
        }
        [pscustomobject]@{
            Key = $key
            Label = $label
        }
    }
}

function Get-XmlEntryValues {
    param([string]$Path)

    [xml]$document = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    foreach ($entry in $document.SelectNodes('//e')) {
        [pscustomobject]@{
            Id = [string]$entry.Attributes['ntry'].Value
            Value = [string]$entry.InnerText
        }
    }
}

function Add-ConceptLabel {
    param(
        [string]$Key,
        [string]$English,
        [string]$Chinese
    )

    if (!$labelsByKey.ContainsKey($Key)) {
        $labelsByKey[$Key] = @{}
    }
    if (!$labelsByKey[$Key].ContainsKey($English)) {
        $labelsByKey[$Key][$English] = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    }
    if (![string]::IsNullOrWhiteSpace($Chinese) -and $hanPattern.IsMatch($Chinese)) {
        [void]$labelsByKey[$Key][$English].Add($Chinese)
    }
}

function Add-PairedConceptTags {
    param(
        [string]$OriginalText,
        [string]$LocalizedText
    )

    $localizedByKey = @{}
    foreach ($localizedTag in @(Get-ConceptTags $LocalizedText)) {
        if (!$localizedByKey.ContainsKey($localizedTag.Key)) {
            $localizedByKey[$localizedTag.Key] = [System.Collections.ArrayList]::new()
        }
        [void]$localizedByKey[$localizedTag.Key].Add($localizedTag.Label)
    }

    $positions = @{}
    foreach ($originalTag in @(Get-ConceptTags $OriginalText)) {
        $position = 0
        if ($positions.ContainsKey($originalTag.Key)) {
            $position = $positions[$originalTag.Key]
        }
        $positions[$originalTag.Key] = $position + 1

        $localizedLabel = $null
        if ($localizedByKey.ContainsKey($originalTag.Key) -and
            $position -lt $localizedByKey[$originalTag.Key].Count) {
            $localizedLabel = $localizedByKey[$originalTag.Key][$position]
        }
        Add-ConceptLabel -Key $originalTag.Key -English $originalTag.Label -Chinese $localizedLabel
    }
}

$localizedEntriesById = @{}
foreach ($entry in @(Get-XmlEntryValues $localizedXmlPath)) {
    $id = $entry.Id
    if (!$localizedEntriesById.ContainsKey($id)) {
        $localizedEntriesById[$id] = [System.Collections.ArrayList]::new()
    }
    [void]$localizedEntriesById[$id].Add($entry.Value)
}

foreach ($entry in @(Get-XmlEntryValues $sourceXmlPath)) {
    $id = $entry.Id
    $localizedValues = if ($localizedEntriesById.ContainsKey($id)) {
        @($localizedEntriesById[$id])
    }
    else {
        @($null)
    }
    foreach ($localizedValue in $localizedValues) {
        Add-PairedConceptTags -OriginalText $entry.Value -LocalizedText $localizedValue
    }
}

foreach ($match in $formatPairPattern.Matches((Get-Content -LiteralPath $compositeRulesPath -Raw -Encoding UTF8))) {
    Add-PairedConceptTags -OriginalText $match.Groups['original'].Value -LocalizedText $match.Groups['localized'].Value
}

$concepts = @(
    foreach ($key in @($labelsByKey.Keys | Sort-Object)) {
        $labels = @(
            foreach ($english in @($labelsByKey[$key].Keys | Sort-Object)) {
                [pscustomobject][ordered]@{
                    English = $english
                    Chinese = @($labelsByKey[$key][$english] | Sort-Object)
                }
            }
        )
        $translatedLabelCount = @($labels | Where-Object { $_.Chinese.Count -gt 0 }).Count
        $status = if ($translatedLabelCount -eq $labels.Count) {
            "Complete"
        }
        elseif ($translatedLabelCount -gt 0) {
            "Partial"
        }
        else {
            "Untranslated"
        }
        [pscustomobject][ordered]@{
            Key = $key
            Status = $status
            Labels = $labels
        }
    }
)

$map = [pscustomobject][ordered]@{
    SchemaVersion = 1
    StaticInputs = @(
        [pscustomobject][ordered]@{
            Original = "source/English.original.xml"
            Localized = "patch/Content/Text/English.xml"
        },
        [pscustomobject][ordered]@{
            Original = "translations/composite-text-rules.json:OriginalFormat"
            Localized = "translations/composite-text-rules.json:LocalizedFormat"
        },
        [pscustomobject][ordered]@{
            Original = "source/AtTheGatesCommon.original.dll:AtTheGatesCommon.ns_UI.Concepts"
            Localized = "canonical concept-key resolver"
        }
    )
    ConceptCount = $concepts.Count
    Concepts = $concepts
}
$json = $map | ConvertTo-Json -Depth 8

if ($Check) {
    if (!(Test-Path -LiteralPath $outputPath -PathType Leaf)) {
        throw "Concept-key translation map is missing: $outputPath"
    }
    $existingBytes = [System.IO.File]::ReadAllBytes($outputPath)
    if ($existingBytes.Length -ge 3 -and
        $existingBytes[0] -eq 0xef -and
        $existingBytes[1] -eq 0xbb -and
        $existingBytes[2] -eq 0xbf) {
        throw "Concept-key translation map must be UTF-8 without BOM. Run .\\tools\\Export-ConceptKeyTranslations.ps1"
    }
    $existing = [System.Text.UTF8Encoding]::new($false, $true).GetString($existingBytes)
    if ($existing.TrimEnd() -cne $json.TrimEnd()) {
        throw "Concept-key translation map is stale. Run .\tools\Export-ConceptKeyTranslations.ps1"
    }
    Write-Host "Concept-key translation map is current ($($concepts.Count) keys)."
    return
}

$utf8WithoutBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($outputPath, $json + [Environment]::NewLine, $utf8WithoutBom)
Write-Host "Concept-key translation map updated ($($concepts.Count) keys): $outputPath"
