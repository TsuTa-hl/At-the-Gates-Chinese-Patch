Set-StrictMode -Version Latest

function Get-AtGBuildContractEntries {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [ValidateSet("MergedFonts", "DynamicCjk")][string]$RendererMode = "DynamicCjk",
        [switch]$SkipFonts
    )

    $entries = @(
        @{ Name = "English text"; RelativePath = "source\English.original.xml"; Type = "File" },
        @{ Name = "UI assembly"; RelativePath = "source\AtTheGatesUI.original.dll"; Type = "File" },
        @{ Name = "Common assembly"; RelativePath = "source\AtTheGatesCommon.original.dll"; Type = "File" },
        @{ Name = "Game executable"; RelativePath = "source\AtTheGatesGame.original.exe"; Type = "File" },
        @{ Name = "ElfTools assembly"; RelativePath = "source\ElfTools.original.dll"; Type = "File" },
        @{ Name = "Config source directory"; RelativePath = "source\Content\Config"; Type = "Directory" },
        @{ Name = "ClanCard source directory"; RelativePath = "source\Content\Images\Interface\ScreenSpecific\ClanCard"; Type = "Directory" },
        @{ Name = "Honor ClanCard assets"; RelativePath = "source\Content\Images\Interface\ScreenSpecific\ClanCard\Honor"; Type = "Directory" },
        @{ Name = "Agriculture ClanCard assets"; RelativePath = "source\Content\Images\Interface\ScreenSpecific\ClanCard\Agriculture"; Type = "Directory" },
        @{ Name = "Livestock ClanCard assets"; RelativePath = "source\Content\Images\Interface\ScreenSpecific\ClanCard\Livestock"; Type = "Directory" },
        @{ Name = "Metalworking ClanCard assets"; RelativePath = "source\Content\Images\Interface\ScreenSpecific\ClanCard\Metalworking"; Type = "Directory" },
        @{ Name = "Crafting ClanCard assets"; RelativePath = "source\Content\Images\Interface\ScreenSpecific\ClanCard\Crafting"; Type = "Directory" },
        @{ Name = "Discovery ClanCard assets"; RelativePath = "source\Content\Images\Interface\ScreenSpecific\ClanCard\Discovery"; Type = "Directory" },
        @{ Name = "Base translation"; RelativePath = "translations\zh-CN.json"; Type = "File" },
        @{ Name = "Runtime key additions"; RelativePath = "translations\runtime-text-key-additions.json"; Type = "File" },
        @{ Name = "Runtime display map"; RelativePath = "translations\runtime-display-strings.json"; Type = "File" },
        @{ Name = "Runtime glyph warmset"; RelativePath = "translations\runtime-glyph-warmset.tsv"; Type = "File" },
        @{ Name = "UI string map"; RelativePath = "translations\hardcoded-strings.json"; Type = "File" },
        @{ Name = "Common string map"; RelativePath = "translations\hardcoded-common-strings.json"; Type = "File" },
        @{ Name = "UI IL map"; RelativePath = "translations\hardcoded-ui-il-strings.json"; Type = "File" },
        @{ Name = "UI IL rewrite map"; RelativePath = "translations\hardcoded-ui-il-rewrite.json"; Type = "File" },
        @{ Name = "UI offset map"; RelativePath = "translations\hardcoded-ui-offsets.json"; Type = "File" },
        @{ Name = "Common IL rewrite map"; RelativePath = "translations\hardcoded-common-il-rewrite.json"; Type = "File" },
        @{ Name = "Common offset map"; RelativePath = "translations\hardcoded-common-offsets.json"; Type = "File" },
        @{ Name = "Game IL rewrite map"; RelativePath = "translations\hardcoded-game-il-rewrite.json"; Type = "File" },
        @{ Name = "ElfTools IL rewrite map"; RelativePath = "translations\hardcoded-elftools-il-rewrite.json"; Type = "File" },
        @{ Name = "Config node map"; RelativePath = "translations\config-node-strings.json"; Type = "File" },
        @{ Name = "Extra config node map"; RelativePath = "translations\config-node-extra-strings.json"; Type = "File" },
        @{ Name = "On-map config node map"; RelativePath = "translations\config-node-onmap-strings.json"; Type = "File" },
        @{ Name = "Misc config node map"; RelativePath = "translations\config-node-misc-strings.json"; Type = "File" },
        @{ Name = "Composite rules"; RelativePath = "translations\composite-text-rules.json"; Type = "File" },
        @{ Name = "Entry-specific composite rules"; RelativePath = "translations\composite-entry-specific-rules.json"; Type = "File" },
        @{ Name = "Tag glossary"; RelativePath = "translations\tag-glossary.json"; Type = "File" },
        @{ Name = "Runtime regular font"; RelativePath = "assets\fonts\NotoSansSC-Regular.otf"; Type = "File" },
        @{ Name = "Runtime bold font"; RelativePath = "assets\fonts\NotoSansSC-Bold.otf"; Type = "File" },
        @{ Name = "Runtime font license"; RelativePath = "assets\fonts\OFL.txt"; Type = "File" }
    )

    if ($RendererMode -eq "MergedFonts" -and !$SkipFonts) {
        $entries += @{ Name = "Original font directory"; RelativePath = "source\fonts-original"; Type = "Directory" }
    }

    return @($entries | ForEach-Object {
        [pscustomobject]@{
            Name = [string]$_.Name
            RelativePath = [string]$_.RelativePath
            Path = Join-Path $ProjectRoot ([string]$_.RelativePath)
            Type = [string]$_.Type
        }
    })
}

