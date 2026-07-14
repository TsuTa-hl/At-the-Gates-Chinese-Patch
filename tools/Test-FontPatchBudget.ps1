param(
    [string]$FontDirectory = "$PSScriptRoot\..\patch\Content\Images\Interface\Components\Fonts",
    [string]$TranslationDirectory = "$PSScriptRoot\..\translations",
    [string]$TextXmlPath = "$PSScriptRoot\..\patch\Content\Text\English.xml",
    [int64]$MaxTotalBytes = 120MB,
    [int]$MaxFontCount = 15,
    [ValidateSet("Auto", "MergedFonts", "DynamicCjk")]
    [string]$RendererMode = "Auto"
)

$ErrorActionPreference = "Stop"

function Assert-AtG {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (!$Condition) {
        throw $Message
    }
}

if ($RendererMode -eq "Auto") {
    $runtimeDll = Join-Path $PSScriptRoot "..\patch\AtG.RuntimeText.dll"
    $RendererMode = if (Test-Path -LiteralPath $runtimeDll -PathType Leaf) { "DynamicCjk" } else { "MergedFonts" }
}

if ($RendererMode -eq "DynamicCjk") {
    $patchRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\patch"))
    $runtimeDll = Join-Path $patchRoot "AtG.RuntimeText.dll"
    $dynamicFontDirectory = Join-Path $patchRoot "Content\Fonts"
    $requiredDynamicFiles = @("NotoSansSC-Regular.otf", "NotoSansSC-Bold.otf", "OFL.txt")
    Assert-AtG (Test-Path -LiteralPath $runtimeDll -PathType Leaf) "Dynamic CJK runtime DLL is missing: $runtimeDll"
    foreach ($fileName in $requiredDynamicFiles) {
        Assert-AtG (Test-Path -LiteralPath (Join-Path $dynamicFontDirectory $fileName) -PathType Leaf) "Dynamic CJK font asset is missing: $fileName"
    }
    $dynamicFontBytes = [int64]((Get-ChildItem -LiteralPath $dynamicFontDirectory -File | Measure-Object Length -Sum).Sum)
    Assert-AtG ($dynamicFontBytes -le 40MB) "Dynamic CJK font assets are $dynamicFontBytes bytes; expected at most 40 MiB."
    $patchedXnb = if (Test-Path -LiteralPath $FontDirectory -PathType Container) {
        @(Get-ChildItem -LiteralPath $FontDirectory -Filter "*.xnb" -File)
    } else { @() }
    Assert-AtG ($patchedXnb.Count -eq 0) "Dynamic CJK mode must not ship merged SpriteFont XNB files."
    Write-Host "Dynamic CJK font budget passed: $dynamicFontBytes bytes, 2 OFL fonts, 0 merged XNB files."
    return
}

$requiredFonts = @(
    "SegoeUI_UltraTiny",
    "SegoeUI_9",
    "SegoeUI_9_Bold",
    "SegoeUI_11",
    "SegoeUI_11_Bold",
    "SegoeUI_13",
    "SegoeUI_13_Bold",
    "SegoeUI_15",
    "SegoeUI_15_Bold",
    "SegoeUI_16",
    "SegoeUI_16_Bold",
    "SegoeUI_18",
    "SegoeUI_18_Bold",
    "SegoeUI_22_Bold",
    "SegoeUI_36_Bold"
)

$excludedFonts = @(
    # Non-Segoe fixed/debug or speech fonts are left as original assets in the
    # current 15-font build. The budget target is the 15 Segoe UI
    # runtime fonts with per-font Chinese subsets.
    "Leelawalee_10",
    "LucidaConsole_10_AtG"
)

Assert-AtG (Test-Path -LiteralPath $FontDirectory -PathType Container) "Font patch directory not found: $FontDirectory"

$marker = Join-Path $FontDirectory ".atg-merged-fonts"
Assert-AtG (Test-Path -LiteralPath $marker -PathType Leaf) "Merged font marker is missing: $marker"

$fonts = @(Get-ChildItem -LiteralPath $FontDirectory -Filter "*.xnb" -File)
$totalBytes = [int64](($fonts | Measure-Object -Property Length -Sum).Sum)

Assert-AtG ($fonts.Count -le $MaxFontCount) "Generated font patch has $($fonts.Count) XNB files; expected at most $MaxFontCount."
Assert-AtG ($totalBytes -le $MaxTotalBytes) "Generated font patch is $totalBytes bytes; expected at most $MaxTotalBytes bytes."

$fontNames = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
foreach ($font in $fonts) {
    [void]$fontNames.Add($font.BaseName)
}

foreach ($requiredFont in $requiredFonts) {
    Assert-AtG ($fontNames.Contains($requiredFont)) "Required runtime font was not generated: $requiredFont"
}

