param(
    [string]$PatchRoot = "$PSScriptRoot\..\patch"
)

$ErrorActionPreference = "Stop"

function Test-Utf16StringPresent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Needle
    )

    if (!(Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "File not found: $Path"
    }

    $bytes = [IO.File]::ReadAllBytes($Path)
    $needleBytes = [Text.Encoding]::Unicode.GetBytes($Needle)
    for ($i = 0; $i -le $bytes.Length - $needleBytes.Length; $i++) {
        if ($bytes[$i] -ne $needleBytes[0]) {
            continue
        }

        $matched = $true
        for ($j = 1; $j -lt $needleBytes.Length; $j++) {
            if ($bytes[$i + $j] -ne $needleBytes[$j]) {
                $matched = $false
                break
            }
        }

        if ($matched) {
            return $true
        }
    }

    return $false
}

function Test-PrintableUtf16CodeUnit {
    param(
        [byte[]]$Bytes,
        [int]$Index
    )

    if ($Index -lt 0 -or $Index -ge $Bytes.Length - 1) {
        return $false
    }

    $code = $Bytes[$Index] + ($Bytes[$Index + 1] -shl 8)
    return ($code -ge 32 -and $code -le 126) -or $code -eq 9 -or $code -eq 10 -or $code -eq 13
}

function Test-Utf16StandaloneStringPresent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Needle
    )

    if (!(Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "File not found: $Path"
    }

    $bytes = [IO.File]::ReadAllBytes($Path)
    $needleBytes = [Text.Encoding]::Unicode.GetBytes($Needle)
    for ($i = 0; $i -le $bytes.Length - $needleBytes.Length; $i++) {
        if ($bytes[$i] -ne $needleBytes[0]) {
            continue
        }

        $matched = $true
        for ($j = 1; $j -lt $needleBytes.Length; $j++) {
            if ($bytes[$i + $j] -ne $needleBytes[$j]) {
                $matched = $false
                break
            }
        }

        if (!$matched) {
            continue
        }

        if ((Test-PrintableUtf16CodeUnit -Bytes $bytes -Index ($i - 2)) -or
            (Test-PrintableUtf16CodeUnit -Bytes $bytes -Index ($i + $needleBytes.Length))) {
            continue
        }

        return $true
    }

    return $false
}

function Test-Utf16StringAtOffset {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [int]$Offset,

        [Parameter(Mandatory = $true)]
        [string]$Needle
    )

    if (!(Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "File not found: $Path"
    }

    $bytes = [IO.File]::ReadAllBytes($Path)
    $needleBytes = [Text.Encoding]::Unicode.GetBytes($Needle)
    if ($Offset -lt 0 -or $Offset + $needleBytes.Length -gt $bytes.Length) {
        throw "Offset $Offset is outside $Path"
    }

    for ($i = 0; $i -lt $needleBytes.Length; $i++) {
        if ($bytes[$Offset + $i] -ne $needleBytes[$i]) {
            return $false
        }
    }

    return $true
}

$ldstrValueCache = @{}
$ldstrRecordCache = @{}

function Get-LiveLdstrValues {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $resolved = (Resolve-Path -LiteralPath $Path).Path
    if ($ldstrValueCache.ContainsKey($resolved)) {
        return $ldstrValueCache[$resolved]
    }

    $exportScript = Join-Path $PSScriptRoot "Export-DllLdstrCatalog.ps1"
    if (!(Test-Path -LiteralPath $exportScript -PathType Leaf)) {
        $ldstrValueCache[$resolved] = $null
        return $null
    }

    $tempBase = [IO.Path]::Combine([IO.Path]::GetTempPath(), [IO.Path]::GetRandomFileName())
    $jsonPath = "$tempBase.json"
    $csvPath = "$tempBase.csv"
    try {
        & $exportScript -DllPath $resolved -OutputJson $jsonPath -OutputCsv $csvPath | Out-Null
        $records = @(Get-Content -LiteralPath $jsonPath -Raw -Encoding UTF8 | ConvertFrom-Json)
        $values = @($records | ForEach-Object { [string]$_.Value })
        $ldstrValueCache[$resolved] = $values
        return $values
    }
    catch {
        $ldstrValueCache[$resolved] = $null
        return $null
    }
    finally {
        Remove-Item -LiteralPath $jsonPath, $csvPath -Force -ErrorAction SilentlyContinue
    }
}

