param(
    [string]$FontDirectory = "$PSScriptRoot\..\patch\Content\Images\Interface\Components\Fonts",
    [string]$TranslationDirectory = "$PSScriptRoot\..\translations",
    [int64]$MaxTotalBytes = 120MB,
    [int]$MaxFontCount = 20
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

$requiredFonts = @(
    "Leelawalee_10",
    "LucidaConsole_10_AtG",
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

$unexpectedFonts = @($fonts | Where-Object { $requiredFonts -notcontains $_.BaseName } | Select-Object -ExpandProperty BaseName)
Assert-AtG ($unexpectedFonts.Count -eq 0) "Generated font patch includes unreferenced fonts: $($unexpectedFonts -join ', ')"

function Add-AtGJsonMapTranslationsToBuilder {
    param(
        [System.Text.StringBuilder]$Builder,
        [string]$MapPath
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
            [void]$Builder.Append([string]$item.Translation)
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

    Assert-AtG ($missing.Count -eq 0) "$Name font character set is missing translated IL rewrite glyphs: $([string]::Join('', $missing))"
}

$fontCharacterSetsPath = Join-Path $FontDirectory ".atg-font-character-sets.json"
Assert-AtG (Test-Path -LiteralPath $fontCharacterSetsPath -PathType Leaf) "Font character-set manifest is missing: $fontCharacterSetsPath"

$fontCharacterSets = Get-Content -LiteralPath $fontCharacterSetsPath -Raw -Encoding UTF8 | ConvertFrom-Json
$ilRewriteTranslations = New-Object System.Text.StringBuilder
foreach ($mapName in @(
    "hardcoded-ui-il-rewrite.json",
    "hardcoded-ui-il-strings.json",
    "hardcoded-common-il-rewrite.json",
    "hardcoded-game-il-rewrite.json"
)) {
    Add-AtGJsonMapTranslationsToBuilder -Builder $ilRewriteTranslations -MapPath (Join-Path $TranslationDirectory $mapName)
}

Assert-AtGCharactersPresent -Name "Full" -Characters ([string]$fontCharacterSets.FullCharacters) -ExpectedText $ilRewriteTranslations.ToString()
Assert-AtGCharactersPresent -Name "LargeUi" -Characters ([string]$fontCharacterSets.LargeUiCharacters) -ExpectedText $ilRewriteTranslations.ToString()

[pscustomobject]@{
    FontCount = $fonts.Count
    TotalBytes = $totalBytes
    MaxTotalBytes = $MaxTotalBytes
}

Write-Host "Font patch budget validation passed."
