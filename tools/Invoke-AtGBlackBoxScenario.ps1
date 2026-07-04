param(
    [Parameter(Mandatory = $true)]
    [string]$ScenarioId,

    [string]$ScenarioPath,

    [ValidateSet("Incremental", "FullRegression", "All")]
    [string]$Suite = "Incremental",

    [string]$OutputRoot,

    [switch]$DryRun,

    [switch]$SkipPassed,

    [switch]$UseComputerUseFirst,

    [int]$DefaultWaitMs = 900
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

function Get-AtGScenarioCandidates {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Root,

        [Parameter(Mandatory = $true)]
        [string]$Suite
    )

    $items = @()
    if ($Suite -eq "Incremental" -or $Suite -eq "All") {
        $items += @(Get-AtGPropertyValue -Object $Root -Name "Incremental")
    }
    if ($Suite -eq "FullRegression" -or $Suite -eq "All") {
        $items += @(Get-AtGPropertyValue -Object $Root -Name "FullRegression")
    }

    return $items
}

function Invoke-AtGPointAction {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Point,

        [Parameter(Mandatory = $true)]
        [string]$RunDirectory,

        [int]$DefaultWaitMs,

        [int]$ClearX = -1,

        [int]$ClearY = -1,

        [int]$ClearWaitMs = 150
    )

    $id = [string](Get-AtGPropertyValue -Object $Point -Name "Id")
    $action = [string](Get-AtGPropertyValue -Object $Point -Name "Action")
    $x = Get-AtGPropertyValue -Object $Point -Name "X"
    $y = Get-AtGPropertyValue -Object $Point -Name "Y"
    $waitMs = Get-AtGPropertyValue -Object $Point -Name "WaitMs"
    if ($null -eq $waitMs) {
        $waitMs = $DefaultWaitMs
    }
    $skipClear = [bool](Get-AtGPropertyValue -Object $Point -Name "SkipClear")

    $result = [ordered]@{
        Id = $id
        Action = $action
        X = $x
        Y = $y
        WaitMs = [int]$waitMs
        Status = "Passed"
        CapturePath = $null
        CropPath = $null
        Error = $null
    }

    if (($action -ne "CaptureOnly") -and ($null -eq $x -or $null -eq $y)) {
        $result.Status = "Skipped"
        $result.Error = "Missing coordinates; mark this point during discovery."
        return [pscustomobject]$result
    }

    $pointStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        if (!$skipClear -and $ClearX -ge 0 -and $ClearY -ge 0) {
            & "$PSScriptRoot\Move-AtGWindow.ps1" -X $ClearX -Y $ClearY | Out-Null
            if ($ClearWaitMs -gt 0) {
                Start-Sleep -Milliseconds $ClearWaitMs
            }
        }

        if ($action -eq "Hover" -or $action -eq "HoverAndCapture") {
            & "$PSScriptRoot\Move-AtGWindow.ps1" -X ([int]$x) -Y ([int]$y) | Out-Null
            Start-Sleep -Milliseconds ([int]$waitMs)
        }
        elseif ($action -eq "Click" -or $action -eq "ClickAndCapture") {
            & "$PSScriptRoot\Click-AtGWindow.ps1" -X ([int]$x) -Y ([int]$y) | Out-Null
            Start-Sleep -Milliseconds ([int]$waitMs)
        }

        if ($action -eq "HoverAndCapture" -or $action -eq "ClickAndCapture" -or $action -eq "CaptureOnly") {
            $capturePath = Join-Path $RunDirectory ($id + ".png")
            & "$PSScriptRoot\Capture-AtGWindow.ps1" -OutputPath $capturePath -MarkCursor | Out-Null
            $result.CapturePath = $capturePath

            $crop = Get-AtGPropertyValue -Object $Point -Name "Crop"
            if ($null -ne $crop) {
                $cropPath = Join-Path $RunDirectory ($id + ".crop.png")
                & "$PSScriptRoot\Crop-AtGImage.ps1" `
                    -SourcePath $capturePath `
                    -OutputPath $cropPath `
                    -X ([int](Get-AtGPropertyValue -Object $crop -Name "X")) `
                    -Y ([int](Get-AtGPropertyValue -Object $crop -Name "Y")) `
                    -Width ([int](Get-AtGPropertyValue -Object $crop -Name "Width")) `
                    -Height ([int](Get-AtGPropertyValue -Object $crop -Name "Height")) | Out-Null
                $result.CropPath = $cropPath
            }
        }
    }
    catch {
        $result.Status = "Failed"
        $result.Error = $_.Exception.Message
    }
    finally {
        $pointStopwatch.Stop()
        $result.DurationMs = [int64]$pointStopwatch.ElapsedMilliseconds
    }

    return [pscustomobject]$result
}