function Get-LiveLdstrRecords {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $resolved = (Resolve-Path -LiteralPath $Path).Path
    if ($ldstrRecordCache.ContainsKey($resolved)) {
        return $ldstrRecordCache[$resolved]
    }

    $exportScript = Join-Path $PSScriptRoot "Export-DllLdstrCatalog.ps1"
    if (!(Test-Path -LiteralPath $exportScript -PathType Leaf)) {
        $ldstrRecordCache[$resolved] = $null
        return $null
    }

    $tempBase = [IO.Path]::Combine([IO.Path]::GetTempPath(), [IO.Path]::GetRandomFileName())
    $jsonPath = "$tempBase.json"
    $csvPath = "$tempBase.csv"
    try {
        & $exportScript -DllPath $resolved -OutputJson $jsonPath -OutputCsv $csvPath | Out-Null
        $records = @(Get-Content -LiteralPath $jsonPath -Raw -Encoding UTF8 | ConvertFrom-Json)
        $ldstrRecordCache[$resolved] = $records
        return $records
    }
    catch {
        $ldstrRecordCache[$resolved] = $null
        return $null
    }
    finally {
        Remove-Item -LiteralPath $jsonPath, $csvPath -Force -ErrorAction SilentlyContinue
    }
}

function Test-LocalizedStringPresent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Needle
    )

    $values = Get-LiveLdstrValues -Path $Path
    if ($null -eq $values) {
        return Test-Utf16StringPresent -Path $Path -Needle $Needle
    }

    foreach ($value in $values) {
        if ($value.Contains($Needle)) {
            return $true
        }
    }

    return $false
}

function Test-LocalizedStandaloneStringPresent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Needle
    )

    $values = Get-LiveLdstrValues -Path $Path
    if ($null -eq $values) {
        return Test-Utf16StandaloneStringPresent -Path $Path -Needle $Needle
    }

    foreach ($value in $values) {
        if ($value -eq $Needle) {
            return $true
        }
    }

    return $false
}

function Test-OriginalLdstrEntryPresent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$MethodToken,

        [Parameter(Mandatory = $true)]
        [int]$ILOffset,

        [Parameter(Mandatory = $true)]
        [string]$Original,

        [string]$TypeFullName,

        [string]$MethodName
    )

    $records = Get-LiveLdstrRecords -Path $Path
    if ($null -eq $records) {
        return Test-LocalizedStringPresent -Path $Path -Needle $Original
    }

    foreach ($record in $records) {
        if ([string]$record.MethodToken -eq $MethodToken -and
            [int]$record.ILOffset -eq $ILOffset -and
            [string]$record.Value -eq $Original) {
            return $true
        }
    }

    if ($TypeFullName -or $MethodName) {
        foreach ($record in $records) {
            if ([int]$record.ILOffset -ne $ILOffset -or
                [string]$record.Value -ne $Original) {
                continue
            }

            if ($TypeFullName -and [string]$record.TypeFullName -ne $TypeFullName) {
                continue
            }

            if ($MethodName -and [string]$record.MethodName -ne $MethodName) {
                continue
            }

            return $true
        }

        return $false
    }

    foreach ($record in $records) {
        if ([int]$record.ILOffset -eq $ILOffset -and
            [string]$record.Value -eq $Original) {
            return $true
        }
    }

    return $false
}

