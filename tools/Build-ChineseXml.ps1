param(
    [string]$SourceXml = "$PSScriptRoot\..\source\English.original.xml",
    [string]$TranslationJson = "$PSScriptRoot\..\translations\zh-CN.json",
    [string]$AdditionalEntriesJson = "$PSScriptRoot\..\translations\runtime-text-key-additions.json",
    [string]$OutputXml = "$PSScriptRoot\..\patch\Content\Text\English.xml"
)

$ErrorActionPreference = "Stop"

if (!(Test-Path -LiteralPath $SourceXml)) {
    throw "Source XML not found: $SourceXml"
}
if (!(Test-Path -LiteralPath $TranslationJson)) {
    throw "Translation JSON not found: $TranslationJson"
}
if (!(Test-Path -LiteralPath $AdditionalEntriesJson)) {
    throw "Additional text entries JSON not found: $AdditionalEntriesJson"
}

$translationObject = Get-Content -LiteralPath $TranslationJson -Raw -Encoding UTF8 | ConvertFrom-Json
$translations = @{}
foreach ($property in $translationObject.PSObject.Properties) {
    $translations[$property.Name] = [string]$property.Value
}

$additionalEntryObject = Get-Content -LiteralPath $AdditionalEntriesJson -Raw -Encoding UTF8 | ConvertFrom-Json
$additionalEntries = [ordered]@{}
foreach ($property in $additionalEntryObject.PSObject.Properties) {
    $additionalEntries[$property.Name] = [string]$property.Value
}

$xml = [xml](Get-Content -LiteralPath $SourceXml -Raw -Encoding UTF8)
$entries = @($xml.SelectNodes("//e"))
$translated = 0

foreach ($entry in $entries) {
    $key = $entry.ntry
    if ($translations.ContainsKey($key) -and $translations[$key].Length -gt 0) {
        $entry.InnerText = $translations[$key]
        $translated++
    }
}

$pluralNode = $xml.SelectSingleNode("//standardPluralizationSuffix")
if ($pluralNode) {
    $pluralNode.InnerText = ""
}

function Add-TextKeyAliases {
    param(
        [xml]$Xml,
        [object[]]$SourceEntries,
        [string]$BaseKeyPattern,
        [string[]]$Suffixes
    )

    if ($null -eq $Xml.DocumentElement) {
        throw "XML document has no root element."
    }

    $knownKeys = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    foreach ($sourceEntry in $SourceEntries) {
        $sourceKey = [string]$sourceEntry.ntry
        if (![string]::IsNullOrWhiteSpace($sourceKey)) {
            [void]$knownKeys.Add($sourceKey)
        }
    }

    $added = 0
    foreach ($sourceEntry in $SourceEntries) {
        $sourceKey = [string]$sourceEntry.ntry
        if ([string]::IsNullOrWhiteSpace($sourceKey)) {
            continue
        }
        if ($sourceKey -notmatch $BaseKeyPattern) {
            continue
        }
        if ($sourceKey.Contains(":")) {
            continue
        }

        foreach ($suffix in $Suffixes) {
            $aliasKey = "${sourceKey}:$suffix"
            if ($knownKeys.Contains($aliasKey)) {
                continue
            }

            $aliasEntry = $Xml.CreateElement("e")
            $ntryAttribute = $Xml.CreateAttribute("ntry")
            $ntryAttribute.Value = $aliasKey
            [void]$aliasEntry.Attributes.Append($ntryAttribute)
            $aliasEntry.InnerText = $sourceEntry.InnerText
            [void]$Xml.DocumentElement.AppendChild($aliasEntry)
            [void]$knownKeys.Add($aliasKey)
            $added++
        }
    }

    return $added
}

