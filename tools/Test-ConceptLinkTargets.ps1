param(
    [string]$CommonDllPath = "$PSScriptRoot\..\source\AtTheGatesCommon.original.dll",

    [string[]]$MapPaths = @(
        "$PSScriptRoot\..\translations\hardcoded-ui-il-rewrite.json",
        "$PSScriptRoot\..\translations\hardcoded-common-il-rewrite.json",
        "$PSScriptRoot\..\translations\hardcoded-game-il-rewrite.json",
        "$PSScriptRoot\..\translations\hardcoded-elftools-il-rewrite.json",
        "$PSScriptRoot\..\translations\hardcoded-strings.json",
        "$PSScriptRoot\..\translations\hardcoded-common-strings.json",
        "$PSScriptRoot\..\translations\hardcoded-ui-il-strings.json"
    )
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\AtGManagedMetadata.ps1"

function Normalize-ConceptDisplay([string]$Display) {
    $normalized = $Display.ToLowerInvariant() -replace "[^a-z]", ""
    if ($normalized.EndsWith("ies") -and $normalized.Length -gt 3) {
        return $normalized.Substring(0, $normalized.Length - 3) + "y"
    }
    if ($normalized.EndsWith("s") -and $normalized.Length -gt 1) {
        return $normalized.Substring(0, $normalized.Length - 1)
    }
    return $normalized
}

function Get-ConceptLinks([string]$Text) {
    $links = New-Object System.Collections.Generic.List[object]
    foreach ($match in [regex]::Matches($Text, "\[([^\]|]+)\|([^\]]+)\]")) {
        $links.Add([pscustomobject]@{
            Display = $match.Groups[1].Value
            Key = $match.Groups[2].Value
            Tag = $match.Value
        }) | Out-Null
    }
    return $links.ToArray()
}

if (!(Test-Path -LiteralPath $CommonDllPath -PathType Leaf)) {
    throw "Common DLL not found: $CommonDllPath"
}

$conceptLinks = @{}
$validKeys = @{}
$records = [AtG.ManagedMetadataReader]::GetLdstrRecords((Resolve-Path -LiteralPath $CommonDllPath).Path)
foreach ($record in $records) {
    if ($record.TypeFullName -ne "AtTheGatesCommon.ns_UI.Concepts" -or $record.MethodName -ne ".cctor") {
        continue
    }

    foreach ($link in Get-ConceptLinks ([string]$record.Value)) {
        $validKeys[$link.Key] = $true
        $displayKey = Normalize-ConceptDisplay $link.Display
        if ($displayKey -and !$conceptLinks.ContainsKey($displayKey)) {
            $conceptLinks[$displayKey] = $link.Key
        }
    }

    $value = [string]$record.Value
    if ($value -match "^[A-Z][A-Z0-9-]{1,}$") {
        $validKeys[$value] = $true
    }
}

if ($validKeys.Count -eq 0) {
    throw "No concept links were discovered from $CommonDllPath"
}

function Get-ExpectedConceptKey([string]$Display, [string]$OriginalKey) {
    if ($validKeys.ContainsKey($OriginalKey)) {
        return $OriginalKey
    }

    $displayKey = Normalize-ConceptDisplay $Display
    if ($displayKey -and $conceptLinks.ContainsKey($displayKey)) {
        return [string]$conceptLinks[$displayKey]
    }
    return $null
}

$errors = New-Object System.Collections.Generic.List[string]
$checked = 0

foreach ($mapPath in $MapPaths) {
    if (!(Test-Path -LiteralPath $mapPath)) {
        throw "Translation map not found: $mapPath"
    }

    [object[]]$entries = Get-Content -LiteralPath $mapPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($entry in $entries) {
        if ($null -eq $entry.PSObject.Properties["Original"] -or $null -eq $entry.PSObject.Properties["Translation"]) {
            continue
        }

        $originalLinks = @(Get-ConceptLinks ([string]$entry.Original))
        $translationLinks = @(Get-ConceptLinks ([string]$entry.Translation))
        if ($originalLinks.Count -eq 0) {
            continue
        }

        $checked++
        $expectedKeys = @($originalLinks | ForEach-Object { Get-ExpectedConceptKey $_.Display $_.Key } | Where-Object { $_ } | Sort-Object)
        $actualKeys = @($translationLinks | ForEach-Object { [string]$_.Key } | Sort-Object)
        $invalidActual = @($actualKeys | Where-Object { !$validKeys.ContainsKey($_) })
        if (($expectedKeys -join [char]31) -eq ($actualKeys -join [char]31) -and $invalidActual.Count -eq 0) {
            continue
        }

        $location = @()
        if ($entry.PSObject.Properties["TypeFullName"]) { $location += [string]$entry.TypeFullName }
        if ($entry.PSObject.Properties["MethodToken"]) { $location += [string]$entry.MethodToken }
        if ($entry.PSObject.Properties["ILOffset"]) { $location += "IL_$($entry.ILOffset)" }
        $errors.Add("$(Split-Path -Leaf $mapPath) :: $($location -join ' / ') :: expected '$($expectedKeys -join ',')', found '$($actualKeys -join ',')' :: '$($entry.Original)' -> '$($entry.Translation)'") | Out-Null
    }
}

if ($errors.Count -gt 0) {
    $errors | Select-Object -First 80 | ForEach-Object { Write-Warning $_ }
    if ($errors.Count -gt 80) {
        Write-Warning "... plus $($errors.Count - 80) more invalid concept-link target(s)."
    }
    throw "Concept-link target validation failed with $($errors.Count) invalid target(s) across $checked translation entries."
}

Write-Host "Concept-link target validation passed for $checked tagged translation entries using $($validKeys.Count) concept keys."