$generatedExcludedFonts = @($fonts | Where-Object { $excludedFonts -contains $_.BaseName } | Select-Object -ExpandProperty BaseName)
Assert-AtG ($generatedExcludedFonts.Count -eq 0) "Generated font patch includes excluded high-memory fonts: $($generatedExcludedFonts -join ', ')"

$unexpectedFonts = @($fonts | Where-Object { $requiredFonts -notcontains $_.BaseName } | Select-Object -ExpandProperty BaseName)
Assert-AtG ($unexpectedFonts.Count -eq 0) "Generated font patch includes unreferenced fonts: $($unexpectedFonts -join ', ')"

function Add-AtGJsonMapTranslationsToBuilder {
    param(
        [System.Text.StringBuilder]$Builder,
        [string]$MapPath,
        [int]$MaxTranslationLength = 0
    )

    if (!(Test-Path -LiteralPath $MapPath -PathType Leaf)) {
        return
    }

    $map = Get-Content -LiteralPath $MapPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($item in @($map)) {
        if ($null -eq $item) {
            continue
        }

        if ($null -ne $item.PSObject.Properties["Translation"]) {
            $translation = [string]$item.Translation
            if ($MaxTranslationLength -le 0 -or $translation.Length -le $MaxTranslationLength) {
                [void]$Builder.Append($translation)
            }
            continue
        }

        foreach ($property in $item.PSObject.Properties) {
            [void]$Builder.Append([string]$property.Value)
        }
    }
}

function Assert-AtGCharactersPresent {
    param(
        [string]$Name,
        [string]$Characters,
        [string]$ExpectedText
    )

    $missing = New-Object 'System.Collections.Generic.SortedSet[string]' ([System.StringComparer]::Ordinal)
    foreach ($ch in $ExpectedText.ToCharArray()) {
        if ([char]::IsControl($ch)) {
            continue
        }

        if (!$Characters.Contains([string]$ch)) {
            [void]$missing.Add([string]$ch)
        }
    }

    Assert-AtG ($missing.Count -eq 0) "$Name font character set is missing required glyphs: $([string]::Join('', $missing))"
}

function Get-AtGEnglishXmlTextByKeyPattern {
    param(
        [string]$XmlPath,
        [string]$KeyPattern
    )

    if (!(Test-Path -LiteralPath $XmlPath -PathType Leaf)) {
        throw "English.xml not found: $XmlPath"
    }

    $builder = New-Object System.Text.StringBuilder
    $xmlText = Get-Content -LiteralPath $XmlPath -Raw -Encoding UTF8
    $matches = [regex]::Matches($xmlText, '<e\s+ntry\s*=\s*"(?<key>[^"]+)">\s*(?<value>.*?)\s*</e>', [System.Text.RegularExpressions.RegexOptions]::Singleline)
    foreach ($match in $matches) {
        $key = $match.Groups["key"].Value
        if ($key -notmatch $KeyPattern) {
            continue
        }

        $value = [System.Net.WebUtility]::HtmlDecode($match.Groups["value"].Value).Trim()
        [void]$builder.Append($value)
    }

    return $builder.ToString()
}

function Add-AtGConfigNodeDisplayTextToBuilder {
    param(
        [System.Text.StringBuilder]$Builder,
        [string]$MapPath
    )

    if (!(Test-Path -LiteralPath $MapPath -PathType Leaf)) {
        return
    }

    $map = Get-Content -LiteralPath $MapPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($fileEntry in $map.PSObject.Properties) {
        foreach ($item in @($fileEntry.Value.Items)) {
            if ($null -ne $item.PSObject.Properties["Name"]) {
                [void]$Builder.Append([string]$item.Name)
            }
            if ($null -ne $item.PSObject.Properties["Description"]) {
                [void]$Builder.Append([string]$item.Description)
            }
            if ($null -ne $item.PSObject.Properties["Nodes"]) {
                foreach ($nodePatch in @($item.Nodes)) {
                    if ($null -ne $nodePatch.PSObject.Properties["Value"]) {
                        [void]$Builder.Append([string]$nodePatch.Value)
                    }
                }
            }
        }
    }
}

$fontCharacterSetsPath = Join-Path $FontDirectory ".atg-font-character-sets.json"
Assert-AtG (Test-Path -LiteralPath $fontCharacterSetsPath -PathType Leaf) "Font character-set manifest is missing: $fontCharacterSetsPath"

