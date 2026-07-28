[CmdletBinding()]
param(
    [string]$ProjectRoot,
    [string]$SourceXml,
    [string]$NameMap,
    [string]$PatchXml,
    [string]$StatePath,
    [switch]$Initialize,
    [string]$TraitId,
    [ValidateSet("Unverified", "Verified", "Failed", "Partial")]
    [string]$TooltipStatus = "Unverified",
    [string]$VerificationSave,
    [Alias("EvidenceDir")]
    [string]$EvidenceHandoff,
    [string[]]$TooltipEnglishResiduals = @(),
    [string]$Notes,
    [string]$VerifiedAt
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}
if ([string]::IsNullOrWhiteSpace($SourceXml)) {
    $SourceXml = Join-Path $ProjectRoot "source\Content\Config\Primary\ClanTraits.original.xml"
}
if ([string]::IsNullOrWhiteSpace($NameMap)) {
    $NameMap = Join-Path $ProjectRoot "translations\config-node-strings.json"
}
if ([string]::IsNullOrWhiteSpace($PatchXml)) {
    $PatchXml = Join-Path $ProjectRoot "patch\Content\Config\Primary\ClanTraits.xml"
}
if ([string]::IsNullOrWhiteSpace($StatePath)) {
    $StatePath = Join-Path $ProjectRoot "docs\agent\clan-trait-verification.json"
}

function Resolve-AtGPath {
    param([string]$Path)

    if ([IO.Path]::IsPathRooted($Path)) {
        return $Path
    }

    return (Join-Path $ProjectRoot $Path)
}

