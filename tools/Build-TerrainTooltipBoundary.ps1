param(
    [string]$SourcePath = (Join-Path $PSScriptRoot "..\source\English.original.xml"),
    [string]$OutputPath = (Join-Path $PSScriptRoot "..\docs\agent\terrain-tooltip-boundary.json"),
    [string]$ObservationPath,
    [string]$TranslationPath = (Join-Path $PSScriptRoot "..\patch\Content\Text\English.xml")
)

$ErrorActionPreference = "Stop"

function Get-EntryKey {
    param([System.Xml.XmlElement]$Element)
    $attribute = $Element.Attributes["ntry"]
    if ($null -eq $attribute) { $attribute = $Element.Attributes["entry"] }
    if ($null -eq $attribute) { return "" }
    return [string]$attribute.Value
}

function Get-Entries {
    param(
        [System.Xml.XmlDocument]$Document,
        [string]$Section,
        [string]$Prefix,
        [string]$Kind
    )

    $result = @()
    foreach ($element in $Document.SelectNodes("//$Section/e")) {
        $key = Get-EntryKey $element
        if (!$key.StartsWith($Prefix, [System.StringComparison]::Ordinal)) { continue }
        $id = $key.Substring($Prefix.Length)
        $variant = if ($Kind -eq "Deposit") {
            if ($id.StartsWith("Large", [System.StringComparison]::Ordinal)) { "Large" }
            elseif ($id.StartsWith("Vast", [System.StringComparison]::Ordinal)) { "Vast" }
            else { "Base" }
        } else { "Base" }
        $descriptionStatus = "Defined"
        if ($Kind -eq "Terrain") {
            $description = @($Document.SelectNodes("//e") | Where-Object {
                (Get-EntryKey $_) -eq ("TEXT.Description.Terrain." + $id)
            } | Select-Object -First 1)
            if ($description.Count -gt 0 -and $description[0].InnerText.Trim() -eq "TODO") {
                $descriptionStatus = "SourceTodo"
            }
        }
        $result += [ordered]@{
            Kind = $Kind
            SourceKey = $key
            Id = $id
            Original = $element.InnerText.Trim()
            Variant = $variant
            DescriptionStatus = $descriptionStatus
        }
    }
    return $result
}

if (!(Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
    throw "Source XML not found: $SourcePath"
}

$document = [xml](Get-Content -LiteralPath $SourcePath -Raw -Encoding UTF8)
$entries = @()
$entries += Get-Entries $document "terrains" "TEXT.Name.Terrain." "Terrain"
$entries += Get-Entries $document "deposits" "TEXT.Name.Deposit." "Deposit"
$entries += Get-Entries $document "resources" "TEXT.Name.Resource." "Resource"
$entries = @($entries | Sort-Object @{ Expression = { @("Terrain", "Deposit", "Resource").IndexOf($_.Kind) } }, SourceKey)

$counts = [ordered]@{
    Terrains = @($entries | Where-Object Kind -eq "Terrain").Count
    Deposits = @($entries | Where-Object Kind -eq "Deposit").Count
    Resources = @($entries | Where-Object Kind -eq "Resource").Count
}
if ($counts.Terrains -ne 23 -or $counts.Deposits -ne 78 -or $counts.Resources -ne 42) {
    throw "Unexpected source inventory counts: terrains=$($counts.Terrains), deposits=$($counts.Deposits), resources=$($counts.Resources)."
}

$observations = @()
if (![string]::IsNullOrWhiteSpace($ObservationPath) -and
    (Test-Path -LiteralPath $ObservationPath -PathType Leaf)) {
    $rawObservations = Get-Content -LiteralPath $ObservationPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $observations = if ($rawObservations.PSObject.Properties.Name -contains "Observations") {
        @($rawObservations.Observations)
    } else { @($rawObservations) }
}

$localizedLookup = @{}
if (Test-Path -LiteralPath $TranslationPath -PathType Leaf) {
    $translation = [xml](Get-Content -LiteralPath $TranslationPath -Raw -Encoding UTF8)
    foreach ($element in $translation.SelectNodes("//e")) {
        $key = Get-EntryKey $element
        if (!$key.StartsWith("TEXT.Name.", [System.StringComparison]::Ordinal)) { continue }
        $value = $element.InnerText.Trim()
        $normalized = $value.Replace("#", "")
        if ($normalized.StartsWith("|", [System.StringComparison]::Ordinal) -and $normalized.EndsWith("|", [System.StringComparison]::Ordinal)) {
            $normalized = $normalized.Trim("|").Split("|")[0]
        }
        if ($normalized) { $localizedLookup[$normalized] = $key }
    }
}

$surfaceNames = @(
    "TerrainBaseOrOverlay",
    "VisibleDeposit",
    "RumorKnownDeposit",
    "RumorUnknownDeposit",
    "TileQuickReference",
    "CycleItem"
)
$statusNames = @("Observed", "RumorOnly", "VisibleOnly", "Unreachable", "Pending")
$entryRows = foreach ($entry in $entries) {
    $matches = @($observations | Where-Object {
        $candidateKeys = @([string]$_.SourceKey, [string]$_.Identity)
        $candidateKeys -contains $entry.SourceKey -or
            ($candidateKeys | ForEach-Object {
                if ($localizedLookup.ContainsKey($_)) { $localizedLookup[$_] }
            }) -contains $entry.SourceKey
    })
    $rumor = @($matches | Where-Object { [bool]$_.Rumor }).Count -gt 0
    $visible = @($matches | Where-Object { [bool]$_.Visible }).Count -gt 0
    $explicitlyUnreachable = @($matches | Where-Object {
        [string]$_.Reachability -eq "Unreachable"
    }).Count -gt 0
    $reachability = if ($rumor -and $visible) { "Observed" }
        elseif ($rumor) { "RumorOnly" }
        elseif ($visible) { "VisibleOnly" }
        elseif ($explicitlyUnreachable) { "Unreachable" }
        else { "Pending" }
    [ordered]@{
        Kind = $entry.Kind
        SourceKey = $entry.SourceKey
        Id = $entry.Id
        Original = $entry.Original
        Variant = $entry.Variant
        DescriptionStatus = $entry.DescriptionStatus
        Reachability = $reachability
        ObservedSurfaces = @($matches | ForEach-Object { [string]$_.Surface } |
            Where-Object { $_ } | Sort-Object -Unique)
        RumorVisibleDifferences = @($matches | Where-Object {
            $_.PSObject.Properties.Name -contains "RumorVisibleDifference" -and
            [bool]$_.RumorVisibleDifference
        } | ForEach-Object { [string]$_.Surface } | Sort-Object -Unique)
    }
}

$manifest = [ordered]@{
    BoundaryManifestId = "terrain-tooltip-v1"
    SchemaVersion = 1
    GeneratedAtUtc = [DateTime]::UtcNow.ToString("o")
    SourcePath = "source/English.original.xml"
    Counts = $counts
    ReachabilityStates = $statusNames
    TooltipSurfaces = $surfaceNames
    Entries = @($entryRows)
}

$parent = Split-Path -Parent $OutputPath
if (!(Test-Path -LiteralPath $parent -PathType Container)) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
}
$manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
Write-Host ("Terrain tooltip boundary written: {0} entries ({1} terrains, {2} deposits, {3} resources)." -f
    $entries.Count, $counts.Terrains, $counts.Deposits, $counts.Resources)
