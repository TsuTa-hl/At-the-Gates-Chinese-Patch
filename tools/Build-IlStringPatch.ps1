param(
    [Parameter(Mandatory = $true)]
    [string]$SourceDll,

    [Parameter(Mandatory = $true)]
    [string]$OutputDll,

    [Parameter(Mandatory = $true)]
    [string]$MapJson,

    [string[]]$SkipSourceStrings = @()
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\AtGManagedMetadata.ps1"

function Convert-AtGToken {
    param([object]$Value)

    if ($null -eq $Value) {
        return 0
    }

    $text = ([string]$Value).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) {
        return 0
    }

    if ($text.StartsWith("0x", [System.StringComparison]::OrdinalIgnoreCase)) {
        return [Convert]::ToInt32($text.Substring(2), 16)
    }

    return [int]$text
}

function ConvertTo-AtGIlPatchEntries {
    param([object]$Json)

    $entries = @()
    foreach ($item in @($Json)) {
        if ($null -eq $item) {
            continue
        }

        if ($null -ne $item.PSObject.Properties["Original"]) {
            $entries += $item
            continue
        }

        foreach ($property in $item.PSObject.Properties) {
            $entries += [pscustomobject]@{
                Original = [string]$property.Name
                Translation = [string]$property.Value
            }
        }
    }

    return $entries
}

if (!(Test-Path -LiteralPath $SourceDll -PathType Leaf)) {
    throw "Source DLL not found: $SourceDll"
}
if (!(Test-Path -LiteralPath $MapJson -PathType Leaf)) {
    throw "IL string map not found: $MapJson"
}

$json = Get-Content -LiteralPath $MapJson -Raw -Encoding UTF8 | ConvertFrom-Json
$entries = ConvertTo-AtGIlPatchEntries -Json $json
$skip = @{}
foreach ($sourceToSkip in @($SkipSourceStrings)) {
    if (![string]::IsNullOrWhiteSpace($sourceToSkip)) {
        $skip[[string]$sourceToSkip] = $true
    }
}
if ($entries.Count -eq 0) {
    $outDir = Split-Path -Parent $OutputDll
    if ($outDir) {
        New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    }
    Copy-Item -LiteralPath $SourceDll -Destination $OutputDll -Force
    Write-Host "No IL string entries found. Copied source DLL unchanged: $OutputDll"
    return
}

$specs = New-Object "System.Collections.Generic.List[AtG.PatchSpec]"
foreach ($entry in @($entries)) {
    $original = [string]$entry.Original
    $translation = [string]$entry.Translation
    if ([string]::IsNullOrWhiteSpace($original)) {
        continue
    }
    if ($skip.ContainsKey($original)) {
        Write-Host "Skipping '$original'; covered by another patch path."
        continue
    }

    $spec = New-Object AtG.PatchSpec
    $spec.Original = $original
    $spec.Translation = $translation
    if ($null -ne $entry.PSObject.Properties["MethodToken"]) {
        $spec.MethodToken = Convert-AtGToken $entry.MethodToken
    }
    if ($null -ne $entry.PSObject.Properties["StringToken"]) {
        $spec.StringToken = Convert-AtGToken $entry.StringToken
    }
    if ($null -ne $entry.PSObject.Properties["TypeFullName"]) {
        $spec.TypeFullName = [string]$entry.TypeFullName
    }
    if ($null -ne $entry.PSObject.Properties["MethodName"]) {
        $spec.MethodName = [string]$entry.MethodName
    }
    if ($null -ne $entry.PSObject.Properties["Optional"]) {
        $spec.Optional = [bool]$entry.Optional
    }
    $specs.Add($spec) | Out-Null
}

$specArray = [Array]::CreateInstance([AtG.PatchSpec], $specs.Count)
for ($i = 0; $i -lt $specs.Count; $i++) {
    $specArray[$i] = $specs[$i]
}

$results = [AtG.ManagedMetadataReader]::PatchLdstr(
    (Resolve-Path -LiteralPath $SourceDll).Path,
    $OutputDll,
    $specArray
)

foreach ($result in @($results)) {
    Write-Host "IL patched '$($result.Original)' -> '$($result.Translation)' ($($result.MatchCount) ldstr occurrence(s), $($result.HeapPatchCount) heap entrie(s))."
}
Write-Host "Built IL string patch: $OutputDll"
