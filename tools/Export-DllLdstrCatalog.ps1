param(
    [Parameter(Mandatory = $true)]
    [string]$DllPath,

    [string]$OutputJson = "$PSScriptRoot\..\.tmp\dll-ldstr-catalog.json",
    [string]$OutputCsv = "$PSScriptRoot\..\.tmp\dll-ldstr-catalog.csv",

    [string[]]$KnownMapJson = @(
        "$PSScriptRoot\..\translations\hardcoded-strings.json",
        "$PSScriptRoot\..\translations\hardcoded-common-strings.json",
        "$PSScriptRoot\..\translations\hardcoded-ui-il-rewrite.json",
        "$PSScriptRoot\..\translations\hardcoded-ui-il-strings.json"
    )
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\AtGManagedMetadata.ps1"

function Get-AtGKnownStringSet {
    param([string[]]$Path)

    $set = @{}
    foreach ($mapPath in @($Path)) {
        if (!(Test-Path -LiteralPath $mapPath)) {
            continue
        }

        $json = Get-Content -LiteralPath $mapPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -eq $json) {
            continue
        }

        foreach ($item in @($json)) {
            if ($null -ne $item.PSObject.Properties["Original"]) {
                $set[[string]$item.Original] = $true
                continue
            }

            foreach ($property in $item.PSObject.Properties) {
                $set[[string]$property.Name] = $true
            }
        }
    }
    return $set
}

function Get-AtGStringClass {
    param(
        [string]$AssemblyName,
        [string]$TypeFullName,
        [string]$MethodName,
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return "Technical"
    }

    if ($Value -match "^[A-Z]:\\|^\\\\|https?://|\.xml$|\.xnb$|\.dll$|\.AtGLog$" -or
        $Value -match "^\[HOTKEY:" -or
        $Value -match "^[A-Z0-9_+\-]{2,}$") {
        return "Technical"
    }

    if ($AssemblyName -match "Common" -and
        ($Value -match "^\[?(Turn|Turns|Learn|Stud(y|ying)|Clan|Faction|Season|Year)" -or
         $Value -match "Cannot Learn Right Now|Early | AD$")) {
        return "LogicSensitive"
    }

    if ($Value -match "Click|Right-click|Hover|button|Notification|Tooltip|HOTKEY|Press " -or
        $Value -match "\[[^\]]+\]") {
        return "TooltipFragment"
    }

    if ($AssemblyName -match "UI") {
        return "SafeUI"
    }

    if ($AssemblyName -match "Common") {
        return "CommonDisplayCandidate"
    }

    return "Review"
}

if (!(Test-Path -LiteralPath $DllPath -PathType Leaf)) {
    throw "DLL not found: $DllPath"
}

$resolvedDll = (Resolve-Path -LiteralPath $DllPath).Path
$known = Get-AtGKnownStringSet -Path $KnownMapJson
$records = [AtG.ManagedMetadataReader]::GetLdstrRecords($resolvedDll)

$output = foreach ($record in @($records)) {
    [pscustomobject]@{
        AssemblyName = $record.AssemblyName
        DllPath = $record.DllPath
        TypeFullName = $record.TypeFullName
        MethodName = $record.MethodName
        MethodToken = ("0x{0:x8}" -f $record.MethodToken)
        StringToken = ("0x{0:x8}" -f $record.StringToken)
        ILOffset = $record.ILOffset
        UserStringHeapOffset = $record.UserStringHeapOffset
        UserStringEntryBytes = $record.UserStringEntryBytes
        Value = $record.Value
        Length = $record.Length
        Class = Get-AtGStringClass -AssemblyName $record.AssemblyName -TypeFullName $record.TypeFullName -MethodName $record.MethodName -Value $record.Value
        AlreadyMapped = [bool]$known[[string]$record.Value]
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
[System.IO.File]::WriteAllText((Resolve-Path -LiteralPath $jsonDir).Path + "\" + [System.IO.Path]::GetFileName($OutputJson), ($output | ConvertTo-Json -Depth 5), $utf8NoBom)
$output | Export-Csv -LiteralPath $OutputCsv -Encoding UTF8 -NoTypeInformation

$summary = $output | Group-Object Class | Sort-Object Name | ForEach-Object {
    [pscustomobject]@{ Class = $_.Name; Count = $_.Count }
}

Write-Host "Exported $($output.Count) ldstr record(s)."
Write-Host "JSON: $OutputJson"
Write-Host "CSV:  $OutputCsv"
$summary | Format-Table -AutoSize