function Test-AtGBuildInputs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [ValidateSet("MergedFonts", "DynamicCjk")][string]$RendererMode = "DynamicCjk",
        [switch]$SkipFonts
    )

    $missing = @()
    $entries = Get-AtGBuildContractEntries -ProjectRoot $ProjectRoot -RendererMode $RendererMode -SkipFonts:$SkipFonts
    foreach ($entry in $entries) {
        $exists = if ($entry.Type -eq "Directory") {
            Test-Path -LiteralPath $entry.Path -PathType Container
        }
        else {
            Test-Path -LiteralPath $entry.Path -PathType Leaf
        }
        if (!$exists) {
            $missing += "$($entry.RelativePath) ($($entry.Name))"
        }
    }

    if ($missing.Count -gt 0) {
        throw "Patch build input contract is incomplete:`n - $($missing -join "`n - ")"
    }

    return $entries
}

function Get-AtGBuildContract {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [ValidateSet("MergedFonts", "DynamicCjk")][string]$RendererMode = "DynamicCjk",
        [switch]$SkipFonts
    )

    $entries = Test-AtGBuildInputs -ProjectRoot $ProjectRoot -RendererMode $RendererMode -SkipFonts:$SkipFonts
    $inputHashes = [ordered]@{}
    foreach ($entry in $entries) {
        $inputHashes[$entry.RelativePath] = Get-AtGBuildPathHash -Path $entry.Path
    }
    return [ordered]@{
        SchemaVersion = 2
        RequiredInputs = @($entries | ForEach-Object { $_.RelativePath })
        InputHashes = $inputHashes
        Stages = @(Get-AtGBuildStageContracts -ProjectRoot $ProjectRoot -RendererMode $RendererMode -SkipFonts:$SkipFonts)
        RendererMode = $RendererMode
        SkipFonts = [bool]$SkipFonts
    }
}

function Get-AtGBuildPathHash {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )

    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        return [string](Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    if (!(Test-Path -LiteralPath $Path -PathType Container)) {
        throw "Cannot hash a missing build-contract path: $Path"
    }

    $resolved = (Resolve-Path -LiteralPath $Path).Path.TrimEnd([char[]]@('\', '/'))
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        foreach ($file in @(Get-ChildItem -LiteralPath $resolved -Recurse -File | Sort-Object FullName)) {
            $relative = $file.FullName.Substring($resolved.Length).TrimStart([char[]]@('\', '/')) -replace '\\', '/'
            $line = "$relative`t$((Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant())`n"
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($line)
            [void]$sha.TransformBlock($bytes, 0, $bytes.Length, $bytes, 0)
        }
        [void]$sha.TransformFinalBlock([byte[]]::new(0), 0, 0)
        return ([System.BitConverter]::ToString($sha.Hash)).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Get-AtGConfigNodeOutputPaths {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$ProjectRoot)

    $paths = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($relativeMap in @(
            'translations\config-node-strings.json',
            'translations\config-node-extra-strings.json',
            'translations\config-node-onmap-strings.json',
            'translations\config-node-misc-strings.json')) {
        $map = Get-Content -LiteralPath (Join-Path $ProjectRoot $relativeMap) -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($property in $map.PSObject.Properties) {
            [void]$paths.Add(([string]$property.Name).Replace('/', '\'))
        }
    }
    return @($paths | Sort-Object)
}

function Get-AtGClanCardAliasOutputPaths {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$ProjectRoot)

    $translation = Get-Content -LiteralPath (Join-Path $ProjectRoot 'translations\zh-CN.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $keys = @(
        'TEXT.Name.Discipline.Honor',
        'TEXT.Name.Discipline.Agriculture',
        'TEXT.Name.Discipline.Livestock',
        'TEXT.Name.Discipline.Metalworking',
        'TEXT.Name.Discipline.Crafting',
        'TEXT.Name.Discipline.Discovery'
    )
    $outputs = @()
    foreach ($key in $keys) {
        $property = $translation.PSObject.Properties[$key]
        if ($null -eq $property -or [string]::IsNullOrWhiteSpace([string]$property.Value)) {
            throw "ClanCard alias input is missing a discipline translation: $key"
        }
        $outputs += "Content\Images\Interface\ScreenSpecific\ClanCard\$([string]$property.Value)"
    }
    return @($outputs)
}

function Get-AtGBuildStageContracts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [ValidateSet('MergedFonts', 'DynamicCjk')][string]$RendererMode = 'DynamicCjk',
        [switch]$SkipFonts
    )

    $configOutputs = @(Get-AtGConfigNodeOutputPaths -ProjectRoot $ProjectRoot)
    $clanCardOutputs = @(Get-AtGClanCardAliasOutputPaths -ProjectRoot $ProjectRoot)
    $stages = @(
        [pscustomobject]@{
            Name = 'text-xml'
            RequiredInputs = @('source\English.original.xml', 'translations\zh-CN.json', 'translations\runtime-text-key-additions.json')
            ExpectedOutputs = @('Content\Text\English.xml')
        },
        [pscustomobject]@{
            Name = 'managed-rewrite'
            RequiredInputs = @('source\AtTheGatesUI.original.dll', 'source\AtTheGatesCommon.original.dll', 'source\AtTheGatesGame.original.exe', 'source\ElfTools.original.dll', 'translations\hardcoded-ui-il-rewrite.json', 'translations\hardcoded-common-il-rewrite.json', 'translations\hardcoded-game-il-rewrite.json', 'translations\hardcoded-elftools-il-rewrite.json')
            ExpectedOutputs = @('AtTheGatesUI.dll', 'AtTheGatesCommon.dll', 'At The Gates.exe', 'ElfTools.dll')
        },
        [pscustomobject]@{
            Name = 'config-node'
            RequiredInputs = @('source\Content\Config', 'translations\config-node-strings.json', 'translations\config-node-extra-strings.json', 'translations\config-node-onmap-strings.json', 'translations\config-node-misc-strings.json')
            ExpectedOutputs = $configOutputs
        },
        [pscustomobject]@{
            Name = 'clan-card-assets'
            RequiredInputs = @('source\Content\Images\Interface\ScreenSpecific\ClanCard', 'translations\zh-CN.json')
            ExpectedOutputs = $clanCardOutputs
        }
    )
    if ($RendererMode -eq 'DynamicCjk') {
        $stages += [pscustomobject]@{
            Name = 'runtime-text'
            RequiredInputs = @('source\AtTheGatesCommon.original.dll', 'translations\runtime-display-strings.json', 'translations\runtime-glyph-warmset.tsv', 'assets\fonts\NotoSansSC-Regular.otf', 'assets\fonts\NotoSansSC-Bold.otf', 'assets\fonts\OFL.txt')
            ExpectedOutputs = @('AtG.RuntimeText.dll', 'Content\Text\AtG.RuntimeText.tsv', 'Content\Fonts\AtG.RuntimeGlyphWarmset.tsv', 'Content\Fonts\NotoSansSC-Regular.otf', 'Content\Fonts\NotoSansSC-Bold.otf', 'Content\Fonts\OFL.txt')
        }
    }
    return @($stages)
}

function Get-AtGBuildStageEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object[]]$Stages,
        [Parameter(Mandatory = $true)][string]$PatchRoot
    )

    $evidence = @()
    foreach ($stage in $Stages) {
        $outputHashes = [ordered]@{}
        foreach ($relative in @($stage.ExpectedOutputs)) {
            $path = Join-Path $PatchRoot $relative
            if (!(Test-Path -LiteralPath $path)) {
                throw "Build stage '$($stage.Name)' did not produce its contract output: $relative"
            }
            $outputHashes[$relative] = Get-AtGBuildPathHash -Path $path
        }
        $evidence += [pscustomobject]@{
            Name = [string]$stage.Name
            RequiredInputs = @($stage.RequiredInputs)
            ExpectedOutputs = @($stage.ExpectedOutputs)
            OutputHashes = $outputHashes
        }
    }
    return @($evidence)
}

function Test-AtGBuildOutputs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$PatchRoot,
        [string]$ProjectRoot = '',
        [ValidateSet("MergedFonts", "DynamicCjk")][string]$RendererMode = "DynamicCjk"
    )

    $required = @(
        "At The Gates.exe",
        "AtTheGatesUI.dll",
        "AtTheGatesCommon.dll",
        "ElfTools.dll",
        "Content\Text\English.xml"
    )
    if ($RendererMode -eq "DynamicCjk") {
        $required += @(
            "AtG.RuntimeText.dll",
            "Content\Text\AtG.RuntimeText.tsv",
            "Content\Fonts\AtG.RuntimeGlyphWarmset.tsv",
            "Content\Fonts\NotoSansSC-Regular.otf",
            "Content\Fonts\NotoSansSC-Bold.otf"
        )
    }

    $missing = @($required | Where-Object {
        !(Test-Path -LiteralPath (Join-Path $PatchRoot $_) -PathType Leaf)
    })
    if ($missing.Count -gt 0) {
        throw "Patch build output contract is incomplete:`n - $($missing -join "`n - ")"
    }
    if (![string]::IsNullOrWhiteSpace($ProjectRoot)) {
        [void](Get-AtGBuildStageEvidence -Stages (Get-AtGBuildStageContracts -ProjectRoot $ProjectRoot -RendererMode $RendererMode) -PatchRoot $PatchRoot)
    }
}

function Update-AtGBuildReportContract {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ReportPath,
        [Parameter(Mandatory = $true)][string]$FinalPatchRoot,
        [Parameter(Mandatory = $true)][object]$BuildContract
    )

    $report = Get-Content -LiteralPath $ReportPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $report.PatchRoot = $FinalPatchRoot
    if ($null -ne $report.LocalizationInputs -and @($report.LocalizationInputs.MissingFiles).Count -gt 0) {
        throw "Build report lists missing localization inputs: $($report.LocalizationInputs.MissingFiles -join ', ')"
    }
    $report | Add-Member -NotePropertyName BuildContract -NotePropertyValue $BuildContract -Force
    $report.BuildContract.Stages = @(Get-AtGBuildStageEvidence -Stages @($BuildContract.Stages) -PatchRoot (Split-Path -Parent $ReportPath))
    [System.IO.File]::WriteAllText(
        $ReportPath,
        ($report | ConvertTo-Json -Depth 8 -Compress),
        [System.Text.UTF8Encoding]::new($false))
}
