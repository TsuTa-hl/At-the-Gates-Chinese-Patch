param(
    [string[]]$MapJson = @("$PSScriptRoot\..\translations\config-node-strings.json"),
    [string]$ProjectRoot = "$PSScriptRoot\..",
    [string]$PatchRoot = "$PSScriptRoot\..\patch"
)

$ErrorActionPreference = "Stop"

foreach ($mapPath in $MapJson) {
    if (!(Test-Path -LiteralPath $mapPath)) {
        throw "Config node map not found: $mapPath"
    }
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$documents = @{}

function Test-JsonProperty {
    param(
        [object]$Object,
        [string]$Name
    )

    return $null -ne $Object.PSObject.Properties[$Name]
}

function Set-AtGConfigNodeText {
    param(
        [System.Xml.XmlNode]$ContainerNode,
        [string]$XPath,
        [object]$Index,
        [string]$Value,
        [string]$ID,
        [string]$SourcePath
    )

    $nodes = @($ContainerNode.SelectNodes($XPath))
    if ($nodes.Count -eq 0) {
        throw "Unable to find node '$XPath' for ID '$ID' in $SourcePath"
    }

    if ($null -ne $Index) {
        $nodeIndex = [int]$Index
        if ($nodeIndex -lt 0 -or $nodeIndex -ge $nodes.Count) {
            throw "Index $nodeIndex is out of range for node '$XPath' on ID '$ID' in $SourcePath"
        }
        $node = $nodes[$nodeIndex]
    }
    elseif ($nodes.Count -eq 1) {
        $node = $nodes[0]
    }
    else {
        throw "Node '$XPath' matched $($nodes.Count) nodes for ID '$ID' in $SourcePath; specify Index."
    }

    $oldValue = $node.InnerText
    $node.InnerText = $Value
    return "Patched config node '$ID' $XPath '$oldValue' -> '$Value'."
}

foreach ($mapPath in $MapJson) {
    $map = Get-Content -LiteralPath $mapPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($fileEntry in $map.PSObject.Properties) {
        $relativeOutput = [string]$fileEntry.Name
        $config = $fileEntry.Value
        $sourcePath = Join-Path $ProjectRoot ([string]$config.Source)
        $container = [string]$config.Container

        if (!(Test-Path -LiteralPath $sourcePath)) {
            throw "Config source not found: $sourcePath"
        }
        if ([string]::IsNullOrWhiteSpace($container)) {
            throw "Missing container for config node patch: $relativeOutput"
        }

        if (!$documents.ContainsKey($relativeOutput)) {
            $documents[$relativeOutput] = [pscustomobject]@{
                Xml       = [xml](Get-Content -LiteralPath $sourcePath -Raw -Encoding UTF8)
                Container = $container
            }
        }

        $document = $documents[$relativeOutput]
        if ([string]$document.Container -ne $container) {
            throw "Conflicting container for config node patch: $relativeOutput"
        }

        foreach ($item in @($config.Items)) {
            $id = [string]$item.ID
            if ([string]::IsNullOrWhiteSpace($id)) {
                throw "Missing ID in config node patch: $relativeOutput"
            }

            $containerNode = $document.Xml.SelectSingleNode("//$container[ID='$id']")
            if (!$containerNode) {
                throw "Unable to find //$container[ID='$id'] in $sourcePath"
            }

            if (Test-JsonProperty $item "Name") {
                $message = Set-AtGConfigNodeText -ContainerNode $containerNode -XPath "name" -Value ([string]$item.Name) -ID $id -SourcePath $sourcePath
                Write-Host "$message in $relativeOutput"
            }

            if (Test-JsonProperty $item "Description") {
                $message = Set-AtGConfigNodeText -ContainerNode $containerNode -XPath "description" -Value ([string]$item.Description) -ID $id -SourcePath $sourcePath
                Write-Host "$message in $relativeOutput"
            }

            if (Test-JsonProperty $item "Nodes") {
                foreach ($nodePatch in @($item.Nodes)) {
                    $xpath = [string]$nodePatch.XPath
                    if ([string]::IsNullOrWhiteSpace($xpath)) {
                        throw "Missing XPath for node patch on ID '$id' in $relativeOutput"
                    }

                    $index = $null
                    if (Test-JsonProperty $nodePatch "Index") {
                        $index = [int]$nodePatch.Index
                    }

                    $message = Set-AtGConfigNodeText -ContainerNode $containerNode -XPath $xpath -Index $index -Value ([string]$nodePatch.Value) -ID $id -SourcePath $sourcePath
                    Write-Host "$message in $relativeOutput"
                }
            }
        }
    }
}

foreach ($relativeOutput in $documents.Keys) {
    $outputPath = Join-Path $PatchRoot $relativeOutput
    $outDir = Split-Path -Parent $outputPath
    if ($outDir) {
        New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    }

    $settings = New-Object System.Xml.XmlWriterSettings
    $settings.Indent = $true
    $settings.Encoding = $utf8NoBom
    $settings.OmitXmlDeclaration = $true
    $settings.NewLineChars = "`r`n"
    $settings.NewLineHandling = [System.Xml.NewLineHandling]::Replace

    $writer = [System.Xml.XmlWriter]::Create($outputPath, $settings)
    try {
        $documents[$relativeOutput].Xml.Save($writer)
    }
    finally {
        $writer.Close()
    }

    Write-Host "Built config node patch: $outputPath"
}