$checks = @(
    @{
        Path = Join-Path $PatchRoot "AtTheGatesUI.dll"
        Strings = @(
            "Opens the Clan List, where you can reference information about all of your clans in a large grid.",
            "[HOTKEY:Esc] Open up the System Menu, where you can save the game, quit to the main menu, etc.",
            "This action can be performed by pressing ",
            "Click the Notification icon or ",
            "Click the Notification icon or press ",
            "Click the Notification icon to cycle through them.",
            "Click the Notification icon to center the camera on it.",
            "Press [HOTKEY:Spacebar] to go to the ",
            "Right-Click the Notification icon to dismiss it.",
            "Hotkey alternative to clicking this button or the Notification icon.",
            "Your growing [FAME] has convinced ",
            " to leave the wilderness and join your Tribe! They are ",
            " currently being ",
            " by clicking this button or the 'Clans' button in the upper-left corner of the screen, or by pressing [HOTKEY:Spacebar].",
            "Unless you're [Moving|MOVE-POINT] your [SETTLEMENT] it's generally a good idea to be Training someone whenever possible, especially during the first year.",
            "Costs ",
            " to enter",
            "next to [SETTLEMENT:NO-ICON]",
            "from [Terrain|TERRAIN]",
            " if entered",
            "Lose ",
            "NOTHING",
            "NOTHING ( Packed Up )",
            "You can view or select which ",
            " by clicking this button or pressing [HOTKEY:F1].",
            "You currently have ",
            "Your Tribe can [Support|POPCAP] up to ",
            "Can Identify ",
            "[HOTKEY:Spacebar] View, manage or ",
            " who make up your Tribe.",
            "When you can afford to do so, clicking this button will spend ",
            "Support Limit",
            "Settlement is Idle",
            "A Clan or your [SETTLEMENT] is idle.",
            "Click to see what",
            "Right-click to write a note to attach to this card."
        )
        LdstrEntries = @(
            @{ MethodToken = "0x06000376"; ILOffset = 112; Original = "Immobilized" },
            @{ MethodToken = "0x06000621"; ILOffset = 1571; Original = "Click this button to choose a " },
            @{ MethodToken = "0x06000621"; ILOffset = 1587; Original = " to " },
            @{ MethodToken = "0x06000621"; ILOffset = 1603; Original = " one of your " },
            @{ MethodToken = "0x06000621"; ILOffset = 1797; Original = "Instead of " },
            @{ MethodToken = "0x06000621"; ILOffset = 1845; Original = " you can spend the [Turn|TURN] switching a Clan to a different " },
            @{ MethodToken = "0x06000621"; ILOffset = 2015; Original = "Instead of " },
            @{ MethodToken = "0x06000621"; ILOffset = 2063; Original = " you can spend the [Turn|TURN] Training a Clan in a new " },
            @{ MethodToken = "0x06000621"; ILOffset = 2079; Original = " (for free), or Training up a Clan's " },
            @{ MethodToken = "0x06000621"; ILOffset = 2097; Original = " in their current Discipline (this costs [" },
            @{ MethodToken = "0x06000621"; ILOffset = 2497; Original = " per [Clan|CLAN] in your [SETTLEMENT]" },
            @{ MethodToken = "0x06000621"; ILOffset = 2511; Original = " this [Turn|TURN]." },
            @{ MethodToken = "0x06000621"; ILOffset = 2540; Original = "Performing this action means you won't be able to [Train|TRAIN] a [Clan|CLAN] in a [Profession|PROFESSION] or [Discipline|DISCIPLINE], and as such it should generally be avoided. Training Clans is important to developing your economy!" },
            @{ MethodToken = "0x06000125"; ILOffset = 122; Original = "Ennoble" },
            @{ MethodToken = "0x06000622"; ILOffset = 169; Original = "Click to choose a " },
            @{ MethodToken = "0x06000622"; ILOffset = 185; Original = " you'd like to " },
            @{ MethodToken = "0x06000622"; ILOffset = 421; Original = "You lack sufficient [" },
            @{ MethodToken = "0x06000622"; ILOffset = 460; Original = " more needed)." }
        )
        StandaloneStrings = @(
            "You can ",
            " to ",
            " one of your ",
            " a ",
            " in a new ",
            " a new ",
            " Clans.",
            " and raise your",
            " by +",
            "You have ",
            " in your Stockpile.",
            "Stockpile",
            " Stockpile is ",
            "increasing by ",
            "Once you reach ",
            " will join you!",
            " This will take ",
            " at the current pace.",
            " The next ",
            " will arrive ",
            " after that, ",
            "once you've reached ",
            " [Turns|TURN]."
        )
    },
    @{
        Path = Join-Path $PatchRoot "AtTheGatesCommon.dll"
        Strings = @(
            "Stockpile / Production / Consumption",
            "Profession:",
            "Click to see what [Professions|PROFESSION] [Clan|CLAN]",
            " can be [Trained|TRAIN] in.",
            "Right-click to write a note to attach to this card.",
            ":      NONE",
            ":    NONE",
            ": NONE",
            "[Resource|RESOURCE] production is a fundamental part of At the Gates.",
            "AtG is a turn-based game. Each turn, [Resources|RESOURCE] are [Produced|PRODUCE] and [Consumed|CONSUME]",
            "You can Study one [Tech|TECH]",
            "[铁匠|BLACKSMITH]",
            "[铁|IRON]",
            "[工具|TOOLS]"
        )
        LdstrEntries = @(
            @{ MethodToken = "0x06000118"; ILOffset = 2374; Original = "Starts in " },
            @{ MethodToken = "0x06000118"; ILOffset = 2528; Original = "Starts with " },
            @{ MethodToken = "0x06000118"; ILOffset = 2622; Original = " in " },
            @{ MethodToken = "0x06000118"; ILOffset = 2719; Original = " (will abandon " },
            @{ MethodToken = "0x06000118"; ILOffset = 2735; Original = " if in another " },
            @{ MethodToken = "0x06000118"; ILOffset = 2797; Original = " gained in " },
            @{ MethodToken = "0x06000118"; ILOffset = 8039; Original = " time for switching " },
            @{ MethodToken = "0x06000118"; ILOffset = 8154; Original = " when switching " },
            @{ MethodToken = "0x06000204"; ILOffset = 302; Original = "Might extremely rarely " },
            @{ MethodToken = "0x06000205"; ILOffset = 300; Original = "Likely to " },
            @{ MethodToken = "0x06000205"; ILOffset = 306; Original = " within a year" },
            @{ MethodToken = "0x06000205"; ILOffset = 411; Original = "Might very rarely " },
            @{ MethodToken = "0x06000205"; ILOffset = 425; Original = "Might extremely rarely " },
            @{ MethodToken = "0x060012f0"; ILOffset = 124; Original = "[Trained|TRAIN] as " },
            @{ MethodToken = "0x060012f0"; ILOffset = 436; Original = "get" },
            @{ MethodToken = "0x060012f0"; ILOffset = 461; Original = " extremely" },
            @{ MethodToken = "0x060012f0"; ILOffset = 488; Original = " very" },
            @{ MethodToken = "0x060012f0"; ILOffset = 515; Original = " quite" },
            @{ MethodToken = "0x060012f0"; ILOffset = 543; Original = " a little" },
            @{ MethodToken = "0x060012f0"; ILOffset = 558; Original = " upset" },
            @{ MethodToken = "0x060012f2"; ILOffset = 126; Original = "[Trained|TRAIN] as " },
            @{ MethodToken = "0x060012f2"; ILOffset = 565; Original = "engage in a" },
            @{ MethodToken = "0x060012f2"; ILOffset = 591; Original = " serious" },
            @{ MethodToken = "0x060012f2"; ILOffset = 619; Original = " major" },
            @{ MethodToken = "0x060012f2"; ILOffset = 647; Original = " disruptive" },
            @{ MethodToken = "0x060012f2"; ILOffset = 675; Original = " mild" },
            @{ MethodToken = "0x060012f2"; ILOffset = 690; Original = " [Feud|FEUD]" },
            @{ MethodToken = "0x060012f4"; ILOffset = 105; Original = "[Trained|TRAIN] as " },
            @{ MethodToken = "0x060012f4"; ILOffset = 353; Original = "Will never " },
            @{ MethodToken = "0x060012f4"; ILOffset = 382; Original = "Less likely " },
            @{ MethodToken = "0x060012f4"; ILOffset = 412; Original = " ([Crime|CRIME])" },
            @{ MethodToken = "0x06000220"; ILOffset = 720; Original = "[Ennoble]" },
            @{ MethodToken = "0x0600026a"; ILOffset = 500; Original = "[Ennoble|NOBLE]" },
            @{ MethodToken = "0x0600026a"; ILOffset = 510; Original = "[Ennobled|NOBLE]" }
        )
        StandaloneStrings = @(
            "[Profession]",
            "[Profession|PROFESSION]",
            "[Professions|PROFESSION]",
            "[Discipline]",
            "[Discipline|DISCIPLINE]",
            "[Disciplines|DISCIPLINE]",
            "[Family]",
            "[Families]",
            "[Family|FAMILY]",
            "[Families|FAMILY]",
            "[Production]",
            "[Production|PRODUCE]",
            "[Produce|PRODUCE]",
            "[Produces|PRODUCE]",
            "[Producing|PRODUCE]",
            "[Power|POWER]",
            "[Attack Power|ATTACK]",
            "[Deposit|DEPOSIT]",
            "[Deposits|DEPOSIT]",
            "[Unidentified Deposit|UNIDENTIFIED]",
            "[Unidentified Deposits|UNIDENTIFIED]",
            "[Plant|PLANT]",
            "[Mineral|MINERAL]",
            "[Animal|ANIMAL]",
            "[Animals|ANIMAL]",
            "[Train|TRAIN]",
            "[Trained|TRAIN]",
            "[Training|TRAIN]",
            "[Turn]",
            "[Turn|TURN]",
            "[Turns|TURN]",
            "[Study|STUDY]",
            "[Studying|STUDY]",
            "[Studied|STUDY]",
            "[Clan|CLAN]",
            "[Clans|CLAN]",
            "[Move Point]",
            "[Move Point|MOVE-POINT]",
            "[Move Points|MOVE-POINT]",
            "[Supply]",
            "[Supply|SUPPLY]",
            "[Defense|DEFENSE]",
            "[Defense Power|DEFENSE]",
            "[Terrain|TERRAIN]",
            "[Tile|TILE]",
            "[Structure]",
            "[Structure|STRUCTURE]",
            "[Structures|STRUCTURE]",
            "Cannot Fight",
            "Requires ",
            "a detailed breakdown of your Stockpile, Production, and Consumption of this Resource",
            "a detailed breakdown of why you cannot Construct this Structure",
            "a detailed breakdown of why you cannot ",
            "a detailed breakdown of what is required to ",
            "...plus advanced versions of similar ",
            " per turn"
        )
    },
    @{
        Path = Join-Path $PatchRoot "At The Gates.exe"
        MethodName = "PerformCheck"
        Strings = @()
        LdstrEntries = @(
            @{ MethodToken = "0x060013e5"; ILOffset = 164; Original = "You lack sufficient " },
            @{ MethodToken = "0x060013e5"; ILOffset = 182; Original = " (" },
            @{ MethodToken = "0x060013e5"; ILOffset = 203; Original = " more needed)." },
            @{ MethodToken = "0x060013e8"; ILOffset = 161; Original = "You lack sufficient " },
            @{ MethodToken = "0x060013e8"; ILOffset = 184; Original = " (" },
            @{ MethodToken = "0x060013e8"; ILOffset = 205; Original = " more needed)." },
            @{ MethodToken = "0x060013eb"; ILOffset = 102; Original = "You lack sufficient " },
            @{ MethodToken = "0x060013eb"; ILOffset = 124; Original = " (" },
            @{ MethodToken = "0x060013eb"; ILOffset = 145; Original = " more needed)." },
            @{ MethodToken = "0x060013ee"; ILOffset = 230; Original = "You lack sufficient " },
            @{ MethodToken = "0x060013ee"; ILOffset = 248; Original = " (need " },
            @{ MethodToken = "0x060013ee"; ILOffset = 269; Original = " more)." },
            @{ MethodToken = "0x060013f1"; ILOffset = 116; Original = "You lack sufficient " },
            @{ MethodToken = "0x060013f1"; ILOffset = 133; Original = " (" },
            @{ MethodToken = "0x060013f1"; ILOffset = 154; Original = " more needed)." },
            @{ MethodToken = "0x060013f4"; ILOffset = 116; Original = "You lack sufficient " },
            @{ MethodToken = "0x060013f4"; ILOffset = 133; Original = " (" },
            @{ MethodToken = "0x060013f4"; ILOffset = 154; Original = " more needed)." },
            @{ MethodToken = "0x060013f7"; ILOffset = 116; Original = "You lack sufficient " },
            @{ MethodToken = "0x060013f7"; ILOffset = 133; Original = " (" },
            @{ MethodToken = "0x060013f7"; ILOffset = 154; Original = " more needed)." },
            @{ MethodToken = "0x060013fa"; ILOffset = 111; Original = "You lack sufficient " },
            @{ MethodToken = "0x060013fa"; ILOffset = 128; Original = " (" },
            @{ MethodToken = "0x060013fa"; ILOffset = 149; Original = " more needed)." },
            @{ MethodToken = "0x060013fd"; ILOffset = 142; Original = "You lack sufficient " },
            @{ MethodToken = "0x060013fd"; ILOffset = 159; Original = " (" },
            @{ MethodToken = "0x060013fd"; ILOffset = 180; Original = " more needed)." }
        )
        StandaloneStrings = @()
    }
)

