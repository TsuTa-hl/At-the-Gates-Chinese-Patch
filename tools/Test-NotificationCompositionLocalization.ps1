param(
    [string]$SourceAssemblyPath = "$PSScriptRoot\..\source\AtTheGatesUI.original.dll",
    [string]$PatchAssemblyPath = "$PSScriptRoot\..\patch\AtTheGatesUI.dll",
    [string]$MapPath = "$PSScriptRoot\..\translations\hardcoded-ui-il-rewrite.json"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$cli = Join-Path $repoRoot "tools\Invoke-AtGPatchCli.ps1"
foreach ($path in @($SourceAssemblyPath, $PatchAssemblyPath, $MapPath, $cli)) {
    if (!(Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Notification composition validation input is missing: $path"
    }
}

function Get-LdstrEntries {
    param([Parameter(Mandatory = $true)][string]$AssemblyPath)

    return (& $cli -Command ldstr -CommandArguments @("--assembly", $AssemblyPath) | ConvertFrom-Json)
}

function Get-EntryKey {
    param([Parameter(Mandatory = $true)]$Entry)

    return "{0}:{1}" -f $Entry.MethodToken, [int]$Entry.IlOffset
}

$sourceEntries = Get-LdstrEntries -AssemblyPath $SourceAssemblyPath
$patchEntries = Get-LdstrEntries -AssemblyPath $PatchAssemblyPath
$rewriteMap = Get-Content -LiteralPath $MapPath -Raw -Encoding UTF8 | ConvertFrom-Json

$mapByKey = @{}
foreach ($entry in $rewriteMap) {
    $key = Get-EntryKey -Entry $entry
    if ($mapByKey.ContainsKey($key)) {
        throw "Notification composition validation found a duplicate rewrite locator: $key"
    }
    $mapByKey[$key] = $entry
}

# The audit scope is every literal that participates in a visible notification
# summary, detail, or season/weather label.  The exclusions below are source
# identifiers, comparisons, placeholders, or diagnostics; rewriting those
# would alter behavior rather than localize player-facing text.
$displayMethods = @{
    "AtTheGatesUI.ns_Notifications.Notification" = @("BuildText_Summary", "AppendDetails")
    "AtTheGatesUI.ns_Notifications.NotificationtMgr" = @("CheckFor_Weather")
}
$nonDisplayKeys = [System.Collections.Generic.HashSet[string]]::new([string[]]@(
    "0x0600002d:1344", # INTENSITY_OBSESSED comparison key
    "0x0600002d:1471", # INTENSITY_OBSESSED comparison key
    "0x0600002d:1671", # Happy comparison key
    "0x0600002d:3515", # unsupported-notification diagnostic
    "0x0600002f:1710", # runtime (NAME) placeholder
    "0x0600002f:1730", # runtime (INTENSITY) placeholder
    "0x0600002f:1818", # runtime (NAME) placeholder
    "0x0600002f:1838", # runtime (NAME2) placeholder
    "0x0600002f:1859", # runtime (FEUD-DESC) placeholder
    "0x0600002f:2378", # runtime (NAME) placeholder
    "0x0600002f:4589"  # unsupported-notification diagnostic
))

$visibleEnglish = @($sourceEntries | Where-Object {
    $methods = $displayMethods[$_.TypeFullName]
    $null -ne $methods -and $_.MethodName -in $methods -and $_.Value -match "[A-Za-z]{2,}"
})
$unmapped = @($visibleEnglish | Where-Object {
    $key = Get-EntryKey -Entry $_
    !$nonDisplayKeys.Contains($key) -and !$mapByKey.ContainsKey($key)
})
if ($unmapped.Count -gt 0) {
    $descriptions = $unmapped | ForEach-Object {
        "{0} {1} IL_{2:X4}: {3}" -f $_.TypeFullName, $_.MethodName, [int]$_.IlOffset, $_.Value
    }
    $unmappedText = [string]::Join([Environment]::NewLine, [string[]]$descriptions)
    throw "Notification composition audit found unmapped player-visible English literals:`n$unmappedText"
}

$expected = @(
    [pscustomobject]@{ MethodToken = "0x0600002d"; IlOffset = 2157; Original = " has " };
    [pscustomobject]@{ MethodToken = "0x0600002d"; IlOffset = 2186; Original = " has " };
    [pscustomobject]@{ MethodToken = "0x0600002d"; IlOffset = 2596; Original = "[DEPOSIT-" };
    [pscustomobject]@{ MethodToken = "0x0600002d"; IlOffset = 2623; Original = ":A/AN]" };
    [pscustomobject]@{ MethodToken = "0x0600002d"; IlOffset = 2721; Original = "[DEPOSIT-" };
    [pscustomobject]@{ MethodToken = "0x0600002d"; IlOffset = 2737; Original = ":A/AN]" };
    [pscustomobject]@{ MethodToken = "0x0600002d"; IlOffset = 2889; Original = "[DEPOSIT-" };
    [pscustomobject]@{ MethodToken = "0x0600002d"; IlOffset = 2905; Original = ":A/AN]" };
    [pscustomobject]@{ MethodToken = "0x0600002f"; IlOffset = 3576; Original = ":A/AN]" };
    [pscustomobject]@{ MethodToken = "0x0600002f"; IlOffset = 3820; Original = "[DEPOSIT-" };
    [pscustomobject]@{ MethodToken = "0x0600002f"; IlOffset = 3836; Original = ":A/AN]" };
    [pscustomobject]@{ MethodToken = "0x0600002f"; IlOffset = 4026; Original = "[DEPOSIT-" };
    [pscustomobject]@{ MethodToken = "0x0600002f"; IlOffset = 4042; Original = ":A/AN]" };
    [pscustomobject]@{ MethodToken = "0x0600002f"; IlOffset = 4321; Original = "Summer" };
    [pscustomobject]@{ MethodToken = "0x0600002f"; IlOffset = 4363; Original = "Winter" };
    [pscustomobject]@{ MethodToken = "0x06000073"; IlOffset = 245; Original = "Scalding" };
    [pscustomobject]@{ MethodToken = "0x06000073"; IlOffset = 259; Original = "Hot" };
    [pscustomobject]@{ MethodToken = "0x06000073"; IlOffset = 273; Original = "Cool" };
    [pscustomobject]@{ MethodToken = "0x06000073"; IlOffset = 287; Original = "Mild" };
    [pscustomobject]@{ MethodToken = "0x06000073"; IlOffset = 367; Original = "Bone-Dry" };
    [pscustomobject]@{ MethodToken = "0x06000073"; IlOffset = 381; Original = "Dry" };
    [pscustomobject]@{ MethodToken = "0x06000073"; IlOffset = 395; Original = "Soggy" };
    [pscustomobject]@{ MethodToken = "0x06000073"; IlOffset = 409; Original = "Wet" };
    [pscustomobject]@{ MethodToken = "0x06000073"; IlOffset = 560; Original = "Balmy" };
    [pscustomobject]@{ MethodToken = "0x06000073"; IlOffset = 574; Original = "Warm" };
    [pscustomobject]@{ MethodToken = "0x06000073"; IlOffset = 588; Original = "Frigid" };
    [pscustomobject]@{ MethodToken = "0x06000073"; IlOffset = 602; Original = "Chilly" };
    [pscustomobject]@{ MethodToken = "0x06000073"; IlOffset = 682; Original = "Bone-Dry" };
    [pscustomobject]@{ MethodToken = "0x06000073"; IlOffset = 696; Original = "Dry" };
    [pscustomobject]@{ MethodToken = "0x06000073"; IlOffset = 710; Original = "Stormy" };
    [pscustomobject]@{ MethodToken = "0x06000073"; IlOffset = 724; Original = "Wet" }
)

foreach ($item in $expected) {
    $key = Get-EntryKey -Entry $item
    $sourceEntry = @($sourceEntries | Where-Object {
        $_.MethodToken -eq $item.MethodToken -and [int]$_.IlOffset -eq $item.IlOffset -and $_.Value -eq $item.Original
    })
    if ($sourceEntry.Count -ne 1) {
        throw "Notification composition source locator drifted or is ambiguous: $key '$($item.Original)'"
    }
    if (!$mapByKey.ContainsKey($key) -or $mapByKey[$key].Original -ne $item.Original) {
        throw "Notification composition mapping is missing or incorrect at $key '$($item.Original)'"
    }
    $translation = [string]$mapByKey[$key].Translation
    if ([string]::IsNullOrWhiteSpace($translation) -or $translation -eq $item.Original) {
        throw "Notification composition mapping did not localize $key '$($item.Original)'"
    }
    $patchedEntry = @($patchEntries | Where-Object {
        $_.MethodToken -eq $item.MethodToken -and [int]$_.IlOffset -eq $item.IlOffset -and $_.Value -eq $translation
    })
    if ($patchedEntry.Count -ne 1) {
        throw "Patched notification composition literal is missing at $key '$translation'"
    }
}

Write-Host "Notification composition localization passed: $($expected.Count) exact display rewrites; $($visibleEnglish.Count) English source literals audited."
