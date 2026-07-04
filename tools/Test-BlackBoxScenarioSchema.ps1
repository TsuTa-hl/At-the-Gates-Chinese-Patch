param(
    [string]$ScenarioPath
)

$ErrorActionPreference = "Stop"

function Assert-AtGCondition {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (!$Condition) {
        throw $Message
    }
}

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

function Test-AtGPropertyExists {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Object,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    return $null -ne $Object.PSObject.Properties[$Name]
}

if ([string]::IsNullOrWhiteSpace($ScenarioPath)) {
    $ScenarioPath = Join-Path $PSScriptRoot "..\docs\agent\black-box-scenarios.json"
}

if (!(Test-Path -LiteralPath $ScenarioPath -PathType Leaf)) {
    throw "Scenario file not found: $ScenarioPath"
}

$root = Get-Content -LiteralPath $ScenarioPath -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-AtGCondition (Test-AtGPropertyExists -Object $root -Name "Version") "Scenario file is missing Version."
Assert-AtGCondition (Test-AtGPropertyExists -Object $root -Name "FullRegression") "Scenario file is missing FullRegression."
Assert-AtGCondition (Test-AtGPropertyExists -Object $root -Name "Incremental") "Scenario file is missing Incremental."

$validStatuses = @("Active", "Completed", "Deferred", "Discovery", "ManualOnly")
$validActions = @("Click", "Hover", "ClickAndCapture", "HoverAndCapture", "CaptureOnly")
$scenarioIds = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
$scenarioCount = 0
$pointCount = 0

foreach ($suiteName in @("FullRegression", "Incremental")) {
    foreach ($scenario in @((Get-AtGPropertyValue -Object $root -Name $suiteName))) {
        if ($null -eq $scenario) {
            continue
        }

        $scenarioCount++
        $id = [string](Get-AtGPropertyValue -Object $scenario -Name "Id")
        $title = [string](Get-AtGPropertyValue -Object $scenario -Name "Title")
        $category = [string](Get-AtGPropertyValue -Object $scenario -Name "Category")
        $status = [string](Get-AtGPropertyValue -Object $scenario -Name "Status")
        $points = @(Get-AtGPropertyValue -Object $scenario -Name "Points")

        Assert-AtGCondition (![string]::IsNullOrWhiteSpace($id)) "Scenario in $suiteName is missing Id."
        Assert-AtGCondition ($scenarioIds.Add($id)) "Duplicate scenario Id: $id"
        Assert-AtGCondition (![string]::IsNullOrWhiteSpace($title)) "Scenario $id is missing Title."
        Assert-AtGCondition (![string]::IsNullOrWhiteSpace($category)) "Scenario $id is missing Category."
        Assert-AtGCondition ($validStatuses -contains $status) "Scenario $id has invalid Status '$status'."
        Assert-AtGCondition ($points.Count -gt 0) "Scenario $id must contain at least one point."

        $pointIds = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($point in $points) {
            $pointCount++
            $pointId = [string](Get-AtGPropertyValue -Object $point -Name "Id")
            $action = [string](Get-AtGPropertyValue -Object $point -Name "Action")
            $x = Get-AtGPropertyValue -Object $point -Name "X"
            $y = Get-AtGPropertyValue -Object $point -Name "Y"
            $discover = [bool](Get-AtGPropertyValue -Object $point -Name "Discover")
            $waitMs = Get-AtGPropertyValue -Object $point -Name "WaitMs"

            Assert-AtGCondition (![string]::IsNullOrWhiteSpace($pointId)) "Scenario $id has a point without Id."
            Assert-AtGCondition ($pointIds.Add($pointId)) "Scenario $id has duplicate point Id '$pointId'."
            Assert-AtGCondition ($validActions -contains $action) "Scenario $id point $pointId has invalid Action '$action'."

            $hasCoordinates = ($null -ne $x -and $null -ne $y)
            if ($hasCoordinates) {
                Assert-AtGCondition (($x -is [int] -or $x -is [long]) -and ($y -is [int] -or $y -is [long])) "Scenario $id point $pointId coordinates must be integers."
                Assert-AtGCondition ([int]$x -ge 0 -and [int]$y -ge 0) "Scenario $id point $pointId coordinates must be non-negative."
            }
            else {
                Assert-AtGCondition ($discover -or $status -eq "Discovery") "Scenario $id point $pointId is missing coordinates but is not marked Discover."
            }

            if ($null -ne $waitMs) {
                $maxWaitMs = if ($action -like "Hover*") { 3000 } else { 15000 }
                Assert-AtGCondition (($waitMs -is [int] -or $waitMs -is [long]) -and [int]$waitMs -ge 0 -and [int]$waitMs -le $maxWaitMs) "Scenario $id point $pointId WaitMs must be between 0 and $maxWaitMs."
            }

            $crop = Get-AtGPropertyValue -Object $point -Name "Crop"
            if ($null -ne $crop) {
                foreach ($name in @("X", "Y", "Width", "Height")) {
                    $value = Get-AtGPropertyValue -Object $crop -Name $name
                    Assert-AtGCondition (($value -is [int] -or $value -is [long])) "Scenario $id point $pointId crop.$name must be an integer."
                }
                Assert-AtGCondition ([int](Get-AtGPropertyValue -Object $crop -Name "Width") -gt 0) "Scenario $id point $pointId crop width must be positive."
                Assert-AtGCondition ([int](Get-AtGPropertyValue -Object $crop -Name "Height") -gt 0) "Scenario $id point $pointId crop height must be positive."
            }
        }
    }
}

[pscustomobject]@{
    ScenarioPath = (Resolve-Path -LiteralPath $ScenarioPath).Path
    ScenarioCount = $scenarioCount
    PointCount = $pointCount
    Status = "Passed"
}

Write-Host "Black-box scenario schema validation passed."
