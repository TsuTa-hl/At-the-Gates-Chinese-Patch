param(
    [string]$ConfigRoot = "$PSScriptRoot\..\source\Content\Config",
    [string[]]$ConfigNodeMap = @(
        "$PSScriptRoot\..\translations\config-node-strings.json",
        "$PSScriptRoot\..\translations\config-node-extra-strings.json",
        "$PSScriptRoot\..\translations\config-node-onmap-strings.json"
    ),
    [string]$OutputJson = "$PSScriptRoot\..\.tmp\static-text-candidates.json",
    [string]$OutputCsv = "$PSScriptRoot\..\.tmp\static-text-candidates.csv"
)

$ErrorActionPreference = "Stop"

function Get-AtGRelativeConfigPath {
    param(
        [string]$SourcePath,
        [string]$RootPath
    )

    $resolvedRoot = (Resolve-Path -LiteralPath $RootPath).Path.TrimEnd("\", "/")
    $resolvedSource = (Resolve-Path -LiteralPath $SourcePath).Path
    if ($resolvedSource.StartsWith($resolvedRoot + "\", [System.StringComparison]::OrdinalIgnoreCase)) {
        $relative = $resolvedSource.Substring($resolvedRoot.Length + 1)
    }
    else {
        $relative = [System.IO.Path]::GetFileName($resolvedSource)
    }

    $relative = $relative -replace "\.original\.xml$", ".xml"
    return "Content\Config\" + ($relative -replace "/", "\")
}

function Get-AtGChildText {
    param(
        [System.Xml.XmlNode]$Node,
        [string]$ChildName
    )

    $child = $Node.SelectSingleNode($ChildName)
    if ($child) {
        return [string]$child.InnerText
    }
    return ""
}

function Get-AtGRelativeXPath {
    param(
        [System.Xml.XmlNode]$Node,
        [System.Xml.XmlNode]$Container
    )

    $parts = New-Object System.Collections.Generic.List[string]
    $cursor = $Node
    while ($cursor -and ![object]::ReferenceEquals($cursor, $Container)) {
        $parts.Insert(0, $cursor.LocalName)
        $cursor = $cursor.ParentNode
    }

    return ($parts -join "/")
}

function Get-AtGPlaceholders {
    param([string]$Text)

    $matches = [regex]::Matches($Text, "\[[^\]]+\]|\([A-Z0-9_]+\)")
    return @($matches | ForEach-Object { $_.Value } | Select-Object -Unique)
}

function Get-AtGStaticTextClass {
    param(
        [string]$FileName,
        [string]$ContainerName,
        [string]$XPath,
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return @{
            Class = "Empty"
            Safety = "Skip"
            Reason = "Empty node."
        }
    }

    if ($Value -eq "TODO") {
        return @{
            Class = "TodoPlaceholder"
            Safety = "Skip"
            Reason = "Developer placeholder, not player-facing prose."
        }
    }

    if ($Value -cmatch "^(TEXT|TRAIT|FACTION|DISCIPLINE|UNIT|RESOURCE|TERRAIN|RIVER|BONUS|JOB|PROFESSION)[\._]") {
        return @{
            Class = "TextKeyReference"
            Safety = "DoNotPatchHere"
            Reason = "This is a key/reference; translate the resolved text entry instead."
        }
    }

    if ($XPath -match "(^|/)shortName$" -or $Value -cmatch "^[A-Z0-9_+\-]{2,}$") {
        return @{
            Class = "CodeOrAbbreviation"
            Safety = "DoNotPatchHere"
            Reason = "Likely a compact UI code or logic abbreviation."
        }
    }

    if ($FileName -eq "ClanTraits.original.xml" -and $ContainerName -eq "clanTrait") {
        if ($XPath -eq "name") {
            return @{
                Class = "ClanTraitName"
                Safety = "SafeDisplay"
                Reason = "Known player-facing trait label; patched by ID."
            }
        }

        if ($XPath -eq "description") {
            return @{
                Class = "ClanTraitDescription"
                Safety = "SafeDisplay"
                Reason = "Player-facing trait tooltip text under a stable trait ID."
            }
        }

        if ($XPath -match "(^|/)text$") {
            return @{
                Class = "ClanTraitDialogue"
                Safety = "SafeDisplay"
                Reason = "Player-facing clan dialogue under a stable trait ID."
            }
        }
    }

    if ($FileName -eq "Factions.original.xml") {
        return @{
            Class = "FactionNameOrLabel"
            Safety = "ManualOnly"
            Reason = "Faction names are used by game logic; direct replacement has caused load/runtime failures."
        }
    }

    if ($FileName -eq "FactionTraits.original.xml") {
        return @{
            Class = "FactionTraitLiteral"
            Safety = "ManualRuntimeTest"
            Reason = "Faction trait literals need targeted UI/runtime verification before patching."
        }
    }

    return @{
        Class = "UnclassifiedLiteral"
        Safety = "ManualOnly"
        Reason = "No established safe patching rule yet."
    }
}

function Get-AtGPatchedIndex {
    param([string[]]$MapPath)

    $index = @{}
    foreach ($path in $MapPath) {
        if (!(Test-Path -LiteralPath $path)) {
            continue
        }

        $map = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($fileEntry in $map.PSObject.Properties) {
            $relativePath = [string]$fileEntry.Name
            foreach ($item in @($fileEntry.Value.Items)) {
                $id = [string]$item.ID
                if ($null -ne $item.PSObject.Properties["Name"]) {
                    $index["$relativePath|$id|name|"] = $true
                }
                if ($null -ne $item.PSObject.Properties["Description"]) {
                    $index["$relativePath|$id|description|"] = $true
                }
                if ($null -ne $item.PSObject.Properties["Nodes"]) {
                    foreach ($nodePatch in @($item.Nodes)) {
                        $xpath = [string]$nodePatch.XPath
                        $idx = ""
                        if ($null -ne $nodePatch.PSObject.Properties["Index"]) {
                            $idx = [string][int]$nodePatch.Index
                        }
                        $index["$relativePath|$id|$xpath|$idx"] = $true
                    }
                }
            }
        }
    }

    return $index
}

if (!(Test-Path -LiteralPath $ConfigRoot)) {
    throw "Config root not found: $ConfigRoot"
}

$patchedIndex = Get-AtGPatchedIndex -MapPath $ConfigNodeMap
$fieldNames = @("name", "shortName", "description", "text")
$candidates = New-Object System.Collections.Generic.List[object]

foreach ($file in Get-ChildItem -LiteralPath $ConfigRoot -Filter "*.original.xml" -File -Recurse) {
    $xml = [xml](Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8)
    $relativePath = Get-AtGRelativeConfigPath -SourcePath $file.FullName -RootPath $ConfigRoot

    $containers = @()
    if ($file.Name -eq "ClanTraits.original.xml") {
        $containers = @($xml.SelectNodes("//clanTrait"))
    }
    elseif ($file.Name -eq "Factions.original.xml") {
        $containers = @($xml.SelectNodes("//faction"))
    }
    elseif ($file.Name -eq "FactionTraits.original.xml") {
        $containers = @($xml.SelectNodes("//factionTrait"))
    }
    else {
        $containers = @($xml.SelectNodes("//*[ID]") | Where-Object { $_.NodeType -eq [System.Xml.XmlNodeType]::Element })
        if ($containers.Count -eq 0) {
            $containers = @($xml.DocumentElement.ChildNodes | Where-Object { $_.NodeType -eq [System.Xml.XmlNodeType]::Element })
        }
    }

    foreach ($container in $containers) {
        $id = Get-AtGChildText -Node $container -ChildName "ID"
        if ([string]::IsNullOrWhiteSpace($id)) {
            $id = "(no ID)"
        }

        $pathCounts = @{}
        $nodes = @($container.SelectNodes(".//*[local-name()='name' or local-name()='shortName' or local-name()='description' or local-name()='text']"))
        foreach ($node in $nodes) {
            if ($fieldNames -notcontains $node.LocalName) {
                continue
            }

            $xpath = Get-AtGRelativeXPath -Node $node -Container $container
            if (!$pathCounts.ContainsKey($xpath)) {
                $pathCounts[$xpath] = 0
            }
            $index = $pathCounts[$xpath]
            $pathCounts[$xpath] = $index + 1
        }

        $seenCounts = @{}
        foreach ($node in $nodes) {
            if ($fieldNames -notcontains $node.LocalName) {
                continue
            }

            $value = [string]$node.InnerText
            if ([string]::IsNullOrWhiteSpace($value)) {
                continue
            }

            $xpath = Get-AtGRelativeXPath -Node $node -Container $container
            if (!$seenCounts.ContainsKey($xpath)) {
                $seenCounts[$xpath] = 0
            }
            $index = $seenCounts[$xpath]
            $seenCounts[$xpath] = $index + 1

            $indexKey = ""
            if ($pathCounts[$xpath] -gt 1) {
                $indexKey = [string]$index
            }

            $classInfo = Get-AtGStaticTextClass -FileName $file.Name -ContainerName $container.LocalName -XPath $xpath -Value $value
            $alreadyPatched = [bool]$patchedIndex["$relativePath|$id|$xpath|$indexKey"]
            if (!$alreadyPatched -and $pathCounts[$xpath] -eq 1) {
                $alreadyPatched = [bool]$patchedIndex["$relativePath|$id|$xpath|"]
            }

            $needsLayout = $false
            if ($classInfo.Safety -match "SafeDisplay|Manual" -and ($xpath -match "(^|/)(description|text)$" -or $value.Length -gt 18)) {
                $needsLayout = $true
            }

            $needsFont = $false
            if ($classInfo.Safety -match "SafeDisplay|Manual" -and !$alreadyPatched) {
                $needsFont = $true
            }

            $candidates.Add([pscustomobject]@{
                SourceFile              = $relativePath
                OriginalFile            = $file.Name
                Container               = $container.LocalName
                ID                      = $id
                XPath                   = $xpath
                Index                   = $indexKey
                Value                   = $value
                Length                  = $value.Length
                Class                   = $classInfo.Class
                Safety                  = $classInfo.Safety
                NeedsFontWhenTranslated = $needsFont
                NeedsLayoutReview       = $needsLayout
                Placeholders            = (Get-AtGPlaceholders -Text $value) -join " "
                AlreadyPatched          = $alreadyPatched
                Reason                  = $classInfo.Reason
            }) | Out-Null
        }
    }
}

$jsonDir = Split-Path -Parent $OutputJson
if ($jsonDir) {
    New-Item -ItemType Directory -Force -Path $jsonDir | Out-Null
}
$csvDir = Split-Path -Parent $OutputCsv
if ($csvDir) {
    New-Item -ItemType Directory -Force -Path $csvDir | Out-Null
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Resolve-Path -LiteralPath $jsonDir).Path + "\" + [System.IO.Path]::GetFileName($OutputJson), ($candidates | ConvertTo-Json -Depth 5), $utf8NoBom)
$candidates | Export-Csv -LiteralPath $OutputCsv -Encoding UTF8 -NoTypeInformation

$summary = $candidates |
    Group-Object Safety, Class |
    Sort-Object Name |
    ForEach-Object {
        [pscustomobject]@{
            Group = $_.Name
            Count = $_.Count
        }
    }

Write-Host "Exported $($candidates.Count) static text candidates."
Write-Host "JSON: $OutputJson"
Write-Host "CSV:  $OutputCsv"
$summary | Format-Table -AutoSize
