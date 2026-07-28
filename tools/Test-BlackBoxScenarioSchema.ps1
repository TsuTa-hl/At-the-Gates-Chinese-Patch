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
$validActions = @("Click", "Hover", "ClickAndCapture", "HoverAndCapture", "CaptureOnly", "TileHoverSweep")
$validControlActions = @(
    "Click", "Hover", "Move", "Key", "Wait",
    "BookmarkProgramLog", "WaitForProgramLogMarker", "Repeat"
)
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
        Assert-AtGCondition ($status -eq "ManualOnly" -or $points.Count -gt 0) "Scenario $id must contain at least one point unless it is ManualOnly."

        $expectedAnyValue = Get-AtGPropertyValue -Object $scenario -Name "ExpectedAny"
        $expectedAny = if ($null -eq $expectedAnyValue) { @() } else { @($expectedAnyValue) }
        foreach ($expectedText in $expectedAny) {
            Assert-AtGCondition ($expectedText -is [string] -and ![string]::IsNullOrWhiteSpace([string]$expectedText)) "Scenario $id ExpectedAny must contain non-empty strings."
        }

        if ($id -eq "clan-screen-random-traits") {
            $dynamicDiscovery = Get-AtGPropertyValue -Object $scenario -Name "DynamicTraitDiscovery"
            $traitScope = @(Get-AtGPropertyValue -Object $scenario -Name "TraitScope")
            Assert-AtGCondition ($status -eq "ManualOnly") "Scenario $id must remain the archived ManualOnly protocol."
            Assert-AtGCondition ((@($traitScope | Where-Object { [string]$_ -match "Non-personality traits" })).Count -gt 0) "Scenario $id must include non-personality traits in TraitScope."
            Assert-AtGCondition ($null -ne $dynamicDiscovery) "Scenario $id is missing DynamicTraitDiscovery."
            Assert-AtGCondition ([bool](Get-AtGPropertyValue -Object $dynamicDiscovery -Name "Required")) "Scenario $id DynamicTraitDiscovery must be required."
            Assert-AtGCondition ([string](Get-AtGPropertyValue -Object $dynamicDiscovery -Name "Mode") -eq "ManualRandomDiscovery") "Scenario $id must use ManualRandomDiscovery for random layouts."
            Assert-AtGCondition ([string](Get-AtGPropertyValue -Object $dynamicDiscovery -Name "SetupMode") -eq "new-game") "Scenario $id random discovery must use new-game setup."
            Assert-AtGCondition (@(Get-AtGPropertyValue -Object $dynamicDiscovery -Name "RecordBeforeVerification").Count -ge 1) "Scenario $id random discovery must define evidence fields."
        }

        if ($id -eq "clan-trait-random-discovery") {
            Assert-AtGCondition ($expectedAny.Count -gt 0) "Scenario $id must require an observed translated trait title before a fixed-point hover can pass."
            Assert-AtGCondition ($points.Count -eq 6) "Scenario $id must cover all six fixed trait slots."
            $actualCoordinates = @($points | ForEach-Object {
                "{0},{1}" -f (Get-AtGPropertyValue -Object $_ -Name "X"), (Get-AtGPropertyValue -Object $_ -Name "Y")
            } | Sort-Object)
            $expectedCoordinates = @("1182,639", "1182,655", "1331,639", "1331,655", "1483,639", "1483,655" | Sort-Object)
            Assert-AtGCondition (($actualCoordinates -join ";") -eq ($expectedCoordinates -join ";")) "Scenario $id must use exactly the six fixed global absolute trait coordinates."
        }

        $tileSweep = Get-AtGPropertyValue -Object $scenario -Name "TileSweep"
        if ($null -ne $tileSweep) {
            Assert-AtGCondition ($points.Count -eq 1) "Scenario $id TileSweep must use exactly one dynamic point."
            $sweepPoint = $points[0]
            Assert-AtGCondition ([string](Get-AtGPropertyValue -Object $sweepPoint -Name "Id") -eq "tile_sweep") "Scenario $id TileSweep point Id must be tile_sweep."
            Assert-AtGCondition ([string](Get-AtGPropertyValue -Object $sweepPoint -Name "Action") -eq "TileHoverSweep") "Scenario $id TileSweep point must use TileHoverSweep."
            $radius = Get-AtGPropertyValue -Object $tileSweep -Name "Radius"
            Assert-AtGCondition (($radius -is [int] -or $radius -is [long]) -and [int]$radius -eq 5) "Scenario $id TileSweep Radius must be exactly 5."
            Assert-AtGCondition ([string](Get-AtGPropertyValue -Object $tileSweep -Name "Metric") -eq "AxialHex") "Scenario $id TileSweep Metric must be AxialHex."
            Assert-AtGCondition ([string](Get-AtGPropertyValue -Object $tileSweep -Name "Enumerate") -eq "CenterOutward") "Scenario $id TileSweep Enumerate must be CenterOutward."
            Assert-AtGCondition ([bool](Get-AtGPropertyValue -Object $tileSweep -Name "ExpandCollapsed")) "Scenario $id TileSweep must expand collapsed cards."
            Assert-AtGCondition ([bool](Get-AtGPropertyValue -Object $tileSweep -Name "CycleItems")) "Scenario $id TileSweep must allow bounded item cycling."
            Assert-AtGCondition ([int](Get-AtGPropertyValue -Object $tileSweep -Name "MaxCardsPerTile") -eq 16) "Scenario $id TileSweep MaxCardsPerTile must be 16."
            Assert-AtGCondition ([int](Get-AtGPropertyValue -Object $tileSweep -Name "MaxCyclesPerTile") -eq 2) "Scenario $id TileSweep MaxCyclesPerTile must be 2."
            $manifestId = [string](Get-AtGPropertyValue -Object $tileSweep -Name "BoundaryManifestId")
            Assert-AtGCondition (![string]::IsNullOrWhiteSpace($manifestId)) "Scenario $id TileSweep BoundaryManifestId is required."
            $scenarioAbsolute = (Resolve-Path -LiteralPath $ScenarioPath).Path
            $repoRoot = Split-Path (Split-Path (Split-Path $scenarioAbsolute -Parent) -Parent) -Parent
            $manifestPath = Join-Path $repoRoot "docs\agent\terrain-tooltip-boundary.json"
            Assert-AtGCondition (Test-Path -LiteralPath $manifestPath -PathType Leaf) "Scenario $id TileSweep boundary manifest is missing."
            $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
            Assert-AtGCondition ([string](Get-AtGPropertyValue -Object $manifest -Name "BoundaryManifestId") -eq $manifestId) "Scenario $id TileSweep BoundaryManifestId does not match the manifest."
            $manifestCounts = Get-AtGPropertyValue -Object $manifest -Name "Counts"
            Assert-AtGCondition ([int](Get-AtGPropertyValue -Object $manifestCounts -Name "Terrains") -eq 23 -and [int](Get-AtGPropertyValue -Object $manifestCounts -Name "Deposits") -eq 78 -and [int](Get-AtGPropertyValue -Object $manifestCounts -Name "Resources") -eq 42) "Scenario $id TileSweep boundary manifest source counts must be 23/78/42."
            Assert-AtGCondition (@(Get-AtGPropertyValue -Object $manifest -Name "Entries").Count -eq 143) "Scenario $id TileSweep boundary manifest must enumerate 143 source entries."
            if ([bool](Get-AtGPropertyValue -Object $scenario -Name "RequiresFixedSave")) {
                $saveName = [string](Get-AtGPropertyValue -Object $scenario -Name "SaveName")
                Assert-AtGCondition (![string]::IsNullOrWhiteSpace($saveName)) "Scenario $id fixed-save TileSweep requires SaveName."
            }

            $anchor = Get-AtGPropertyValue -Object $tileSweep -Name "Anchor"
            $basisQ = Get-AtGPropertyValue -Object $tileSweep -Name "BasisQ"
            $basisR = Get-AtGPropertyValue -Object $tileSweep -Name "BasisR"
            foreach ($pair in @(@("Anchor", $anchor), @("BasisQ", $basisQ), @("BasisR", $basisR))) {
                $name = [string]$pair[0]
                $point = $pair[1]
                Assert-AtGCondition ($null -ne $point) "Scenario $id TileSweep $name is required."
                foreach ($axis in @("X", "Y")) {
                    $value = Get-AtGPropertyValue -Object $point -Name $axis
                    Assert-AtGCondition (($value -is [int] -or $value -is [long]) -and [int]$value -ge 0) "Scenario $id TileSweep $name.$axis must be a non-negative integer."
                }
                Assert-AtGCondition ([int](Get-AtGPropertyValue -Object $point -Name "X") -lt 2560 -and [int](Get-AtGPropertyValue -Object $point -Name "Y") -lt 1440) "Scenario $id TileSweep $name must be inside the 2560x1440 reference client."
            }
            $dqX = [int](Get-AtGPropertyValue -Object $basisQ -Name "X") - [int](Get-AtGPropertyValue -Object $anchor -Name "X")
            $dqY = [int](Get-AtGPropertyValue -Object $basisQ -Name "Y") - [int](Get-AtGPropertyValue -Object $anchor -Name "Y")
            $drX = [int](Get-AtGPropertyValue -Object $basisR -Name "X") - [int](Get-AtGPropertyValue -Object $anchor -Name "X")
            $drY = [int](Get-AtGPropertyValue -Object $basisR -Name "Y") - [int](Get-AtGPropertyValue -Object $anchor -Name "Y")
            Assert-AtGCondition (!(($dqX -eq 0 -and $dqY -eq 0) -or ($drX -eq 0 -and $drY -eq 0))) "Scenario $id TileSweep basis points must differ from Anchor."
            Assert-AtGCondition (($dqX * $drY - $dqY * $drX) -ne 0) "Scenario $id TileSweep basis points must be non-collinear."

            $safe = Get-AtGPropertyValue -Object $tileSweep -Name "SafeViewport"
            Assert-AtGCondition ($null -ne $safe) "Scenario $id TileSweep SafeViewport is required."
            foreach ($name in @("X", "Y", "Width", "Height")) {
                $value = Get-AtGPropertyValue -Object $safe -Name $name
                Assert-AtGCondition (($value -is [int] -or $value -is [long]) -and [int]$value -ge 0) "Scenario $id TileSweep SafeViewport.$name must be a non-negative integer."
            }
            Assert-AtGCondition ([int](Get-AtGPropertyValue -Object $safe -Name "Width") -gt 0 -and [int](Get-AtGPropertyValue -Object $safe -Name "Height") -gt 0) "Scenario $id TileSweep SafeViewport must be positive."
            Assert-AtGCondition ([int](Get-AtGPropertyValue -Object $safe -Name "X") + [int](Get-AtGPropertyValue -Object $safe -Name "Width") -le 2560 -and [int](Get-AtGPropertyValue -Object $safe -Name "Y") + [int](Get-AtGPropertyValue -Object $safe -Name "Height") -le 1440) "Scenario $id TileSweep SafeViewport must fit the reference client."

            foreach ($regionName in @("MapRegion", "QuickReferenceRegion")) {
                $region = Get-AtGPropertyValue -Object $tileSweep -Name $regionName
                Assert-AtGCondition ($null -ne $region) "Scenario $id TileSweep $regionName is required."
                foreach ($name in @("X", "Y", "Width", "Height")) {
                    $value = Get-AtGPropertyValue -Object $region -Name $name
                    Assert-AtGCondition (($value -is [int] -or $value -is [long]) -and [int]$value -ge 0) "Scenario $id TileSweep $regionName.$name must be a non-negative integer."
                }
                Assert-AtGCondition ([int](Get-AtGPropertyValue -Object $region -Name "Width") -gt 0 -and [int](Get-AtGPropertyValue -Object $region -Name "Height") -gt 0) "Scenario $id TileSweep $regionName must be positive."
                Assert-AtGCondition ([int](Get-AtGPropertyValue -Object $region -Name "X") + [int](Get-AtGPropertyValue -Object $region -Name "Width") -le 2560 -and [int](Get-AtGPropertyValue -Object $region -Name "Y") + [int](Get-AtGPropertyValue -Object $region -Name "Height") -le 1440) "Scenario $id TileSweep $regionName must fit the reference client."
            }

            $coordinates = @()
            for ($q = -5; $q -le 5; $q++) {
                for ($r = -5; $r -le 5; $r++) {
                    if ([Math]::Max([Math]::Abs($q), [Math]::Max([Math]::Abs($r), [Math]::Abs($q + $r))) -gt 5) { continue }
                    $coordinates += [pscustomobject]@{
                        X = [int](Get-AtGPropertyValue -Object $anchor -Name "X") + $q * $dqX + $r * $drX
                        Y = [int](Get-AtGPropertyValue -Object $anchor -Name "Y") + $q * $dqY + $r * $drY
                    }
                }
            }
            Assert-AtGCondition ($coordinates.Count -eq 91) "Scenario $id TileSweep must generate 91 coordinates."
            $uniqueCoordinates = @($coordinates | ForEach-Object { "{0},{1}" -f $_.X, $_.Y } | Sort-Object -Unique)
            Assert-AtGCondition ($uniqueCoordinates.Count -eq 91) "Scenario $id TileSweep generated duplicate coordinates."
            foreach ($coordinate in $coordinates) {
                Assert-AtGCondition ($coordinate.X -ge [int](Get-AtGPropertyValue -Object $safe -Name "X") -and $coordinate.X -lt ([int](Get-AtGPropertyValue -Object $safe -Name "X") + [int](Get-AtGPropertyValue -Object $safe -Name "Width")) -and $coordinate.Y -ge [int](Get-AtGPropertyValue -Object $safe -Name "Y") -and $coordinate.Y -lt ([int](Get-AtGPropertyValue -Object $safe -Name "Y") + [int](Get-AtGPropertyValue -Object $safe -Name "Height"))) "Scenario $id TileSweep coordinate ($($coordinate.X),$($coordinate.Y)) is outside SafeViewport."
            }
        }

        foreach ($phase in @("SetupActions", "TeardownActions")) {
            foreach ($control in @(Get-AtGPropertyValue -Object $scenario -Name $phase)) {
                if ($null -eq $control) {
                    continue
                }
                $controlAction = [string](Get-AtGPropertyValue -Object $control -Name "Action")
                Assert-AtGCondition ($validControlActions -contains $controlAction) "Scenario $id $phase contains invalid Action '$controlAction'."
                if ($controlAction -eq "BookmarkProgramLog") {
                    $bookmark = [string](Get-AtGPropertyValue -Object $control -Name "Bookmark")
                    Assert-AtGCondition (![string]::IsNullOrWhiteSpace($bookmark)) "Scenario $id $phase BookmarkProgramLog requires Bookmark."
                }
                if ($controlAction -eq "WaitForProgramLogMarker") {
                    $bookmark = [string](Get-AtGPropertyValue -Object $control -Name "Bookmark")
                    $marker = [string](Get-AtGPropertyValue -Object $control -Name "Marker")
                    $controlWaitMs = Get-AtGPropertyValue -Object $control -Name "WaitMs"
                    Assert-AtGCondition (![string]::IsNullOrWhiteSpace($bookmark)) "Scenario $id $phase WaitForProgramLogMarker requires Bookmark."
                    Assert-AtGCondition (![string]::IsNullOrWhiteSpace($marker)) "Scenario $id $phase WaitForProgramLogMarker requires Marker."
                    Assert-AtGCondition (($controlWaitMs -is [int] -or $controlWaitMs -is [long]) -and [int]$controlWaitMs -gt 0 -and [int]$controlWaitMs -le 120000) "Scenario $id $phase WaitForProgramLogMarker WaitMs must be between 1 and 120000."
                }
                if ($controlAction -eq "Repeat") {
                    $repeatCount = Get-AtGPropertyValue -Object $control -Name "RepeatCount"
                    $nestedActions = @(Get-AtGPropertyValue -Object $control -Name "Actions")
                    Assert-AtGCondition (($repeatCount -is [int] -or $repeatCount -is [long]) -and [int]$repeatCount -ge 1 -and [int]$repeatCount -le 10) "Scenario $id $phase RepeatCount must be between 1 and 10."
                    Assert-AtGCondition ($nestedActions.Count -gt 0) "Scenario $id $phase Repeat requires nested Actions."
                    foreach ($nested in $nestedActions) {
                        $nestedAction = [string](Get-AtGPropertyValue -Object $nested -Name "Action")
                        Assert-AtGCondition ($validControlActions -contains $nestedAction -and $nestedAction -ne "Repeat") "Scenario $id $phase Repeat contains invalid nested Action '$nestedAction'."
                    }
                }
            }
        }

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
            elseif ($action -ne "CaptureOnly") {
                Assert-AtGCondition ($discover -or $status -eq "Discovery") "Scenario $id point $pointId is missing coordinates but is not marked Discover."
            }

            if ($null -ne $waitMs) {
                $maxWaitMs = if ($action -like "Hover*") { 3000 } else { 15000 }
                Assert-AtGCondition (($waitMs -is [int] -or $waitMs -is [long]) -and [int]$waitMs -ge 0 -and [int]$waitMs -le $maxWaitMs) "Scenario $id point $pointId WaitMs must be between 0 and $maxWaitMs."
            }

            $readyMarker = [string](Get-AtGPropertyValue -Object $point -Name "ReadyMarker")
            $readyTimeoutMs = Get-AtGPropertyValue -Object $point -Name "ReadyTimeoutMs"
            $expectedAllValue = Get-AtGPropertyValue -Object $point -Name "ExpectedAll"
            $expectedAll = if ($null -eq $expectedAllValue) { @() } else { @($expectedAllValue) }
            foreach ($expectedText in $expectedAll) {
                Assert-AtGCondition ($expectedText -is [string] -and ![string]::IsNullOrWhiteSpace([string]$expectedText)) "Scenario $id point $pointId ExpectedAll must contain non-empty strings."
            }
            if (![string]::IsNullOrWhiteSpace($readyMarker) -or $null -ne $readyTimeoutMs) {
                Assert-AtGCondition (![string]::IsNullOrWhiteSpace($readyMarker)) "Scenario $id point $pointId ReadyTimeoutMs requires ReadyMarker."
                Assert-AtGCondition ($action -ne "CaptureOnly") "Scenario $id point $pointId ReadyMarker requires an action."
                Assert-AtGCondition (($readyTimeoutMs -is [int] -or $readyTimeoutMs -is [long]) -and [int]$readyTimeoutMs -gt 0 -and [int]$readyTimeoutMs -le 120000) "Scenario $id point $pointId ReadyTimeoutMs must be between 1 and 120000."
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
