param(
    [string]$AssemblyPath = "$PSScriptRoot\..\patch\AtTheGatesCommon.dll",
    [string]$SourceAssemblyPath = "$PSScriptRoot\..\source\AtTheGatesCommon.original.dll",
    [string]$ConceptMapPath = "$PSScriptRoot\..\translations\concept-key-translations.json",
    [string]$PatchTextPath = "$PSScriptRoot\..\patch\Content\Text\English.xml"
)

$ErrorActionPreference = "Stop"

function Get-ConceptTooltipCatalog {
    param([Parameter(Mandatory)][string]$Path)

    $report = Join-Path $repoRoot ".tmp\concept-tooltip-catalog-$([guid]::NewGuid().ToString('N')).json"
    try {
        & $cli -Command concept-tooltips -CommandArguments @("--assembly", $Path, "--output", $report) | Out-Null
        if (!(Test-Path -LiteralPath $report -PathType Leaf)) {
            throw "Concept tooltip catalog was not written: $report"
        }
        return Get-Content -LiteralPath $report -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    finally {
        Remove-Item -LiteralPath $report -Force -ErrorAction SilentlyContinue
    }
}

function Assert-RegistrationInventory {
    param(
        [Parameter(Mandatory)]$Catalog,
        [Parameter(Mandatory)][string]$Role
    )

    if ($Catalog.TypeFullName -ne "AtTheGatesCommon.ns_UI.Concepts" -or
        $Catalog.StaticConstructorToken -ne "0x0600026a") {
        throw "$Role catalog did not resolve the Concepts static registration entry point."
    }
    $entries = @($Catalog.Entries)
    if ($entries.Count -ne 111) {
        throw "$Role catalog expected 111 concept tooltip registrations, found $($entries.Count)."
    }
    if (($entries.Key | Sort-Object -Unique).Count -ne $entries.Count) {
        throw "$Role catalog has duplicate concept tooltip keys."
    }
    $incomplete = @($entries | Where-Object { -not $_.IsComplete })
    if ($incomplete.Count -gt 0) {
        throw "$Role catalog has incomplete registrations: $($incomplete.Key -join ', ')."
    }
}

function Get-VisibleConceptText {
    param([AllowNull()][string]$Text)

    if ($null -eq $Text) { return "" }
    $visible = $Text
    # Concept links and built-in rich-text tags are labels generated elsewhere;
    # their text is validated by concept-key map and rich-text tests. This gate
    # checks the literal prose owned by Concepts::.cctor.
    $visible = [regex]::Replace($visible, "\[[^\]]+\]", "")
    $visible = [regex]::Replace($visible, "\{font-icon:[^}]+\}", "")
    return $visible
}

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$cli = Join-Path $repoRoot "tools\Invoke-AtGPatchCli.ps1"
$AssemblyPath = (Resolve-Path -LiteralPath $AssemblyPath).Path
$SourceAssemblyPath = (Resolve-Path -LiteralPath $SourceAssemblyPath).Path
$ConceptMapPath = (Resolve-Path -LiteralPath $ConceptMapPath).Path
$PatchTextPath = (Resolve-Path -LiteralPath $PatchTextPath).Path

$source = Get-ConceptTooltipCatalog -Path $SourceAssemblyPath
$patch = Get-ConceptTooltipCatalog -Path $AssemblyPath
Assert-RegistrationInventory -Catalog $source -Role "Source"
Assert-RegistrationInventory -Catalog $patch -Role "Patched"

$sourceByKey = @{}
foreach ($entry in @($source.Entries)) { $sourceByKey[[string]$entry.Key] = $entry }
$patchByKey = @{}
foreach ($entry in @($patch.Entries)) { $patchByKey[[string]$entry.Key] = $entry }
foreach ($key in $sourceByKey.Keys) {
    if (!$patchByKey.ContainsKey($key)) {
        throw "Patched catalog is missing source concept tooltip key: $key"
    }
    $sourceEntry = $sourceByKey[$key]
    $patchEntry = $patchByKey[$key]
    if ($sourceEntry.RegistrationOffset -ne $patchEntry.RegistrationOffset -or
        $sourceEntry.Composition -ne $patchEntry.Composition -or
        [bool]$sourceEntry.IsXmlTextKeyReference -ne [bool]$patchEntry.IsXmlTextKeyReference) {
        throw "Patched catalog changed the registration contract for concept tooltip $key."
    }
}

$map = Get-Content -LiteralPath $ConceptMapPath -Raw -Encoding UTF8 | ConvertFrom-Json
$mapKeys = @($map.Concepts | ForEach-Object { [string]$_.Key })
$registrationOnlyKeys = @("DEFEND", "ENEMY", "FOOD", "FRIEND")
$unexpectedKeys = @($patchByKey.Keys | Where-Object {
    $_ -notin $mapKeys -and $_ -notin $registrationOnlyKeys
})
if ($unexpectedKeys.Count -gt 0) {
    throw "Concept registration inventory contains undocumented keys: $($unexpectedKeys -join ', ')."
}
$missingRegistrationOnlyKeys = @($registrationOnlyKeys | Where-Object { !$patchByKey.ContainsKey($_) })
if ($missingRegistrationOnlyKeys.Count -gt 0) {
    throw "Concept registration-only keys are missing: $($missingRegistrationOnlyKeys -join ', ')."
}

[xml]$patchText = Get-Content -LiteralPath $PatchTextPath -Raw -Encoding UTF8
$residualEnglish = @()
foreach ($entry in @($patch.Entries)) {
    if ($entry.IsXmlTextKeyReference) {
        $xmlText = @($patchText.SelectNodes("//e") | Where-Object {
            $_.GetAttribute("ntry") -eq $entry.Description
        })
        if ($xmlText.Count -ne 1 -or [string]$xmlText[0].InnerText -notmatch "[\p{IsCJKUnifiedIdeographs}]") {
            $residualEnglish += "$($entry.Key): unresolved XML text key $($entry.Description)"
        }
        continue
    }

    $visible = Get-VisibleConceptText -Text ([string]$entry.Description)
    # Keep the game title and its standard abbreviation; all other word-like
    # English remnants in the literal tooltip prose are localization failures.
    $visible = $visible -replace "At the Gates", "" -replace "\bAtG\b", ""
    $words = @([regex]::Matches($visible, "[A-Za-z]{2,}") | ForEach-Object Value)
    if ($words.Count -gt 0) {
        $residualEnglish += "$($entry.Key): $($words -join ', ')"
    }
}
if ($residualEnglish.Count -gt 0) {
    throw "Patched concept tooltip literals still contain English: $($residualEnglish -join '; ')"
}

$social = $patchByKey["SOCIAL"]
if ($social.Composition -ne "Concat" -or @($social.Parts | Where-Object {
    $_.IlOffset -eq "<dynamic>" -and $_.Value -eq "{font-icon:Social}"
}).Count -ne 1) {
    throw "SOCIAL tooltip must retain its dynamic FontIcons composition part."
}

Write-Host "Concept tooltip localization test passed: 111 static registrations, 109 concept-link labels, 4 registration-only keys."
