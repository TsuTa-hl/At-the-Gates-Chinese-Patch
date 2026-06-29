param(
    [string[]]$MapPath,

    [switch]$Strict,

    [switch]$ShowWarnings
)

$ErrorActionPreference = "Stop"

function Get-AtGPropertyValue {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Object,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}

function Test-AtGBroadFragment {
    param([string]$Value)

    if ($null -eq $Value) {
        return $false
    }

    $broadFragments = @(
        " ",
        " a ",
        " an ",
        " and ",
        " or ",
        " of ",
        " to ",
        " in ",
        " for ",
        " with ",
        " (",
        ")",
        ".",
        ":"
    )

    return $broadFragments -contains $Value
}

function ConvertTo-AtGArray {
    param([object]$Value)

    if ($null -eq $Value) {
        return @()
    }

    $items = @()
    foreach ($entry in $Value) {
        $items += $entry
    }

    if ($items.Count -eq 0) {
        return @($Value)
    }

    return $items
}

if ($null -eq $MapPath -or $MapPath.Count -eq 0) {
    $MapPath = @(
        (Join-Path $PSScriptRoot "..\translations\hardcoded-ui-il-rewrite.json"),
        (Join-Path $PSScriptRoot "..\translations\hardcoded-common-il-rewrite.json"),
        (Join-Path $PSScriptRoot "..\translations\hardcoded-game-il-rewrite.json")
    )
}

$summaries = New-Object System.Collections.Generic.List[object]
$failures = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]

foreach ($path in $MapPath) {
    if (!(Test-Path -LiteralPath $path -PathType Leaf)) {
        $warnings.Add("Map not found: $path") | Out-Null
        continue
    }

    $parsed = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    $items = @(ConvertTo-AtGArray -Value $parsed)
    $riskCount = 0
    $emptyTranslationCount = 0
    $shortOriginalCount = 0
    $broadFragmentCount = 0
    $missingEvidenceScenarioCount = 0

    for ($i = 0; $i -lt $items.Count; $i++) {
        $item = $items[$i]
        $hasOriginalProperty = $null -ne $item.PSObject.Properties["Original"]
        $original = [string](Get-AtGPropertyValue -Object $item -Name "Original")
        $translation = Get-AtGPropertyValue -Object $item -Name "Translation"
        $methodToken = [string](Get-AtGPropertyValue -Object $item -Name "MethodToken")
        $ilOffset = Get-AtGPropertyValue -Object $item -Name "ILOffset"
        $safety = [string](Get-AtGPropertyValue -Object $item -Name "Safety")
        $note = [string](Get-AtGPropertyValue -Object $item -Name "Note")
        $evidenceScenario = [string](Get-AtGPropertyValue -Object $item -Name "EvidenceScenario")

        if (!$hasOriginalProperty) {
            $failures.Add("$($path)[$i] is missing Original.") | Out-Null
        }
        if ([string]::IsNullOrWhiteSpace($methodToken)) {
            $failures.Add("$($path)[$i] is missing MethodToken.") | Out-Null
        }
        if ($null -eq $ilOffset) {
            $failures.Add("$($path)[$i] is missing ILOffset.") | Out-Null
        }

        $isShort = ($null -ne $original -and $original.Length -le 5)
        $isEmptyTranslation = ($null -eq $translation -or [string]$translation -eq "")
        $isBroad = Test-AtGBroadFragment -Value $original
        $hasOuterWhitespace = ($null -ne $original -and $original -match '^\s|\s$')
        $isRisky = ($isShort -or $isEmptyTranslation -or $isBroad -or $hasOuterWhitespace)

        if ($isShort) { $shortOriginalCount++ }
        if ($isEmptyTranslation) { $emptyTranslationCount++ }
        if ($isBroad) { $broadFragmentCount++ }

        if ($isRisky) {
            $riskCount++
            if ([string]::IsNullOrWhiteSpace($safety)) {
                $failures.Add("$($path)[$i] risky entry '$original' is missing Safety.") | Out-Null
            }
            if ([string]::IsNullOrWhiteSpace($note)) {
                $failures.Add("$($path)[$i] risky entry '$original' is missing Note.") | Out-Null
            }
            if ([string]::IsNullOrWhiteSpace($evidenceScenario)) {
                $missingEvidenceScenarioCount++
                $message = "$($path)[$i] risky entry '$original' is missing EvidenceScenario."
                if ($Strict) {
                    $failures.Add($message) | Out-Null
                }
                else {
                    $warnings.Add($message) | Out-Null
                }
            }
        }
    }

    $summaries.Add([pscustomobject]@{
        MapPath = (Resolve-Path -LiteralPath $path).Path
        EntryCount = $items.Count
        RiskyEntryCount = $riskCount
        ShortOriginalCount = $shortOriginalCount
        EmptyTranslationCount = $emptyTranslationCount
        BroadFragmentCount = $broadFragmentCount
        MissingEvidenceScenarioCount = $missingEvidenceScenarioCount
    }) | Out-Null
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    throw "IL rewrite map risk validation failed with $($failures.Count) error(s)."
}

if ($ShowWarnings) {
    foreach ($warning in $warnings) {
        Write-Warning $warning
    }
}
elseif ($warnings.Count -gt 0) {
    Write-Warning "$($warnings.Count) risky entries are missing EvidenceScenario. Re-run with -ShowWarnings for details or -Strict to fail on them."
}

$summaries
Write-Host "IL rewrite map risk validation passed."