if ([string]::IsNullOrWhiteSpace($ScenarioPath)) {
    $ScenarioPath = Join-Path $PSScriptRoot "..\docs\agent\black-box-scenarios.json"
}
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $PSScriptRoot "..\.tmp\runs"
}

& "$PSScriptRoot\Test-BlackBoxScenarioSchema.ps1" -ScenarioPath $ScenarioPath | Out-Null
$root = Get-Content -LiteralPath $ScenarioPath -Raw -Encoding UTF8 | ConvertFrom-Json
$scenario = Get-AtGScenarioCandidates -Root $root -Suite $Suite | Where-Object { $_.Id -eq $ScenarioId } | Select-Object -First 1
if ($null -eq $scenario) {
    throw "Scenario '$ScenarioId' was not found in suite '$Suite'."
}

if ($SkipPassed -and [string]$scenario.Status -eq "Completed" -and [bool](Get-AtGPropertyValue -Object $scenario -Name "SkipByDefault")) {
    [pscustomobject]@{
        ScenarioId = $ScenarioId
        Suite = $Suite
        Status = "Skipped"
        Reason = "Completed scenario skipped by default."
    }
    return
}

$points = @(Get-AtGPropertyValue -Object $scenario -Name "Points")
$clear = Get-AtGPropertyValue -Object $scenario -Name "ClearBeforeEachPoint"
$clearX = -1
$clearY = -1
$clearWaitMs = 150
if ($null -ne $clear) {
    $configuredClearX = Get-AtGPropertyValue -Object $clear -Name "X"
    $configuredClearY = Get-AtGPropertyValue -Object $clear -Name "Y"
    $configuredClearWaitMs = Get-AtGPropertyValue -Object $clear -Name "WaitMs"
    if ($null -ne $configuredClearX -and $null -ne $configuredClearY) {
        $clearX = [int]$configuredClearX
        $clearY = [int]$configuredClearY
    }
    if ($null -ne $configuredClearWaitMs) {
        $clearWaitMs = [int]$configuredClearWaitMs
    }
}
$planned = foreach ($point in $points) {
    [pscustomobject]@{
        Id = [string](Get-AtGPropertyValue -Object $point -Name "Id")
        Label = [string](Get-AtGPropertyValue -Object $point -Name "Label")
        Action = [string](Get-AtGPropertyValue -Object $point -Name "Action")
        X = Get-AtGPropertyValue -Object $point -Name "X"
        Y = Get-AtGPropertyValue -Object $point -Name "Y"
        WaitMs = Get-AtGPropertyValue -Object $point -Name "WaitMs"
        Discover = [bool](Get-AtGPropertyValue -Object $point -Name "Discover")
    }
}