$offsetChecks = @(
    @{
        Path = Join-Path $PatchRoot "AtTheGatesUI.dll"
        Entries = @(
            @{ Offset = 488569; Original = " can be " },
            @{ Offset = 488587; Original = " in." }
        )
    }
)

$failures = New-Object System.Collections.Generic.List[string]
foreach ($check in $checks) {
    foreach ($needle in @($check.Strings)) {
        if (Test-LocalizedStringPresent -Path $check.Path -Needle $needle) {
            $failures.Add("$($check.Path): $needle")
        }
    }

    foreach ($needle in @($check.StandaloneStrings)) {
        if (Test-LocalizedStandaloneStringPresent -Path $check.Path -Needle $needle) {
            $failures.Add("$($check.Path): standalone $needle")
        }
    }

    foreach ($entry in @($check.LdstrEntries)) {
        $entryTypeFullName = [string]$entry.TypeFullName
        if (!$entryTypeFullName -and $null -ne $check.TypeFullName) {
            $entryTypeFullName = [string]$check.TypeFullName
        }

        $entryMethodName = [string]$entry.MethodName
        if (!$entryMethodName -and $null -ne $check.MethodName) {
            $entryMethodName = [string]$check.MethodName
        }

        if (Test-OriginalLdstrEntryPresent `
                -Path $check.Path `
                -MethodToken ([string]$entry.MethodToken) `
                -ILOffset ([int]$entry.ILOffset) `
                -Original ([string]$entry.Original) `
                -TypeFullName $entryTypeFullName `
                -MethodName $entryMethodName) {
            $failures.Add("$($check.Path): ldstr $($entry.MethodToken) @$($entry.ILOffset) $($entry.Original)")
        }
    }
}

foreach ($check in $offsetChecks) {
    foreach ($entry in @($check.Entries)) {
        if (Test-Utf16StringAtOffset -Path $check.Path -Offset ([int]$entry.Offset) -Needle ([string]$entry.Original)) {
            $failures.Add("$($check.Path): offset $($entry.Offset) $($entry.Original)")
        }
    }
}

if ($failures.Count -gt 0) {
    $message = "Unlocalized hover text remains:`n" + ($failures -join "`n")
    throw $message
}

Write-Host "Hover localization regression checks passed."
