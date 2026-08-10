$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$generator = Join-Path $root "tools\Export-ConceptKeyTranslations.ps1"
$mapPath = Join-Path $root "translations\concept-key-translations.json"

& $generator -Check

$map = Get-Content -LiteralPath $mapPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($map.SchemaVersion -ne 1) {
    throw "Unexpected concept-key translation map schema: $($map.SchemaVersion)"
}
if ($map.ConceptCount -ne @($map.Concepts).Count) {
    throw "ConceptCount does not match the emitted concept collection."
}
if (@($map.Concepts).Count -eq 0) {
    throw "Concept-key translation map must contain at least one concept."
}

function Require-Label([string]$Key, [string]$English, [string]$Chinese) {
    $concept = @($map.Concepts | Where-Object { $_.Key -ceq $Key })
    if ($concept.Count -ne 1) {
        throw "Expected exactly one concept entry for $Key."
    }
    $label = @($concept[0].Labels | Where-Object { $_.English -ceq $English })
    if ($label.Count -ne 1 -or @($label[0].Chinese) -notcontains $Chinese) {
        throw "Expected $Key/$English to include Chinese label $Chinese."
    }
}

foreach ($concept in @($map.Concepts)) {
    if ([string]::IsNullOrWhiteSpace($concept.Key) -or
        $concept.Key -notmatch '^[A-Z][A-Z0-9-]*$') {
        throw "Invalid concept key in translation map: $($concept.Key)"
    }
    if (@($concept.Labels).Count -eq 0) {
        throw "Concept key has no source labels: $($concept.Key)"
    }
    foreach ($label in @($concept.Labels)) {
        if ([string]::IsNullOrWhiteSpace($label.English)) {
            throw "Concept key has an empty English source label: $($concept.Key)"
        }
    }
}

$incomplete = @($map.Concepts | Where-Object { $_.Status -ne "Complete" })
if ($incomplete.Count -gt 0) {
    $details = $incomplete | ForEach-Object { "$($_.Key):$($_.Status)" }
    throw "Known concept labels remain untranslated: $($details -join ', ')."
}
if (@($map.Concepts | Where-Object { $_.Key -eq "CONSTURCT" }).Count -ne 0) {
    throw "Known source typo CONSTURCT must normalize to CONSTRUCT in the concept-key translation map."
}

$forage = [string]::Concat([char]0x91C7, [char]0x96C6)
$forager = [string]::Concat($forage, [char]0x8005)
$harvest = [string]::Concat([char]0x91C7, [char]0x6536)
$pasture = [string]::Concat([char]0x7267, [char]0x573A)
Require-Label -Key "FORAGE" -English "Forage" -Chinese $forage
Require-Label -Key "FORAGE" -English "Forager" -Chinese $forager
Require-Label -Key "HARVEST" -English "Harvest" -Chinese $harvest
Require-Label -Key "PASTURE" -English "Pasture" -Chinese $pasture

Write-Host "Concept-key translation map test passed."
