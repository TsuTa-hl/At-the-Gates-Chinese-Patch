param(
    [Parameter(Mandatory = $true)]
    [string[]]$TracePath,
    [string[]]$ScenarioId,
    [string]$OutputPath = "$PSScriptRoot\..\translations\runtime-glyph-warmset.tsv"
)

$ErrorActionPreference = "Stop"

if ($null -ne $ScenarioId -and $ScenarioId.Count -ne $TracePath.Count) {
    throw "ScenarioId must contain exactly one value for every TracePath."
}

function ConvertTo-AtGBase64 {
    param([string]$Value)
    return [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Value))
}

function Test-AtGDynamicGlyph {
    param([char]$Character)
    $value = [int]$Character
    if (($value -ge 0x3000 -and $value -le 0x303F) -or
        ($value -in 0x2013, 0x2014, 0x2018, 0x2019, 0x201C, 0x201D, 0x2026)) {
        return $true
    }
    return ($value -ge 0x2E80 -and $value -le 0x9FFF) -or
        ($value -ge 0xF900 -and $value -le 0xFAFF) -or
        ($value -ge 0x3000 -and $value -le 0x303F) -or
        ($value -ge 0xFE10 -and $value -le 0xFE6F) -or
        ($value -ge 0xFF00 -and $value -le 0xFFEF) -or
        ($value -in 0x2013, 0x2014, 0x2018, 0x2019, 0x201C, 0x201D, 0x2026)
}

function Get-AtGWarmPriority {
    param([string]$Scenario)
    # Queue priority zero is reserved for live misses.  The startup menu has a
    # small trace-observed subset promoted below; the remaining load flow must
    # not crowd those glyphs out of the bounded prepared queue before Draw 1.
    if ($Scenario -eq "load-save-main-loop-tile-tooltip-20260702") { return 1 }
    if ($Scenario -in @(
        "knowledge-screen-hovers",
        "clan-list-header-hover-20260710",
        "clan-screen-buttons",
        "religion-screen-20260718"
    )) { return 2 }
    return 3
}

# These strings are the trace-observed first main-menu display, not a general
# character universe.  Promote only their dynamic glyphs so the worker fills
# the 256-item prepared cache with what Draw 1 can actually use.  The ordinary
# scenario traces still supply every operand and descriptor below.
$startupGlyphTexts = @(
    [pscustomobject]@{
        FontName = "SegoeUI_15_Bold"
        Size = 15.0
        Bold = $true
        Text = -join ([char[]](
            0x65B0, 0x6E38, 0x620F, 0x8BFB, 0x53D6, 0x5B58, 0x6863,
            0x9009, 0x9879, 0x5236, 0x4F5C, 0x7EC4, 0x9000, 0x51FA,
            0x751F, 0x5B58, 0x6218, 0x7565, 0x6E38, 0x620F, 0x6E38,
            0x73A9, 0x6559, 0x7A0B, 0x5730, 0x56FE, 0x6E38, 0x73A9,
            0x6BCF, 0x5468, 0x6311, 0x6218, 0x5BFB, 0x5B9D, 0x6E38,
            0x73A9, 0x6B27, 0x6D32, 0x5730, 0x56FE
        ))
        <#
        Text = "新游戏读取存档选项制作组退出生存战略游戏游玩教程地图游玩每周挑战寻宝游玩欧洲地图"
    }
        #>
    }
)