if ($DryRun) {
    [pscustomobject]@{
        ScenarioId = $ScenarioId
        Title = [string]$scenario.Title
        Suite = $Suite
        Mode = "DryRun"
        PointCount = $planned.Count
        MissingCoordinateCount = @($planned | Where-Object { $null -eq $_.X -or $null -eq $_.Y }).Count
        PlannedPoints = $planned
    }
    return
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$safeScenarioId = ($ScenarioId -replace '[^A-Za-z0-9_.-]', '_')
$runDir = Join-Path $OutputRoot "$timestamp-$safeScenarioId"
New-Item -ItemType Directory -Force -Path $runDir | Out-Null

$runStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$results = New-Object System.Collections.Generic.List[object]
foreach ($point in $points) {
    $results.Add((Invoke-AtGPointAction -Point $point -RunDirectory $runDir -DefaultWaitMs $DefaultWaitMs -ClearX $clearX -ClearY $clearY -ClearWaitMs $clearWaitMs)) | Out-Null
}
$runStopwatch.Stop()

$capturePaths = @($results | Where-Object { $_.CropPath } | ForEach-Object { $_.CropPath })
if ($capturePaths.Count -eq 0) {
    $capturePaths = @($results | Where-Object { $_.CapturePath } | ForEach-Object { $_.CapturePath })
}

$contactSheetPath = $null
if ($capturePaths.Count -gt 0) {
    $contactSheetPath = Join-Path $runDir "contact.png"
    & "$PSScriptRoot\New-AtGContactSheet.ps1" -ImagePath $capturePaths -OutputPath $contactSheetPath | Out-Null
}

$failedCount = @($results | Where-Object { $_.Status -eq "Failed" }).Count
$skippedCount = @($results | Where-Object { $_.Status -eq "Skipped" }).Count
$clickCount = @($results | Where-Object { $_.Action -like "Click*" }).Count
$hoverCount = @($results | Where-Object { $_.Action -like "Hover*" }).Count
$screenshotCount = @($results | Where-Object { $_.CapturePath }).Count
$status = if ($failedCount -gt 0) { "Failed" } else { "Completed" }

$computerUse = New-Object psobject
$computerUse | Add-Member -NotePropertyName RequestedFirst -NotePropertyValue ([bool]$UseComputerUseFirst)
$computerUse | Add-Member -NotePropertyName Used -NotePropertyValue $false
$computerUse | Add-Member -NotePropertyName Note -NotePropertyValue "This PowerShell runner uses Win32 helpers. If computer-use capture is required, attempt it before invoking this runner and use this as fallback."

$summary = New-Object psobject
$summary | Add-Member -NotePropertyName ScenarioId -NotePropertyValue $ScenarioId
$summary | Add-Member -NotePropertyName Title -NotePropertyValue ([string]$scenario.Title)
$summary | Add-Member -NotePropertyName Suite -NotePropertyValue $Suite
$summary | Add-Member -NotePropertyName Status -NotePropertyValue $status
$summary | Add-Member -NotePropertyName StartedAtLocal -NotePropertyValue $timestamp
$summary | Add-Member -NotePropertyName DurationMs -NotePropertyValue ([int64]$runStopwatch.ElapsedMilliseconds)
$summary | Add-Member -NotePropertyName ClickCount -NotePropertyValue $clickCount
$summary | Add-Member -NotePropertyName HoverCount -NotePropertyValue $hoverCount
$summary | Add-Member -NotePropertyName ScreenshotCount -NotePropertyValue $screenshotCount
$summary | Add-Member -NotePropertyName SkippedCount -NotePropertyValue $skippedCount
$summary | Add-Member -NotePropertyName FailedCount -NotePropertyValue $failedCount
$summary | Add-Member -NotePropertyName RunDirectory -NotePropertyValue $runDir
$summary | Add-Member -NotePropertyName ContactSheetPath -NotePropertyValue $contactSheetPath
$summary | Add-Member -NotePropertyName ComputerUse -NotePropertyValue $computerUse
$summary | Add-Member -NotePropertyName Results -NotePropertyValue ([object[]]$results.ToArray())

$summaryPath = Join-Path $runDir "run-summary.json"
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8

[pscustomobject]@{
    ScenarioId = $ScenarioId
    Status = $summary.Status
    RunDirectory = $runDir
    SummaryPath = $summaryPath
    ContactSheetPath = $contactSheetPath
    DurationMs = $summary.DurationMs
    ClickCount = $summary.ClickCount
    HoverCount = $summary.HoverCount
    ScreenshotCount = $summary.ScreenshotCount
    SkippedCount = $summary.SkippedCount
    FailedCount = $summary.FailedCount
}