function Get-JsonPropertyValue {
    param(
        [object]$Object,
        [string]$Name
    )

    if ($null -eq $Object) {
        return $null
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}

function Read-ExistingTraitState {
    param([string]$Path)

    $text = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    try {
        return $text | ConvertFrom-Json
    }
    catch {
        $originalError = $_
    }

    # Older hand-written notes could be interrupted after their final character,
    # leaving a Notes string without its closing quote. Repair only that narrow
    # shape in memory, then let ConvertFrom-Json validate the complete document.
    $changed = $false
    $repairedLines = foreach ($line in (Get-Content -LiteralPath $Path -Encoding UTF8)) {
        if ($line -match '^(?<prefix>\s*"Notes"\s*:\s*".*)(?<tail>,\s*)$') {
            $prefix = $Matches['prefix']
            if (!$prefix.TrimEnd().EndsWith('"')) {
                $changed = $true
                $prefix + '"' + $Matches['tail']
                continue
            }
        }
        $line
    }

    if (!$changed) {
        throw "Clan-trait state is invalid and has no supported recovery: $($originalError.Exception.Message)"
    }

    try {
        return (($repairedLines -join "`n") | ConvertFrom-Json)
    }
    catch {
        throw "Clan-trait state is invalid after supported recovery: $($_.Exception.Message)"
    }
}

function Get-NodeText {
    param(
        [System.Xml.XmlNode]$Container,
        [string]$XPath
    )

    $node = $Container.SelectSingleNode($XPath)
    if ($null -eq $node) {
        return ""
    }

    return [string]$node.InnerText
}

function Get-InitialTraitRecord {
    param(
        [System.Xml.XmlNode]$SourceNode,
        [System.Xml.XmlNode]$PatchedNode,
        [object]$NameItem
    )

    $id = [string](Get-NodeText -Container $SourceNode -XPath "ID")
    $originalName = [string](Get-NodeText -Container $SourceNode -XPath "name")
    $originalDescription = [string](Get-NodeText -Container $SourceNode -XPath "description")
    $translatedName = [string](Get-JsonPropertyValue -Object $NameItem -Name "Name")
    $patchedName = if ($null -ne $PatchedNode) { [string](Get-NodeText -Container $PatchedNode -XPath "name") } else { "" }
    $patchedDescription = if ($null -ne $PatchedNode) { [string](Get-NodeText -Container $PatchedNode -XPath "description") } else { "" }
    $isNonPersonality = ([string](Get-NodeText -Container $SourceNode -XPath "isNotPersonalityTrait")).ToLowerInvariant() -eq "true"

    $nameStatus = "Missing"
    if (![string]::IsNullOrWhiteSpace($translatedName) -and $translatedName -ne $originalName) {
        $nameStatus = "TranslatedInConfig"
    }

    $descriptionStatus = "NotPresent"
    if (![string]::IsNullOrWhiteSpace($originalDescription)) {
        if (![string]::IsNullOrWhiteSpace($patchedDescription) -and $patchedDescription -ne $originalDescription) {
            $descriptionStatus = "TranslatedInConfig"
        }
        else {
            $descriptionStatus = "UntranslatedOrMissing"
        }
    }

    return [ordered]@{
        ID = $id
        OriginalName = $originalName
        Translation = $translatedName
        IsPersonality = !$isNonPersonality
        NameStatus = $nameStatus
        DescriptionStatus = $descriptionStatus
        # Every trait can appear on a randomly generated clan card. Keep
        # personality and non-personality traits in the same tooltip queue.
        TooltipStatus = "Unverified"
        TooltipEnglishResiduals = @()
        Verified = $false
        VerificationSave = $null
        EvidenceHandoff = $null
        EvidenceRetention = $null
        Notes = $null
        VerifiedAt = $null
    }
}

$sourcePath = Resolve-AtGPath -Path $SourceXml
$nameMapPath = Resolve-AtGPath -Path $NameMap
$patchPath = Resolve-AtGPath -Path $PatchXml
$statePathResolved = Resolve-AtGPath -Path $StatePath

foreach ($requiredPath in @($sourcePath, $nameMapPath, $patchPath)) {
    if (!(Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Required clan-trait file not found: $requiredPath"
    }
}

$sourceDocument = New-Object System.Xml.XmlDocument
$sourceDocument.Load($sourcePath)
$patchedDocument = New-Object System.Xml.XmlDocument
$patchedDocument.Load($patchPath)
$nameMapDocument = Get-Content -LiteralPath $nameMapPath -Raw -Encoding UTF8 | ConvertFrom-Json
$nameConfig = $null
foreach ($mapProperty in $nameMapDocument.PSObject.Properties) {
    if ([string]$mapProperty.Name -eq "Content\Config\Primary\ClanTraits.xml") {
        $nameConfig = $mapProperty.Value
        break
    }
}
if ($null -eq $nameConfig) {
    $availableKeys = @($nameMapDocument.PSObject.Properties | ForEach-Object { [string]$_.Name }) -join ", "
    $mapType = if ($null -eq $nameMapDocument) { "null" } else { $nameMapDocument.GetType().FullName }
    throw "ClanTraits entry is missing from $nameMapPath. Map type: $mapType. Available keys: $availableKeys"
}

$nameItems = @{}
foreach ($item in @($nameConfig.Items)) {
    $nameItems[[string]$item.ID] = $item
}

$existingState = $null
if (Test-Path -LiteralPath $statePathResolved -PathType Leaf) {
    $existingState = Read-ExistingTraitState -Path $statePathResolved
}

$existingTraits = @{}
if ($null -ne $existingState) {
    foreach ($trait in @($existingState.Traits)) {
        if (![string]::IsNullOrWhiteSpace([string]$trait.ID)) {
            $existingTraits[[string]$trait.ID] = $trait
        }
    }
}

$records = New-Object System.Collections.Generic.List[object]
foreach ($sourceNode in @($sourceDocument.SelectNodes("//clanTrait"))) {
    $id = [string](Get-NodeText -Container $sourceNode -XPath "ID")
    if ([string]::IsNullOrWhiteSpace($id)) {
        throw "Clan trait node is missing ID in $sourcePath"
    }

    $patchedNode = $patchedDocument.SelectSingleNode("//clanTrait[ID='$id']")
    $nameItem = $null
    if ($nameItems.ContainsKey($id)) {
        $nameItem = $nameItems[$id]
    }

    $initial = Get-InitialTraitRecord -SourceNode $sourceNode -PatchedNode $patchedNode -NameItem $nameItem
    if ($existingTraits.ContainsKey($id)) {
        $old = $existingTraits[$id]
        foreach ($propertyName in @(
            "TooltipStatus", "TooltipEnglishResiduals", "Verified", "VerificationSave",
            "EvidenceRetention", "Notes", "VerifiedAt"
        )) {
            if ($null -ne $old.PSObject.Properties[$propertyName]) {
                $oldValue = $old.$propertyName
                if ($propertyName -eq "TooltipStatus" -and [string]$oldValue -eq "OutOfScope") {
                    $oldValue = "Unverified"
                }
                $initial[$propertyName] = $oldValue
            }
        }

        $oldEvidenceHandoff = Get-JsonPropertyValue -Object $old -Name "EvidenceHandoff"
        if ([string]::IsNullOrWhiteSpace([string]$oldEvidenceHandoff)) {
            $oldEvidenceHandoff = Get-JsonPropertyValue -Object $old -Name "EvidenceDir"
        }
        $initial["EvidenceHandoff"] = $oldEvidenceHandoff
    }

    $records.Add([pscustomobject]$initial) | Out-Null
}

if (![string]::IsNullOrWhiteSpace($TraitId)) {
    $target = @($records | Where-Object { $_.ID -eq $TraitId }) | Select-Object -First 1
    if ($null -eq $target) {
        throw "Trait ID '$TraitId' was not found in $sourcePath"
    }
    $target.TooltipStatus = $TooltipStatus
    $target.Verified = $TooltipStatus -eq "Verified"
    $target.TooltipEnglishResiduals = @($TooltipEnglishResiduals | Where-Object { ![string]::IsNullOrWhiteSpace($_) })
    $target.VerificationSave = if ([string]::IsNullOrWhiteSpace($VerificationSave)) { $null } else { $VerificationSave }
    $target.EvidenceHandoff = if ([string]::IsNullOrWhiteSpace($EvidenceHandoff)) { $null } else { $EvidenceHandoff }
    $target.EvidenceRetention = if ([string]::IsNullOrWhiteSpace($target.EvidenceHandoff)) { $null } else { "TextOnly" }
    $target.Notes = if ([string]::IsNullOrWhiteSpace($Notes)) { $null } else { $Notes }
    $target.VerifiedAt = if ($TooltipStatus -ne "Verified") {
        $null
    }
    elseif ([string]::IsNullOrWhiteSpace($VerifiedAt)) {
        (Get-Date).ToUniversalTime().ToString("o")
    }
    else {
        $VerifiedAt
    }
}
elseif (!$Initialize -and $null -eq $existingState) {
    Write-Verbose "No state file exists; creating the initial state."
}

$personalityRecords = @($records | Where-Object { $_.IsPersonality })
$nonPersonalityRecords = @($records | Where-Object { !$_.IsPersonality })
# StatusSummary covers every trait, including the 14 non-personality traits.
$verifiedCount = @($records | Where-Object { $_.TooltipStatus -eq "Verified" }).Count
$failedCount = @($records | Where-Object { $_.TooltipStatus -eq "Failed" }).Count
$partialCount = @($records | Where-Object { $_.TooltipStatus -eq "Partial" }).Count
$unverifiedCount = @($records | Where-Object { $_.TooltipStatus -eq "Unverified" }).Count
$traitArray = $records.ToArray()

$state = [ordered]@{
    SchemaVersion = 1
    GeneratedAt = (Get-Date).ToUniversalTime().ToString("o")
    GeneratedFrom = (Resolve-Path -LiteralPath $sourcePath).Path
    NameMap = (Resolve-Path -LiteralPath $nameMapPath).Path
    PatchXml = (Resolve-Path -LiteralPath $patchPath).Path
    EvidenceRetentionPolicy = "TextOnly; temporary visual evidence is summarized by cleanup handoffs."
    TotalClanTraits = $records.Count
    PersonalityCount = $personalityRecords.Count
    NonPersonalityCount = $nonPersonalityRecords.Count
    StatusSummary = [ordered]@{
        Verified = $verifiedCount
        Partial = $partialCount
        Failed = $failedCount
        Unverified = $unverifiedCount
    }
    Traits = $traitArray
}

$stateDirectory = Split-Path -Parent $statePathResolved
if ($stateDirectory) {
    New-Item -ItemType Directory -Force -Path $stateDirectory | Out-Null
}

$json = $state | ConvertTo-Json -Depth 10
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($statePathResolved, $json, $utf8NoBom)

[pscustomobject]@{
    StatePath = $statePathResolved
    TotalClanTraits = $records.Count
    PersonalityCount = $personalityRecords.Count
    Verified = $verifiedCount
    Partial = $partialCount
    Failed = $failedCount
    Unverified = $unverifiedCount
    UpdatedTrait = if ([string]::IsNullOrWhiteSpace($TraitId)) { $null } else { $TraitId }
}
