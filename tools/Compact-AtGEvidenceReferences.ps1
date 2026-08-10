[CmdletBinding()]
param(
    [string]$ProjectRoot,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]*$')]
    [string]$HandoffId
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}
else {
    $ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
}

function Read-AtGJson {
    param([string]$Path)

    if (!(Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }

    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Write-AtGJson {
    param(
        [string]$Path,
        [object]$Value
    )

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    # Git tracks repository JSON with LF. Preserve that stable format so a
    # cleanup compaction changes only evidence fields, not every line ending.
    $json = ($Value | ConvertTo-Json -Depth 100) -replace "`r`n", "`n"
    [IO.File]::WriteAllText($Path, $json, $utf8NoBom)
}

function Test-AtGTemporaryEvidencePath {
    param([object]$Value)

    return ($Value -is [string]) -and ($Value -match '^(?:\.tmp[\\/]|\.tmp$)')
}

function Add-AtGProperty {
    param(
        [object]$Object,
        [string]$Name,
        [object]$Value
    )

    if ($null -ne $Object.PSObject.Properties[$Name]) {
        $Object.$Name = $Value
    }
    else {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    }
}

function Compact-AtGEvidenceObject {
    param(
        [object]$Evidence,
        [string]$RunProperty = "LastRunDir"
    )

    if ($null -eq $Evidence) {
        return $false
    }

    $changed = $false
    $run = $Evidence.PSObject.Properties[$RunProperty]
    if ($null -ne $run) {
        if (Test-AtGTemporaryEvidencePath -Value $run.Value) {
            $Evidence.PSObject.Properties.Remove($RunProperty)
            Add-AtGProperty -Object $Evidence -Name "EvidenceHandoff" -Value $HandoffId
            Add-AtGProperty -Object $Evidence -Name "EvidenceRetention" -Value "TextOnly"
            $changed = $true
        }
        elseif ($null -eq $run.Value) {
            $Evidence.PSObject.Properties.Remove($RunProperty)
            $changed = $true
        }
    }

    foreach ($propertyName in @("LastContactSheet", "LastScreenshot")) {
        $property = $Evidence.PSObject.Properties[$propertyName]
        if ($null -ne $property -and (Test-AtGTemporaryEvidencePath -Value $property.Value)) {
            $Evidence.PSObject.Properties.Remove($propertyName)
            Add-AtGProperty -Object $Evidence -Name "EvidenceHandoff" -Value $HandoffId
            Add-AtGProperty -Object $Evidence -Name "EvidenceRetention" -Value "TextOnly"
            $changed = $true
        }
    }

    return $changed
}

$scenarioPath = Join-Path $ProjectRoot "docs\agent\black-box-scenarios.json"
$traitPath = Join-Path $ProjectRoot "docs\agent\clan-trait-verification.json"

$scenarioChanges = 0
$scenario = Read-AtGJson -Path $scenarioPath
if ($null -ne $scenario) {
    foreach ($suiteName in @("FullRegression", "Incremental")) {
        $suiteProperty = $scenario.PSObject.Properties[$suiteName]
        if ($null -eq $suiteProperty) {
            continue
        }

        foreach ($item in @($suiteProperty.Value)) {
            if (Compact-AtGEvidenceObject -Evidence $item.Evidence) {
                $scenarioChanges++
            }

            if ($null -ne $item.Evidence -and $null -ne $item.Evidence.RandomDiscoveryLastRun) {
                if (Compact-AtGEvidenceObject -Evidence $item.Evidence.RandomDiscoveryLastRun -RunProperty "RunDir") {
                    $scenarioChanges++
                }
            }
        }
    }

    if ($scenarioChanges -gt 0) {
        Write-AtGJson -Path $scenarioPath -Value $scenario
    }
}

$traitChanges = 0
$traits = Read-AtGJson -Path $traitPath
if ($null -ne $traits) {
    foreach ($trait in @($traits.Traits)) {
        $property = $trait.PSObject.Properties["EvidenceDir"]
        if ($null -eq $property) {
            continue
        }

        if (Test-AtGTemporaryEvidencePath -Value $property.Value) {
            $trait.PSObject.Properties.Remove("EvidenceDir")
            Add-AtGProperty -Object $trait -Name "EvidenceHandoff" -Value $HandoffId
            Add-AtGProperty -Object $trait -Name "EvidenceRetention" -Value "TextOnly"
            $traitChanges++
        }
        elseif ($null -eq $property.Value) {
            $trait.PSObject.Properties.Remove("EvidenceDir")
            $traitChanges++
        }
    }

    if ($traitChanges -gt 0) {
        Add-AtGProperty -Object $traits -Name "EvidenceRetentionPolicy" -Value "TextOnly; temporary visual evidence is summarized by cleanup handoffs."
        Write-AtGJson -Path $traitPath -Value $traits
    }
}

[pscustomobject]@{
    HandoffId = $HandoffId
    ScenarioChanges = $scenarioChanges
    TraitChanges = $traitChanges
}