function Add-ConfiguredTextEntries {
    param(
        [xml]$Xml,
        [System.Collections.IDictionary]$Entries
    )

    if ($null -eq $Xml.DocumentElement) {
        throw "XML document has no root element."
    }

    $knownKeys = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    foreach ($sourceEntry in @($Xml.SelectNodes("//e"))) {
        $sourceKey = [string]$sourceEntry.ntry
        if (![string]::IsNullOrWhiteSpace($sourceKey)) {
            [void]$knownKeys.Add($sourceKey)
        }
    }

    $added = 0
    foreach ($key in @($Entries.Keys | Sort-Object)) {
        if ([string]::IsNullOrWhiteSpace([string]$key)) {
            throw "Additional text entry has an empty key."
        }
        if ($knownKeys.Contains([string]$key)) {
            throw "Additional text entry '$key' already exists in the source English XML. Move it to zh-CN.json instead."
        }
        $entry = $Xml.CreateElement("e")
        $ntryAttribute = $Xml.CreateAttribute("ntry")
        $ntryAttribute.Value = [string]$key
        [void]$entry.Attributes.Append($ntryAttribute)
        $entry.InnerText = [string]$Entries[$key]
        [void]$Xml.DocumentElement.AppendChild($entry)
        [void]$knownKeys.Add([string]$key)
        $added++
    }
    return $added
}

$resourceAliasCount = Add-TextKeyAliases `
    -Xml $xml `
    -SourceEntries $entries `
    -BaseKeyPattern '^TEXT\.Name\.Resource\.' `
    -Suffixes @("SINGULAR", "PLURAL")

$professionAliasCount = Add-TextKeyAliases `
    -Xml $xml `
    -SourceEntries $entries `
    -BaseKeyPattern '^TEXT\.Name\.Profession\.' `
    -Suffixes @("SINGULAR", "PLURAL")

$disciplineAliasCount = Add-TextKeyAliases `
    -Xml $xml `
    -SourceEntries $entries `
    -BaseKeyPattern '^TEXT\.Name\.Discipline\.' `
    -Suffixes @("SINGULAR", "PLURAL")

$structureAliasCount = Add-TextKeyAliases `
    -Xml $xml `
    -SourceEntries $entries `
    -BaseKeyPattern '^TEXT\.Name\.Structure\.' `
    -Suffixes @("SINGULAR", "PLURAL")

$depositAliasCount = Add-TextKeyAliases `
    -Xml $xml `
    -SourceEntries $entries `
    -BaseKeyPattern '^TEXT\.Name\.Deposit\.' `
    -Suffixes @("SINGULAR", "PLURAL")

$terrainAliasCount = Add-TextKeyAliases `
    -Xml $xml `
    -SourceEntries $entries `
    -BaseKeyPattern '^TEXT\.Name\.Terrain\.' `
    -Suffixes @("SINGULAR", "PLURAL")

$techAliasCount = Add-TextKeyAliases `
    -Xml $xml `
    -SourceEntries $entries `
    -BaseKeyPattern '^TEXT\.Name\.Tech\.' `
    -Suffixes @("SINGULAR", "PLURAL")

$additionalEntryCount = Add-ConfiguredTextEntries -Xml $xml -Entries $additionalEntries

$outDir = Split-Path -Parent $OutputXml
if ($outDir) {
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
}

$settings = New-Object System.Xml.XmlWriterSettings
$settings.Indent = $true
$settings.Encoding = New-Object System.Text.UTF8Encoding($false)
$settings.OmitXmlDeclaration = $true
$settings.NewLineChars = "`n"
$settings.NewLineHandling = [System.Xml.NewLineHandling]::Replace

$writer = [System.Xml.XmlWriter]::Create($OutputXml, $settings)
try {
    $xml.Save($writer)
}
finally {
    $writer.Close()
}

Write-Host "Built $OutputXml"
Write-Host "Translated $translated / $($entries.Count) entries."
Write-Host "Added $resourceAliasCount generated resource name aliases."
Write-Host "Added $professionAliasCount generated profession name aliases."
Write-Host "Added $disciplineAliasCount generated discipline name aliases."
Write-Host "Added $structureAliasCount generated structure name aliases."
Write-Host "Added $depositAliasCount generated deposit name aliases."
Write-Host "Added $terrainAliasCount generated terrain name aliases."
Write-Host "Added $techAliasCount generated tech name aliases."
Write-Host "Added $additionalEntryCount configured runtime text entries."