$fontCharacterSets = Get-Content -LiteralPath $fontCharacterSetsPath -Raw -Encoding UTF8 | ConvertFrom-Json
$bodyCharactersProperty = $fontCharacterSets.PSObject.Properties["BodyCharacters"]
Assert-AtG ($null -ne $bodyCharactersProperty) "Font character-set manifest is missing BodyCharacters."
$microCharactersProperty = $fontCharacterSets.PSObject.Properties["MicroUiCharacters"]
Assert-AtG ($null -ne $microCharactersProperty) "Font character-set manifest is missing MicroUiCharacters."
$perFontCharactersProperty = $fontCharacterSets.PSObject.Properties["PerFontCharacters"]
Assert-AtG ($null -ne $perFontCharactersProperty) "Font character-set manifest is missing PerFontCharacters."

$perFontCharacters = $fontCharacterSets.PerFontCharacters
$uniquePerFontSets = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
foreach ($requiredFont in $requiredFonts) {
    $property = $perFontCharacters.PSObject.Properties[$requiredFont]
    Assert-AtG ($null -ne $property) "Font character-set manifest is missing per-font characters for $requiredFont."
    Assert-AtG (![string]::IsNullOrEmpty([string]$property.Value)) "Per-font character set is empty for $requiredFont."
    [void]$uniquePerFontSets.Add([string]$property.Value)
}
Assert-AtG ($uniquePerFontSets.Count -ge 6) "Expected at least 6 distinct font role character sets; found $($uniquePerFontSets.Count)."

$ilRewriteTranslations = New-Object System.Text.StringBuilder
$shortIlRewriteTranslations = New-Object System.Text.StringBuilder
foreach ($mapName in @(
    "hardcoded-ui-il-rewrite.json",
    "hardcoded-ui-il-strings.json",
    "hardcoded-common-il-rewrite.json",
    "hardcoded-game-il-rewrite.json",
    "hardcoded-elftools-il-rewrite.json"
)) {
    $mapPath = Join-Path $TranslationDirectory $mapName
    Add-AtGJsonMapTranslationsToBuilder -Builder $ilRewriteTranslations -MapPath $mapPath
    Add-AtGJsonMapTranslationsToBuilder -Builder $shortIlRewriteTranslations -MapPath $mapPath -MaxTranslationLength 32
}

Assert-AtGCharactersPresent -Name "Body" -Characters ([string]$fontCharacterSets.BodyCharacters) -ExpectedText $ilRewriteTranslations.ToString()
Assert-AtGCharactersPresent -Name "LargeUi" -Characters ([string]$fontCharacterSets.LargeUiCharacters) -ExpectedText $shortIlRewriteTranslations.ToString()
Assert-AtGCharactersPresent -Name "MicroUi" -Characters ([string]$fontCharacterSets.MicroUiCharacters) -ExpectedText $shortIlRewriteTranslations.ToString()
Assert-AtGCharactersPresent -Name "SegoeUI_15" -Characters ([string]$perFontCharacters.SegoeUI_15) -ExpectedText $ilRewriteTranslations.ToString()
Assert-AtGCharactersPresent -Name "SegoeUI_15_Bold" -Characters ([string]$perFontCharacters.SegoeUI_15_Bold) -ExpectedText $shortIlRewriteTranslations.ToString()
Assert-AtGCharactersPresent -Name "SegoeUI_36_Bold" -Characters ([string]$perFontCharacters.SegoeUI_36_Bold) -ExpectedText $shortIlRewriteTranslations.ToString()

$descriptionText = Get-AtGEnglishXmlTextByKeyPattern -XmlPath $TextXmlPath -KeyPattern '^TEXT\.Description\.'
Assert-AtGCharactersPresent -Name "Body" -Characters ([string]$fontCharacterSets.BodyCharacters) -ExpectedText $descriptionText
foreach ($bodyFont in @("SegoeUI_13", "SegoeUI_15", "SegoeUI_15_Bold")) {
    Assert-AtGCharactersPresent -Name $bodyFont -Characters ([string]$perFontCharacters.$bodyFont) -ExpectedText $descriptionText
}

$configNodeText = New-Object System.Text.StringBuilder
foreach ($mapName in @(
    "config-node-strings.json",
    "config-node-extra-strings.json",
    "config-node-onmap-strings.json"
)) {
    $mapPath = Join-Path $TranslationDirectory $mapName
    Add-AtGConfigNodeDisplayTextToBuilder -Builder $configNodeText -MapPath $mapPath
}

Assert-AtGCharactersPresent -Name "Body" -Characters ([string]$fontCharacterSets.BodyCharacters) -ExpectedText $configNodeText.ToString()
foreach ($bodyFont in @("SegoeUI_13", "SegoeUI_15", "SegoeUI_15_Bold")) {
    Assert-AtGCharactersPresent -Name $bodyFont -Characters ([string]$perFontCharacters.$bodyFont) -ExpectedText $configNodeText.ToString()
}

[pscustomobject]@{
    FontCount = $fonts.Count
    TotalBytes = $totalBytes
    MaxTotalBytes = $MaxTotalBytes
}

Write-Host "Font patch budget validation passed."
