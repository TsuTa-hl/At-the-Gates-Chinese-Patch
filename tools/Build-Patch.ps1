param(
    [string]$SourceXml = "$PSScriptRoot\..\source\English.original.xml",
    [string]$TranslationJson = "$PSScriptRoot\..\translations\zh-CN.json",
    [string]$PatchRoot = "$PSScriptRoot\..\patch",
    [string]$OriginalFontDir = "$PSScriptRoot\..\source\fonts-original",
    [switch]$PatchCommonConceptTerms,
    [switch]$SkipFonts
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\AtGTiming.ps1"

$timing = New-AtGTimingSummary

function Get-AtGMapOriginals {
    param([string]$MapPath)

    $originals = @()
    if (!(Test-Path -LiteralPath $MapPath -PathType Leaf)) {
        return $originals
    }

    $json = Get-Content -LiteralPath $MapPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($item in @($json)) {
        if ($null -eq $item) {
            continue
        }

        if ($null -ne $item.PSObject.Properties["Original"]) {
            $originals += [string]$item.Original
            continue
        }

        foreach ($property in $item.PSObject.Properties) {
            $originals += [string]$property.Name
        }
    }

    return $originals
}

$textOut = Join-Path $PatchRoot "Content\Text\English.xml"
Measure-AtGStage -Summary $timing -Name "text-xml" -ScriptBlock {
    & "$PSScriptRoot\Build-ChineseXml.ps1" -SourceXml $SourceXml -TranslationJson $TranslationJson -OutputXml $textOut
    & "$PSScriptRoot\Test-TextTags.ps1" -SourceXml $SourceXml -PatchedXml $textOut
}

$hardcodedSource = Join-Path $PSScriptRoot "..\source\AtTheGatesUI.original.dll"
if (Test-Path -LiteralPath $hardcodedSource) {
    $hardcodedOutput = Join-Path $PatchRoot "AtTheGatesUI.dll"
    Measure-AtGStage -Summary $timing -Name "ui-dll" -ScriptBlock {
        $uiRewriteMap = Join-Path $PSScriptRoot "..\translations\hardcoded-ui-il-rewrite.json"
        $uiIlMap = Join-Path $PSScriptRoot "..\translations\hardcoded-ui-il-strings.json"
        $uiCoveredSources = @()
        $uiDllInput = $hardcodedSource
        if (Test-Path -LiteralPath $uiRewriteMap) {
            & "$PSScriptRoot\Build-IlRewritePatch.ps1" -SourceDll $uiDllInput -OutputDll $hardcodedOutput -MapJson $uiRewriteMap
            $uiCoveredSources += Get-AtGMapOriginals -MapPath $uiRewriteMap
            $uiDllInput = $hardcodedOutput
        }

        if (Test-Path -LiteralPath $uiIlMap) {
            & "$PSScriptRoot\Build-IlStringPatch.ps1" `
                -SourceDll $uiDllInput `
                -OutputDll $hardcodedOutput `
                -MapJson $uiIlMap `
                -SkipSourceStrings $uiCoveredSources
            $uiCoveredSources += Get-AtGMapOriginals -MapPath $uiIlMap
        }
        elseif (!(Test-Path -LiteralPath $uiRewriteMap)) {
            Copy-Item -LiteralPath $hardcodedSource -Destination $hardcodedOutput -Force
        }

        & "$PSScriptRoot\Build-HardcodedPatch.ps1" `
            -SourceDll $hardcodedOutput `
            -OutputDll $hardcodedOutput `
            -PaddingCodePoint 0x200B `
            -SkipSourceStrings $uiCoveredSources

        $hardcodedUiOffsetMap = Join-Path $PSScriptRoot "..\translations\hardcoded-ui-offsets.json"
        if (Test-Path -LiteralPath $hardcodedUiOffsetMap) {
            & "$PSScriptRoot\Build-OffsetStringPatch.ps1" `
                -SourceDll $hardcodedOutput `
                -OutputDll $hardcodedOutput `
                -MapJson $hardcodedUiOffsetMap `
                -SkipSourceStrings $uiCoveredSources
        }
    }
}
else {
    Write-Host "Skipping hardcoded DLL patch; source\AtTheGatesUI.original.dll not found."
}

$hardcodedCommonSource = Join-Path $PSScriptRoot "..\source\AtTheGatesCommon.original.dll"
$hardcodedCommonMap = Join-Path $PSScriptRoot "..\translations\hardcoded-common-strings.json"
if ((Test-Path -LiteralPath $hardcodedCommonSource) -and (Test-Path -LiteralPath $hardcodedCommonMap)) {
    $hardcodedCommonOutput = Join-Path $PatchRoot "AtTheGatesCommon.dll"
    Measure-AtGStage -Summary $timing -Name "common-dll" -ScriptBlock {
        $commonRewriteMap = Join-Path $PSScriptRoot "..\translations\hardcoded-common-il-rewrite.json"
        $commonCoveredSources = @()
        $commonDllInput = $hardcodedCommonSource
        if (Test-Path -LiteralPath $commonRewriteMap) {
            & "$PSScriptRoot\Build-IlRewritePatch.ps1" -SourceDll $commonDllInput -OutputDll $hardcodedCommonOutput -MapJson $commonRewriteMap
            $commonCoveredSources += Get-AtGMapOriginals -MapPath $commonRewriteMap
            $commonDllInput = $hardcodedCommonOutput
        }

        & "$PSScriptRoot\Build-HardcodedPatch.ps1" `
            -SourceDll $commonDllInput `
            -OutputDll $hardcodedCommonOutput `
            -MapJson $hardcodedCommonMap `
            -PaddingCodePoint 0x200B `
            -SkipSourceStrings $commonCoveredSources

        $hardcodedCommonOffsetMap = Join-Path $PSScriptRoot "..\translations\hardcoded-common-offsets.json"
        if ($PatchCommonConceptTerms -and (Test-Path -LiteralPath $hardcodedCommonOffsetMap)) {
            & "$PSScriptRoot\Build-OffsetStringPatch.ps1" -SourceDll $hardcodedCommonOutput -OutputDll $hardcodedCommonOutput -MapJson $hardcodedCommonOffsetMap
        }
    }
}
else {
    Write-Host "Skipping common DLL patch; source\AtTheGatesCommon.original.dll or translations\hardcoded-common-strings.json not found."
}

$gameExeSource = Join-Path $PSScriptRoot "..\source\AtTheGatesGame.original.exe"
$gameExeRewriteMap = Join-Path $PSScriptRoot "..\translations\hardcoded-game-il-rewrite.json"
if (Test-Path -LiteralPath $gameExeRewriteMap) {
    if (!(Test-Path -LiteralPath $gameExeSource -PathType Leaf)) {
        throw "Game EXE rewrite map exists but source\AtTheGatesGame.original.exe is missing."
    }

    $gameExeOutput = Join-Path $PatchRoot "At The Gates.exe"
    Measure-AtGStage -Summary $timing -Name "game-exe" -ScriptBlock {
        & "$PSScriptRoot\Build-IlRewritePatch.ps1" -SourceDll $gameExeSource -OutputDll $gameExeOutput -MapJson $gameExeRewriteMap
    }
}

$configMap = Join-Path $PSScriptRoot "..\translations\config-strings.json"
if (Test-Path -LiteralPath $configMap) {
    Measure-AtGStage -Summary $timing -Name "config" -ScriptBlock {
        & "$PSScriptRoot\Build-ConfigPatch.ps1" -MapJson $configMap -PatchRoot $PatchRoot
    }
}
else {
    Write-Host "Skipping config patch; translations\config-strings.json not found."
}

$configNodeMaps = @(
    (Join-Path $PSScriptRoot "..\translations\config-node-strings.json"),
    (Join-Path $PSScriptRoot "..\translations\config-node-extra-strings.json")
) | Where-Object { Test-Path -LiteralPath $_ }
if ($configNodeMaps.Count -gt 0) {
    Measure-AtGStage -Summary $timing -Name "config-node" -ScriptBlock {
        & "$PSScriptRoot\Build-ConfigNodePatch.ps1" -MapJson $configNodeMaps -PatchRoot $PatchRoot
    }
}
else {
    Write-Host "Skipping config node patch; translations\config-node-strings.json not found."
}

function Remove-AtGGeneratedPatchDirectory {
    param(
        [string]$Directory,
        [string]$RootDirectory
    )

    if (!(Test-Path -LiteralPath $Directory)) {
        return
    }

    $resolvedRoot = (Resolve-Path -LiteralPath $RootDirectory).Path.TrimEnd("\", "/")
    $resolvedDirectory = (Resolve-Path -LiteralPath $Directory).Path.TrimEnd("\", "/")
    if (!$resolvedDirectory.StartsWith($resolvedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove generated patch directory outside patch root: $resolvedDirectory"
    }

    Remove-Item -LiteralPath $resolvedDirectory -Recurse -Force
}

function Copy-ClanCardDisciplineAliases {
    param(
        [string]$SourceDirectory,
        [string]$DestinationDirectory,
        [string]$TranslationJsonPath,
        [string]$RootDirectory
    )

    if (!(Test-Path -LiteralPath $SourceDirectory)) {
        Write-Host "Skipping ClanCard discipline aliases; source directory not found: $SourceDirectory"
        return
    }

    if (!(Test-Path -LiteralPath $TranslationJsonPath)) {
        Write-Host "Skipping ClanCard discipline aliases; translation JSON not found: $TranslationJsonPath"
        return
    }

    $translationObject = Get-Content -LiteralPath $TranslationJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $disciplineAssets = [ordered]@{
        Honor        = "TEXT.Name.Discipline.Honor"
        Agriculture  = "TEXT.Name.Discipline.Agriculture"
        Livestock    = "TEXT.Name.Discipline.Livestock"
        Metalworking = "TEXT.Name.Discipline.Metalworking"
        Crafting     = "TEXT.Name.Discipline.Crafting"
        Discovery    = "TEXT.Name.Discipline.Discovery"
    }

    Remove-AtGGeneratedPatchDirectory -Directory $DestinationDirectory -RootDirectory $RootDirectory
    New-Item -ItemType Directory -Force -Path $DestinationDirectory | Out-Null

    $copied = 0
    foreach ($assetName in $disciplineAssets.Keys) {
        $sourceAssetDirectory = Join-Path $SourceDirectory $assetName
        if (!(Test-Path -LiteralPath $sourceAssetDirectory)) {
            Write-Host "Skipping ClanCard alias for $assetName; source assets not found."
            continue
        }

        $translationProperty = $translationObject.PSObject.Properties[$disciplineAssets[$assetName]]
        if ($null -eq $translationProperty) {
            Write-Host "Skipping ClanCard alias for $assetName; translation key not found."
            continue
        }

        $aliasName = ([string]$translationProperty.Value).Trim()
        if ([string]::IsNullOrWhiteSpace($aliasName) -or $aliasName -eq $assetName) {
            continue
        }

        $aliasDirectory = Join-Path $DestinationDirectory $aliasName
        New-Item -ItemType Directory -Force -Path $aliasDirectory | Out-Null
        Get-ChildItem -LiteralPath $sourceAssetDirectory -Force | Copy-Item -Destination $aliasDirectory -Recurse -Force
        $copied++
    }

    Write-Host "Copied $copied ClanCard discipline asset alias directories."
}

$clanCardSourceDirectory = Join-Path $PSScriptRoot "..\source\Content\Images\Interface\ScreenSpecific\ClanCard"
$clanCardDestinationDirectory = Join-Path $PatchRoot "Content\Images\Interface\ScreenSpecific\ClanCard"
Measure-AtGStage -Summary $timing -Name "clan-card-assets" -ScriptBlock {
    Copy-ClanCardDisciplineAliases `
        -SourceDirectory $clanCardSourceDirectory `
        -DestinationDirectory $clanCardDestinationDirectory `
        -TranslationJsonPath $TranslationJson `
        -RootDirectory $PatchRoot
}

function Remove-AtGGeneratedFontPatch {
    param(
        [string]$FontDirectory,
        [string]$RootDirectory,
        [int]$MaxAttempts = 5
    )

    if (!(Test-Path -LiteralPath $FontDirectory)) {
        return
    }

    $resolvedRoot = (Resolve-Path -LiteralPath $RootDirectory).Path.TrimEnd("\", "/")
    $resolvedFontDirectory = (Resolve-Path -LiteralPath $FontDirectory).Path.TrimEnd("\", "/")
    if (!$resolvedFontDirectory.StartsWith($resolvedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove font patch outside patch root: $resolvedFontDirectory"
    }

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            Remove-Item -LiteralPath $resolvedFontDirectory -Recurse -Force
            return
        }
        catch {
            if ($attempt -ge $MaxAttempts) {
                throw "Unable to remove generated font patch after $MaxAttempts attempts: $resolvedFontDirectory. $($_.Exception.Message)"
            }

            $delayMs = [Math]::Min(2000, 250 * [Math]::Pow(2, $attempt - 1))
            Write-Warning ("Generated font patch directory is temporarily locked; retrying removal attempt {0}/{1} after {2} ms." -f ($attempt + 1), $MaxAttempts, $delayMs)
            [GC]::Collect()
            [GC]::WaitForPendingFinalizers()
            Start-Sleep -Milliseconds $delayMs
        }
    }
}

$fontOutDir = Join-Path $PatchRoot "Content\Images\Interface\Components\Fonts"
$fontMarker = Join-Path $fontOutDir ".atg-merged-fonts"
if ($SkipFonts) {
    Remove-AtGGeneratedFontPatch -FontDirectory $fontOutDir -RootDirectory $PatchRoot
    Write-Host "Skipping font generation. Removed stale generated SpriteFont files from patch output."
    return
}

if (!(Test-Path -LiteralPath $OriginalFontDir)) {
    throw "Original font directory not found: $OriginalFontDir. Restore it from the game backup or run with -SkipFonts."
}

New-Item -ItemType Directory -Force -Path $fontOutDir | Out-Null

$text = Get-Content -LiteralPath $textOut -Raw -Encoding UTF8
$extraCharactersPath = Join-Path $PSScriptRoot "..\translations\common-chars.txt"
if (Test-Path -LiteralPath $extraCharactersPath) {
    $extraCharacters = Get-Content -LiteralPath $extraCharactersPath -Raw -Encoding UTF8
}
else {
    $extraCharacters = ""
}

function Add-AtGJsonMapTranslationsToBuilder {
    param(
        [System.Text.StringBuilder]$Builder,
        [string]$MapPath
    )

    if (!(Test-Path -LiteralPath $MapPath)) {
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

$charsBuilder = New-Object System.Text.StringBuilder
[void]$charsBuilder.Append($text)
[void]$charsBuilder.Append($extraCharacters)
[void]$charsBuilder.Append([char]0x200B)

$fontJsonMapPaths = @(
    (Join-Path $PSScriptRoot "..\translations\hardcoded-strings.json"),
    (Join-Path $PSScriptRoot "..\translations\hardcoded-common-strings.json"),
    (Join-Path $PSScriptRoot "..\translations\hardcoded-ui-il-rewrite.json"),
    (Join-Path $PSScriptRoot "..\translations\hardcoded-ui-il-strings.json"),
    (Join-Path $PSScriptRoot "..\translations\hardcoded-common-il-rewrite.json"),
    (Join-Path $PSScriptRoot "..\translations\hardcoded-game-il-rewrite.json"),
    (Join-Path $PSScriptRoot "..\translations\hardcoded-ui-offsets.json")
)
foreach ($mapPath in $fontJsonMapPaths) {
    Add-AtGJsonMapTranslationsToBuilder -Builder $charsBuilder -MapPath $mapPath
}

$hardcodedCommonOffsetMapPath = Join-Path $PSScriptRoot "..\translations\hardcoded-common-offsets.json"
if ($PatchCommonConceptTerms -and (Test-Path -LiteralPath $hardcodedCommonOffsetMapPath)) {
    Add-AtGJsonMapTranslationsToBuilder -Builder $charsBuilder -MapPath $hardcodedCommonOffsetMapPath
}

$configMapPath = Join-Path $PSScriptRoot "..\translations\config-strings.json"
if (Test-Path -LiteralPath $configMapPath) {
    $configTextMap = Get-Content -LiteralPath $configMapPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($fileEntry in $configTextMap.PSObject.Properties) {
        foreach ($replacement in $fileEntry.Value.Replacements.PSObject.Properties) {
            [void]$charsBuilder.Append([string]$replacement.Value)
        }
    }
}

$configNodeMapPaths = @(
    (Join-Path $PSScriptRoot "..\translations\config-node-strings.json"),
    (Join-Path $PSScriptRoot "..\translations\config-node-extra-strings.json")
) | Where-Object { Test-Path -LiteralPath $_ }
foreach ($configNodeMapPath in $configNodeMapPaths) {
    $configNodeTextMap = Get-Content -LiteralPath $configNodeMapPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($fileEntry in $configNodeTextMap.PSObject.Properties) {
        foreach ($item in @($fileEntry.Value.Items)) {
            if ($null -ne $item.PSObject.Properties["Name"]) {
                [void]$charsBuilder.Append([string]$item.Name)
            }
            if ($null -ne $item.PSObject.Properties["Description"]) {
                [void]$charsBuilder.Append([string]$item.Description)
            }
            if ($null -ne $item.PSObject.Properties["Nodes"]) {
                foreach ($nodePatch in @($item.Nodes)) {
                    [void]$charsBuilder.Append([string]$nodePatch.Value)
                }
            }
        }
    }
}

$chars = $charsBuilder.ToString()

function Add-AtGShortEnglishXmlTextToBuilder {
    param(
        [System.Text.StringBuilder]$Builder,
        [string]$XmlText,
        [int]$MaxLength = 96
    )

    $matches = [regex]::Matches($XmlText, '<e\s+ntry\s*=\s*"[^"]+">\s*(?<value>.*?)\s*</e>', [System.Text.RegularExpressions.RegexOptions]::Singleline)
    foreach ($match in $matches) {
        $value = [System.Net.WebUtility]::HtmlDecode($match.Groups["value"].Value).Trim()
        if ($value.Length -le $MaxLength) {
            [void]$Builder.Append($value)
        }
    }
}

function Get-AtGConfigNodeDisplayText {
    param([string[]]$MapPaths)

    $builder = New-Object System.Text.StringBuilder
    foreach ($mapPath in @($MapPaths)) {
        if (!(Test-Path -LiteralPath $mapPath)) {
            continue
        }

        $configNodeTextMap = Get-Content -LiteralPath $mapPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($fileEntry in $configNodeTextMap.PSObject.Properties) {
            foreach ($item in @($fileEntry.Value.Items)) {
                if ($null -ne $item.PSObject.Properties["Name"]) {
                    [void]$builder.Append([string]$item.Name)
                }
                if ($null -ne $item.PSObject.Properties["Description"]) {
                    [void]$builder.Append([string]$item.Description)
                }
            }
        }
    }

    return $builder.ToString()
}

# Large SpriteFonts are expensive in a 32-bit XNA process. They are used for
# titles, labels, and buttons, so keep them on a UI-focused glyph set while
# smaller body fonts retain the full localized corpus for long text.
$largeFontCharsBuilder = New-Object System.Text.StringBuilder
[void]$largeFontCharsBuilder.Append([char]0x200B)
Add-AtGShortEnglishXmlTextToBuilder -Builder $largeFontCharsBuilder -XmlText $text
foreach ($mapPath in @(
    (Join-Path $PSScriptRoot "..\translations\hardcoded-strings.json"),
    (Join-Path $PSScriptRoot "..\translations\hardcoded-common-strings.json"),
    (Join-Path $PSScriptRoot "..\translations\hardcoded-ui-il-rewrite.json"),
    (Join-Path $PSScriptRoot "..\translations\hardcoded-ui-il-strings.json"),
    (Join-Path $PSScriptRoot "..\translations\hardcoded-common-il-rewrite.json"),
    (Join-Path $PSScriptRoot "..\translations\hardcoded-game-il-rewrite.json"),
    (Join-Path $PSScriptRoot "..\translations\hardcoded-ui-offsets.json")
)) {
    Add-AtGJsonMapTranslationsToBuilder -Builder $largeFontCharsBuilder -MapPath $mapPath
}
[void]$largeFontCharsBuilder.Append((Get-AtGConfigNodeDisplayText -MapPaths $configNodeMapPaths))
$largeFontChars = $largeFontCharsBuilder.ToString()

function Get-AtGUniqueCharacters {
    param([string]$Text)

    $set = New-Object 'System.Collections.Generic.SortedSet[string]' ([System.StringComparer]::Ordinal)
    foreach ($ch in $Text.ToCharArray()) {
        [void]$set.Add([string]$ch)
    }

    return [string]::Join("", $set)
}

# Only override SpriteFonts referenced by the managed runtime catalogs. Leaving
# unreferenced fonts untouched avoids a large 32-bit XNA memory tax during map
# generation while preserving the original game fonts for unused assets.
$fontSpecs = @(
    @{ Name = "Leelawalee_10"; Size = 10; Bold = $false },
    @{ Name = "LucidaConsole_10_AtG"; Size = 10; Bold = $false },
    @{ Name = "SegoeUI_UltraTiny"; Size = 8; Bold = $false },
    @{ Name = "SegoeUI_9"; Size = 9; Bold = $false },
    @{ Name = "SegoeUI_9_Bold"; Size = 9; Bold = $true },
    @{ Name = "SegoeUI_11"; Size = 11; Bold = $false },
    @{ Name = "SegoeUI_11_Bold"; Size = 11; Bold = $true },
    @{ Name = "SegoeUI_13"; Size = 13; Bold = $false },
    @{ Name = "SegoeUI_13_Bold"; Size = 13; Bold = $true },
    @{ Name = "SegoeUI_15"; Size = 15; Bold = $false },
    @{ Name = "SegoeUI_15_Bold"; Size = 15; Bold = $true },
    @{ Name = "SegoeUI_16"; Size = 16; Bold = $false; Profile = "LargeUi" },
    @{ Name = "SegoeUI_16_Bold"; Size = 16; Bold = $true; Profile = "LargeUi" },
    @{ Name = "SegoeUI_18"; Size = 18; Bold = $false; Profile = "LargeUi" },
    @{ Name = "SegoeUI_18_Bold"; Size = 18; Bold = $true; Profile = "LargeUi" },
    @{ Name = "SegoeUI_22_Bold"; Size = 22; Bold = $true; Profile = "LargeUi" },
    @{ Name = "SegoeUI_36_Bold"; Size = 36; Bold = $true; Profile = "LargeUi" }
)

$fontStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$fontCachePath = Join-Path $fontOutDir ".atg-font-cache.json"
$fontCharacterSetsPath = Join-Path $fontOutDir ".atg-font-character-sets.json"
$fontCacheVersion = "merged-fonts-cache-v5-large-ui-pad0"
$fontMarkerVersion = "merged-fonts-v5-large-ui-pad0"
$fontHashBuilder = New-Object System.Text.StringBuilder
[void]$fontHashBuilder.AppendLine($fontCacheVersion)
[void]$fontHashBuilder.AppendLine("full:")
[void]$fontHashBuilder.AppendLine($chars)
[void]$fontHashBuilder.AppendLine("large-ui:")
[void]$fontHashBuilder.AppendLine($largeFontChars)

$expectedFontOutputs = New-Object System.Collections.Generic.List[string]
foreach ($spec in $fontSpecs) {
    $sourceFont = Join-Path $OriginalFontDir ($spec.Name + ".xnb")
    if (!(Test-Path -LiteralPath $sourceFont)) {
        throw "Original SpriteFont not found: $sourceFont"
    }

    $sourceFontItem = Get-Item -LiteralPath $sourceFont
    $profile = if ($null -ne $spec.Profile) { [string]$spec.Profile } else { "Full" }
    $glyphPadding = if ($profile -eq "LargeUi") { 0 } else { 2 }
    [void]$fontHashBuilder.AppendLine("$($spec.Name)|$($spec.Size)|$($spec.Bold)|$profile|padding=$glyphPadding|$($sourceFontItem.Length)|$($sourceFontItem.LastWriteTimeUtc.Ticks)")
    $expectedFontOutputs.Add((Join-Path $fontOutDir ($spec.Name + ".xnb"))) | Out-Null
    $expectedFontOutputs.Add((Join-Path $fontOutDir ($spec.Name + ".png"))) | Out-Null
}

$sha256 = [System.Security.Cryptography.SHA256]::Create()
try {
    $fontInputHash = [BitConverter]::ToString($sha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($fontHashBuilder.ToString()))).Replace("-", "").ToLowerInvariant()
}
finally {
    $sha256.Dispose()
}

$fontCacheHit = $false
if ((Test-Path -LiteralPath $fontMarker) -and (Test-Path -LiteralPath $fontCachePath)) {
    try {
        $fontCache = Get-Content -LiteralPath $fontCachePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $allFontOutputsExist = $true
        foreach ($expectedFontOutput in @($expectedFontOutputs)) {
            if (!(Test-Path -LiteralPath $expectedFontOutput -PathType Leaf)) {
                $allFontOutputsExist = $false
                break
            }
        }
        $fontCacheHit = ($fontCache.InputHash -eq $fontInputHash -and $allFontOutputsExist)
    }
    catch {
        $fontCacheHit = $false
    }
}

if ($fontCacheHit) {
    Write-Host "Skipping font generation; merged font cache hit."
}
else {
    Remove-AtGGeneratedFontPatch -FontDirectory $fontOutDir -RootDirectory $PatchRoot
    New-Item -ItemType Directory -Force -Path $fontOutDir | Out-Null

    foreach ($spec in $fontSpecs) {
        $sourceFont = Join-Path $OriginalFontDir ($spec.Name + ".xnb")
        $xnb = Join-Path $fontOutDir ($spec.Name + ".xnb")
        $png = Join-Path $fontOutDir ($spec.Name + ".png")
        Write-Host "Generating merged font $($spec.Name)..."
        $charactersForFont = if ($spec.Profile -eq "LargeUi") { $largeFontChars } else { $chars }
        $glyphPadding = if ($spec.Profile -eq "LargeUi") { 0 } else { 2 }
        $args = @{
            SourcePath     = $sourceFont
            OutputPath     = $xnb
            PreviewPngPath = $png
            Characters     = $charactersForFont
            FontSize       = [float]$spec.Size
            FontFamily     = "Microsoft YaHei UI"
            TextureWidth   = 4096
            Padding        = $glyphPadding
        }
        if ($spec.Bold) {
            & "$PSScriptRoot\New-XnaMergedSpriteFont.ps1" @args -Bold
        }
        else {
            & "$PSScriptRoot\New-XnaMergedSpriteFont.ps1" @args
        }
    }

    $fontMarkerVersion | Set-Content -LiteralPath $fontMarker -Encoding ASCII
    [pscustomobject]@{
        Version = $fontCacheVersion
        InputHash = $fontInputHash
        GeneratedAtUtc = [DateTime]::UtcNow.ToString("o")
        FontCount = $fontSpecs.Count
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $fontCachePath -Encoding UTF8
}

[pscustomobject]@{
    Version = $fontCacheVersion
    FullCharacters = Get-AtGUniqueCharacters -Text $chars
    LargeUiCharacters = Get-AtGUniqueCharacters -Text $largeFontChars
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $fontCharacterSetsPath -Encoding UTF8

$fontStopwatch.Stop()
$timing.Stages += [pscustomobject]@{
    Name = if ($fontCacheHit) { "fonts-cache-hit" } else { "fonts-generate" }
    DurationMs = [int64]$fontStopwatch.ElapsedMilliseconds
    Duration = $fontStopwatch.Elapsed
}

function Get-AtGJsonArrayCount {
    param([string]$Path)

    if (!(Test-Path -LiteralPath $Path -PathType Leaf)) {
        return 0
    }

    $json = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    return @($json).Count
}

function Get-AtGXmlEntryCount {
    param([string]$Path)

    if (!(Test-Path -LiteralPath $Path -PathType Leaf)) {
        return 0
    }

    $xmlText = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    return [regex]::Matches($xmlText, '<e\s+ntry\s*=').Count
}

function Get-AtGTextAliasCount {
    param(
        [string]$Path,
        [string]$Prefix
    )

    if (!(Test-Path -LiteralPath $Path -PathType Leaf)) {
        return 0
    }

    $xmlText = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $escapedPrefix = [regex]::Escape($Prefix)
    return [regex]::Matches($xmlText, '<e\s+ntry\s*=\s*"' + $escapedPrefix + '[^"]*:(SINGULAR|PLURAL)"').Count
}

function Get-AtGBuildArtifactStatus {
    param(
        [string]$Path,
        [string]$ExpectedFirstLine
    )

    if (!(Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject]@{
            Exists = $false
            FirstLine = $null
            FirstLineMatches = $false
        }
    }

    $firstLine = [string](Get-Content -LiteralPath $Path -Encoding UTF8 -TotalCount 1)
    return [pscustomobject]@{
        Exists = $true
        FirstLine = $firstLine
        FirstLineMatches = if ($null -ne $ExpectedFirstLine) { $firstLine -eq $ExpectedFirstLine } else { $true }
    }
}

$fontXnbFiles = @()
if (Test-Path -LiteralPath $fontOutDir) {
    $fontXnbFiles = @(Get-ChildItem -LiteralPath $fontOutDir -Filter "*.xnb" -File)
}
$fontTotalBytes = 0L
foreach ($fontFile in $fontXnbFiles) {
    $fontTotalBytes += [int64]$fontFile.Length
}

$fontCharacterSets = $null
if (Test-Path -LiteralPath $fontCharacterSetsPath -PathType Leaf) {
    $fontCharacterSets = Get-Content -LiteralPath $fontCharacterSetsPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

$timingReportForJson = foreach ($timingStage in @(Get-AtGTimingReport -Summary $timing)) {
    [ordered]@{
        Stage = [string]$timingStage.Stage
        DurationMs = [int64]$timingStage.DurationMs
        Percent = [double]$timingStage.Percent
    }
}

$metallurgyAliasName = -join ([char[]](0x51B6, 0x91D1))
$metallurgyAliasPath = Join-Path $PatchRoot ("Content\Images\Interface\ScreenSpecific\ClanCard\{0}\PortraitBackground_2.xnb" -f $metallurgyAliasName)

$buildReport = [ordered]@{
    GeneratedAtUtc = [DateTime]::UtcNow.ToString("o")
    PatchRoot = (Resolve-Path -LiteralPath $PatchRoot).Path
    Text = [ordered]@{
        EnglishXml = Get-AtGBuildArtifactStatus -Path $textOut -ExpectedFirstLine "<english>"
        EntryCount = Get-AtGXmlEntryCount -Path $textOut
        AliasCounts = [ordered]@{
            Resource = Get-AtGTextAliasCount -Path $textOut -Prefix "TEXT.Name.Resource."
            Profession = Get-AtGTextAliasCount -Path $textOut -Prefix "TEXT.Name.Profession."
            Discipline = Get-AtGTextAliasCount -Path $textOut -Prefix "TEXT.Name.Discipline."
            Deposit = Get-AtGTextAliasCount -Path $textOut -Prefix "TEXT.Name.Deposit."
        }
    }
    RewriteMaps = [ordered]@{
        UiIlRewrite = Get-AtGJsonArrayCount -Path (Join-Path $PSScriptRoot "..\translations\hardcoded-ui-il-rewrite.json")
        UiIlInPlace = Get-AtGJsonArrayCount -Path (Join-Path $PSScriptRoot "..\translations\hardcoded-ui-il-strings.json")
        UiByteFallback = Get-AtGJsonArrayCount -Path (Join-Path $PSScriptRoot "..\translations\hardcoded-strings.json")
        UiOffsetFallback = Get-AtGJsonArrayCount -Path (Join-Path $PSScriptRoot "..\translations\hardcoded-ui-offsets.json")
        CommonIlRewrite = Get-AtGJsonArrayCount -Path (Join-Path $PSScriptRoot "..\translations\hardcoded-common-il-rewrite.json")
        CommonByteFallback = Get-AtGJsonArrayCount -Path (Join-Path $PSScriptRoot "..\translations\hardcoded-common-strings.json")
        CommonOffsetsEnabled = [bool]$PatchCommonConceptTerms
        GameExeIlRewrite = Get-AtGJsonArrayCount -Path (Join-Path $PSScriptRoot "..\translations\hardcoded-game-il-rewrite.json")
    }
    Fonts = [ordered]@{
        CacheHit = [bool]$fontCacheHit
        InputHash = $fontInputHash
        MarkerExists = Test-Path -LiteralPath $fontMarker -PathType Leaf
        Marker = if (Test-Path -LiteralPath $fontMarker -PathType Leaf) { [string](Get-Content -LiteralPath $fontMarker -Raw -Encoding ASCII) } else { $null }
        XnbCount = $fontXnbFiles.Count
        TotalBytes = $fontTotalBytes
        BudgetBytes = 125829120
        FullCharacterCount = if ($null -ne $fontCharacterSets) { ([string]$fontCharacterSets.FullCharacters).Length } else { 0 }
        LargeUiCharacterCount = if ($null -ne $fontCharacterSets) { ([string]$fontCharacterSets.LargeUiCharacters).Length } else { 0 }
    }
    Artifacts = [ordered]@{
        UiDll = Test-Path -LiteralPath (Join-Path $PatchRoot "AtTheGatesUI.dll") -PathType Leaf
        CommonDll = Test-Path -LiteralPath (Join-Path $PatchRoot "AtTheGatesCommon.dll") -PathType Leaf
        GameExe = Test-Path -LiteralPath (Join-Path $PatchRoot "At The Gates.exe") -PathType Leaf
        ClanCardMetallurgyAlias = Test-Path -LiteralPath $metallurgyAliasPath -PathType Leaf
    }
    Timing = @($timingReportForJson)
}

$buildReportPath = Join-Path $PatchRoot ".atg-build-report.json"
$buildReport | ConvertTo-Json -Depth 6 -Compress | Set-Content -LiteralPath $buildReportPath -Encoding UTF8
Write-Host "Build report: $buildReportPath"

Write-Host "Build timing summary:"
Get-AtGTimingReport -Summary $timing | Format-Table -AutoSize
Write-Host "Patch build complete: $PatchRoot"