$observed = @{}
for ($traceIndex = 0; $traceIndex -lt $TracePath.Count; $traceIndex++) {
    $resolvedTrace = (Resolve-Path -LiteralPath $TracePath[$traceIndex]).Path
    $scenario = if ($null -ne $ScenarioId) {
        [string]$ScenarioId[$traceIndex]
    } else {
        [IO.Path]::GetFileNameWithoutExtension($resolvedTrace)
    }
    if ([string]::IsNullOrWhiteSpace($scenario) -or $scenario.Contains("`t") -or $scenario.Contains(",")) {
        throw "Scenario IDs must be non-empty and cannot contain tabs or commas: '$scenario'."
    }
    $priority = Get-AtGWarmPriority -Scenario $scenario

    foreach ($line in [IO.File]::ReadLines($resolvedTrace, [Text.Encoding]::UTF8)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $entry = $line | ConvertFrom-Json }
        catch { throw "Invalid runtime trace JSON in '$resolvedTrace': $($_.Exception.Message)" }
        $font = [string]$entry.font
        $text = [string]$entry.text
        if ([string]::IsNullOrEmpty($font) -or [string]::IsNullOrEmpty($text)) { continue }
        $fontParts = $font.Split("|")
        if ($fontParts.Count -lt 4) { continue }
        $fontName = $fontParts[0]
        $size = 0.0
        if (![double]::TryParse(
            $fontParts[1],
            [Globalization.NumberStyles]::Float,
            [Globalization.CultureInfo]::InvariantCulture,
            [ref]$size
        )) { continue }
        $bold = $false
        if (![bool]::TryParse($fontParts[2], [ref]$bold)) { continue }

        foreach ($character in $text.ToCharArray()) {
            if (!(Test-AtGDynamicGlyph -Character $character)) { continue }
            $characterKey = "{0}|{1}|{2}|{3:X4}" -f
                $fontName,
                $size.ToString("0.###", [Globalization.CultureInfo]::InvariantCulture),
                $bold,
                [int]$character
            if (!$observed.ContainsKey($characterKey)) {
                $observed[$characterKey] = [pscustomobject]@{
                    FontName = $fontName
                    Size = $size
                    Bold = $bold
                    Character = $character
                    Priority = $priority
                    Scenarios = [Collections.Generic.SortedSet[string]]::new(
                        [StringComparer]::Ordinal
                    )
                }
            }
            $record = $observed[$characterKey]
            if ($priority -lt $record.Priority) { $record.Priority = $priority }
            [void]$record.Scenarios.Add($scenario)
        }
    }
}

foreach ($startup in $startupGlyphTexts) {
    foreach ($character in $startup.Text.ToCharArray()) {
        if (!(Test-AtGDynamicGlyph -Character $character)) { continue }
        $characterKey = "{0}|{1}|{2}|{3:X4}" -f
            $startup.FontName,
            $startup.Size.ToString("0.###", [Globalization.CultureInfo]::InvariantCulture),
            $startup.Bold,
            [int]$character
        if ($observed.ContainsKey($characterKey)) {
            $observed[$characterKey].Priority = 0
        }
    }
}

$unsortedGroups = @($observed.Values |
    Group-Object {
        "{0}|{1}|{2}|{3}" -f
            $_.Priority,
            $_.FontName,
            $_.Size.ToString("0.###", [Globalization.CultureInfo]::InvariantCulture),
            $_.Bold
    } |
    ForEach-Object {
        $first = $_.Group[0]
        $characters = [string]::Join("", @(
            $_.Group |
                Sort-Object { [int]$_.Character } |
                ForEach-Object { [string]$_.Character }
        ))
        $scenarios = [Collections.Generic.SortedSet[string]]::new([StringComparer]::Ordinal)
        foreach ($record in $_.Group) {
            foreach ($scenario in $record.Scenarios) { [void]$scenarios.Add($scenario) }
        }
        [pscustomobject]@{
            Priority = [int]$first.Priority
            FontName = [string]$first.FontName
            Size = [double]$first.Size
            Bold = [bool]$first.Bold
            Characters = $characters
            Scenarios = [string]::Join(",", $scenarios)
            SortKey = "{0}|{1}|{2}|{3}" -f
                [int]$first.Priority,
                [string]$first.FontName,
                ([double]$first.Size).ToString(
                    "0.###", [Globalization.CultureInfo]::InvariantCulture),
                $(if ([bool]$first.Bold) { "1" } else { "0" })
        }
    })

$groups = [Collections.Generic.List[object]]::new()
foreach ($group in $unsortedGroups) { $groups.Add($group) }
$ordinalComparison = [Comparison[object]]{
    param($left, $right)
    [StringComparer]::Ordinal.Compare(
        [string]$left.SortKey,
        [string]$right.SortKey)
}
$groups.Sort($ordinalComparison)

$lines = [Collections.Generic.List[string]]::new()
$lines.Add("# AtG.RuntimeGlyphWarmset v1")
foreach ($group in $groups) {
    $lines.Add([string]::Join("`t", @(
        "W",
        $group.Priority.ToString([Globalization.CultureInfo]::InvariantCulture),
        (ConvertTo-AtGBase64 -Value $group.FontName),
        $group.Size.ToString("0.###", [Globalization.CultureInfo]::InvariantCulture),
        $(if ($group.Bold) { "1" } else { "0" }),
        (ConvertTo-AtGBase64 -Value $group.Characters),
        $group.Scenarios
    )))
}

$resolvedOutput = [IO.Path]::GetFullPath($OutputPath)
[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($resolvedOutput)) | Out-Null
[IO.File]::WriteAllLines($resolvedOutput, $lines, [Text.UTF8Encoding]::new($false))

[pscustomobject]@{
    OutputPath = $resolvedOutput
    Version = 1
    EntryCount = $groups.Count
    PairCount = $observed.Count
    ScenarioCount = $TracePath.Count
}
