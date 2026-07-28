param(
    [string]$BoundaryPath = "$PSScriptRoot\..\docs\agent\terrain-tooltip-boundary.json",
    [string]$SourcePath = "$PSScriptRoot\..\source\English.original.xml",
    [string]$TranslationPath = "$PSScriptRoot\..\patch\Content\Text\English.xml",
    [string]$RuntimeMapPath = "$PSScriptRoot\..\translations\runtime-display-strings.json"
)

$ErrorActionPreference = "Stop"

function Assert-AtG {
    param([bool]$Condition, [string]$Message)
    if (!$Condition) { throw $Message }
}

function Get-EntryKey {
    param([System.Xml.XmlElement]$Element)
    $attribute = $Element.Attributes["ntry"]
    if ($null -eq $attribute) { $attribute = $Element.Attributes["entry"] }
    if ($null -eq $attribute) { return "" }
    return [string]$attribute.Value
}

function Read-TextEntries {
    param([string]$Path)
    Assert-AtG (Test-Path -LiteralPath $Path -PathType Leaf) "Missing XML: $Path"
    $document = [xml](Get-Content -LiteralPath $Path -Raw -Encoding UTF8)
    $map = @{}
    foreach ($element in $document.SelectNodes("//*[local-name()='e']")) {
        $key = Get-EntryKey $element
        if ($key) { $map[$key] = ([string]$element.InnerText).Trim() }
    }
    return $map
}

function Normalize-Name {
    param([string]$Value)
    if ($null -eq $Value) { $Value = "" }
    $normalized = $Value.Trim().Replace("#", "")
    if ($normalized.StartsWith("|") -and $normalized.EndsWith("|")) {
        $normalized = $normalized.Trim("|").Split("|")[0]
    }
    return $normalized
}

function Has-Chinese {
    param([string]$Value)
    return ![string]::IsNullOrWhiteSpace($Value) -and $Value -match "[\u3400-\u9fff]"
}

Assert-AtG (Test-Path -LiteralPath $BoundaryPath -PathType Leaf) "Missing boundary manifest: $BoundaryPath"
Assert-AtG (Test-Path -LiteralPath $RuntimeMapPath -PathType Leaf) "Missing runtime display map: $RuntimeMapPath"

$boundary = Get-Content -LiteralPath $BoundaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
$source = Read-TextEntries $SourcePath
$translation = Read-TextEntries $TranslationPath

$expectedCounts = [ordered]@{ Terrain = 23; Deposit = 78; Resource = 42 }
$entries = @($boundary.Entries)
foreach ($kind in $expectedCounts.Keys) {
    $actual = @($entries | Where-Object { $_.Kind -eq $kind }).Count
    Assert-AtG ($actual -eq $expectedCounts[$kind]) "Boundary $kind count is $actual, expected $($expectedCounts[$kind])."
}
Assert-AtG ($entries.Count -eq 143) "Boundary manifest must contain 143 entries."

$localizedNames = 0
$nameFailures = @()
foreach ($entry in $entries) {
    $key = [string]$entry.SourceKey
    $sourceName = Normalize-Name $source[$key]
    $patchedName = Normalize-Name $translation[$key]
    if ([string]::IsNullOrWhiteSpace($sourceName)) {
        $nameFailures += "$key missing from source"
        continue
    }
    if ([string]::IsNullOrWhiteSpace($patchedName) -or !(Has-Chinese $patchedName)) {
        $nameFailures += "$key has no Chinese localized name"
        continue
    }
    $localizedNames++
}
Assert-AtG ($nameFailures.Count -eq 0) ("Name coverage failures:`n" + ($nameFailures -join "`n"))

$descriptionChecks = @()
foreach ($entry in @($entries | Where-Object { $_.Kind -eq "Terrain" -or $_.Kind -eq "Resource" })) {
    $prefix = if ($entry.Kind -eq "Terrain") { "TEXT.Description.Terrain." } else { "TEXT.Description.Resource." }
    $key = $prefix + [string]$entry.Id
    $sourceDescription = [string]$source[$key]
    if ([string]::IsNullOrWhiteSpace($sourceDescription) -or $sourceDescription.Trim() -eq "TODO") {
        continue
    }
    $patchedDescription = [string]$translation[$key]
    $descriptionChecks += [pscustomobject]@{
        Key = $key
        Localized = (Has-Chinese $patchedDescription)
    }
}
$descriptionFailures = @($descriptionChecks | Where-Object { !$_.Localized })
Assert-AtG ($descriptionFailures.Count -eq 0) ("Description coverage failures:`n" + (($descriptionFailures | ForEach-Object Key) -join "`n"))

$runtime = Get-Content -LiteralPath $RuntimeMapPath -Raw -Encoding UTF8 | ConvertFrom-Json
$runtimeEntries = @($runtime.Exact) + @($runtime.PlainText) + @($runtime.PlainTextFragments)
$requiredPatterns = @(
    "^Seeing this on a \[Tile\|TILE\]",
    "^Herds of \[DEER\]",
    "^This is a farm",
    "^Berry Patches can be",
    "^Fields of Wheat can be",
    "^Beehives can be",
    "^Wheat can no longer be Harvested"
)
$runtimeFailures = @()
foreach ($pattern in $requiredPatterns) {
    $matches = @($runtimeEntries | Where-Object { ([string]$_.Original) -match $pattern })
    Assert-AtG ($matches.Count -gt 0) "Missing runtime tooltip template matching '$pattern'."
    foreach ($match in $matches) {
        if (!(Has-Chinese ([string]$match.Translation))) {
            $runtimeFailures += [string]$match.Original
        }
    }
}
Assert-AtG ($runtimeFailures.Count -eq 0) ("Runtime tooltip templates without Chinese:`n" + ($runtimeFailures -join "`n"))

[pscustomobject]@{
    BoundaryPath = (Resolve-Path -LiteralPath $BoundaryPath).Path
    TerrainNames = @($entries | Where-Object Kind -eq "Terrain").Count
    DepositNames = @($entries | Where-Object Kind -eq "Deposit").Count
    ResourceNames = @($entries | Where-Object Kind -eq "Resource").Count
    LocalizedNames = $localizedNames
    LocalizedDescriptions = $descriptionChecks.Count
    RuntimeTemplateChecks = $requiredPatterns.Count
    Status = "Passed"
}

Write-Host "Terrain/deposit tooltip boundary coverage passed: 23 terrains, 78 deposits, 42 resources; all localized names and runtime tooltip templates verified."
