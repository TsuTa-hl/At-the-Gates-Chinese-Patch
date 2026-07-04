param(
    [Parameter(Mandatory = $true)]
    [string]$BatchJson,

    [string]$GamePath,

    [int]$MaxTestRuns = 16,

    [switch]$PlanOnly
)

$ErrorActionPreference = "Stop"

function Read-AtGJsonArray {
    param([string]$Path)

    if (!(Test-Path -LiteralPath $Path -PathType Leaf)) {
        return @()
    }

    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return @()
    }

    return @($raw | ConvertFrom-Json | ForEach-Object { $_ })
}

function ConvertTo-AtGJsonArray {
    param([object[]]$Items)

    $items = @($Items)
    if ($items.Count -eq 0) {
        return "[]`n"
    }

    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($item in $items) {
        $json = ($item | ConvertTo-Json -Depth 12) -replace "`r`n", "`n"
        $json = [regex]::Replace($json, "[ \t]+(?=`n|$)", "")
        $parts.Add($json)
    }

    return "[`n$([string]::Join(",`n", $parts))`n]`n"
}

function Write-AtGJsonArray {
    param(
        [string]$Path,
        [object[]]$Items
    )

    $directory = Split-Path -Parent $Path
    if ($directory) {
        New-Item -ItemType Directory -Force -Path $directory | Out-Null
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText((Resolve-Path -LiteralPath $directory).Path + "\" + (Split-Path -Leaf $Path), (ConvertTo-AtGJsonArray -Items $Items), $utf8NoBom)
}

function Get-AtGEntryKey {
    param([object]$Entry)
    return "$($Entry.MethodToken)|$($Entry.ILOffset)"
}

function ConvertTo-AtGRewriteEntry {
    param([object]$Entry)

    $out = [ordered]@{
        Original = [string]$Entry.Original
        Translation = [string]$Entry.Translation
        MethodToken = [string]$Entry.MethodToken
        ILOffset = [int]$Entry.ILOffset
    }

    foreach ($name in @("StringToken", "TypeFullName", "MethodName", "Safety", "Note", "EvidenceScenario")) {
        if ($null -ne $Entry.PSObject.Properties[$name] -and $null -ne $Entry.$name) {
            $out[$name] = $Entry.$name
        }
    }

    return [pscustomobject]$out
}

function Get-AtGTrialBatchSafetyError {
    param([object]$Entry)

    $original = [string]$Entry.Original
    $translation = [string]$Entry.Translation
    $typeFullName = [string]$Entry.TypeFullName
    $methodName = [string]$Entry.MethodName
    $replacementChar = [string][char]0xfffd

    if ($original.Contains($replacementChar) -or $translation.Contains($replacementChar)) {
        return "Entry contains Unicode replacement characters, which indicates mojibake or lossy decoding."
    }

    if ($typeFullName -eq "AtTheGatesCommon.ns_Text.Text" -and $methodName -eq "ConvertTags") {
        return "Entries from AtTheGatesCommon.ns_Text.Text.ConvertTags are parser tag definitions, not safe trial localization display text."
    }

    if ($original -match '^\[[A-Za-z][A-Za-z0-9 _\-\|:]*\]$') {
        return "Bracket-only parser-like tokens are not safe trial localization targets."
    }

    return ""
}

function Invoke-AtGTrialCommand {
    param(
        [string]$Name,
        [scriptblock]$ScriptBlock,
        [string]$LogPath
    )

    try {
        & $ScriptBlock *>&1 | Tee-Object -FilePath $LogPath | Out-Null
        return $true
    }
    catch {
        $_ | Out-String | Add-Content -LiteralPath $LogPath -Encoding UTF8
        return $false
    }
}

$batchPath = (Resolve-Path -LiteralPath $BatchJson).Path
$batch = @(Read-AtGJsonArray -Path $batchPath)
if ($batch.Count -eq 0) {
    throw "Trial localization batch is empty: $batchPath"
}

$validAssemblies = @("UI", "Common", "Game", "ElfTools")
foreach ($entry in $batch) {
    foreach ($required in @("Assembly", "Original", "Translation", "MethodToken", "ILOffset")) {
        if ($null -eq $entry.PSObject.Properties[$required] -or [string]::IsNullOrWhiteSpace([string]$entry.$required)) {
            throw "Batch entry is missing required field '$required': $($entry | ConvertTo-Json -Depth 6)"
        }
    }

    if ($validAssemblies -notcontains [string]$entry.Assembly) {
        throw "Unsupported Assembly '$($entry.Assembly)'. Expected one of: $($validAssemblies -join ', ')"
    }

    $safetyError = Get-AtGTrialBatchSafetyError -Entry $entry
    if (![string]::IsNullOrWhiteSpace($safetyError)) {
        throw "Unsafe trial localization batch entry: $safetyError Entry: $($entry | ConvertTo-Json -Depth 6)"
    }
}

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$runId = Get-Date -Format "yyyyMMdd-HHmmss"
$runRoot = Join-Path $repoRoot ".tmp\trial-localization\$runId"
$logRoot = Join-Path $runRoot "logs"
New-Item -ItemType Directory -Force -Path $logRoot | Out-Null

$mapPaths = @{
    UI = Join-Path $repoRoot "translations\hardcoded-ui-il-rewrite.json"
    Common = Join-Path $repoRoot "translations\hardcoded-common-il-rewrite.json"
    Game = Join-Path $repoRoot "translations\hardcoded-game-il-rewrite.json"
    ElfTools = Join-Path $repoRoot "translations\hardcoded-elftools-il-rewrite.json"
}
$activeRunPath = Join-Path $repoRoot ".tmp\trial-localization\active-run.json"

function Test-AtGActiveTrialProcess {
    param([object]$State)

    if ($null -eq $State.PSObject.Properties["ProcessId"]) {
        return $false
    }

    $processId = [int]$State.ProcessId
    $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
    if ($null -eq $process) {
        return $false
    }

    if ($null -eq $State.PSObject.Properties["ProcessStartTime"] -or [string]::IsNullOrWhiteSpace([string]$State.ProcessStartTime)) {
        return $true
    }

    try {
        $expected = [DateTime]::Parse([string]$State.ProcessStartTime).ToUniversalTime()
        $actual = $process.StartTime.ToUniversalTime()
        return ([Math]::Abs(($actual - $expected).TotalSeconds) -lt 2)
    }
    catch {
        return $true
    }
}

function Restore-AtGIncompleteTrialRun {
    if (!(Test-Path -LiteralPath $activeRunPath -PathType Leaf)) {
        return
    }

    $state = Get-Content -LiteralPath $activeRunPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (Test-AtGActiveTrialProcess -State $state) {
        throw "Another trial localization batch appears to be running. Active run: $($state.RunRoot)"
    }

    foreach ($map in @($state.Maps)) {
        if ([string]::IsNullOrWhiteSpace([string]$map.MapPath) -or [string]::IsNullOrWhiteSpace([string]$map.BaselineBackup)) {
            throw "Incomplete trial active-run manifest has an invalid map entry: $($map | ConvertTo-Json -Depth 5)"
        }

        if (!(Test-Path -LiteralPath $map.BaselineBackup -PathType Leaf)) {
            throw "Incomplete trial baseline backup is missing: $($map.BaselineBackup)"
        }

        Copy-Item -LiteralPath $map.BaselineBackup -Destination $map.MapPath -Force
    }

    $recoveredPath = Join-Path (Split-Path -Parent $activeRunPath) ("recovered-active-run-$runId.json")
    Move-Item -LiteralPath $activeRunPath -Destination $recoveredPath -Force
}

Restore-AtGIncompleteTrialRun

$baseline = @{}
$baselineKeys = @{}
foreach ($assembly in $validAssemblies) {
    $items = @(Read-AtGJsonArray -Path $mapPaths[$assembly])
    $baseline[$assembly] = $items
    $keys = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($item in $items) {
        [void]$keys.Add((Get-AtGEntryKey -Entry $item))
    }
    $baselineKeys[$assembly] = $keys
}

$newBatch = @($batch | Where-Object { -not $baselineKeys[[string]$_.Assembly].Contains((Get-AtGEntryKey -Entry $_)) })

if ($PlanOnly) {
    [pscustomobject]@{
        RunRoot = $runRoot
        BatchPath = $batchPath
        InputEntries = $batch.Count
        AlreadyMappedEntries = $batch.Count - $newBatch.Count
        TrialEntries = $newBatch.Count
        MaxTestRuns = $MaxTestRuns
    }
    return
}

if ($newBatch.Count -eq 0) {
    Write-AtGJsonArray -Path (Join-Path $runRoot "accepted.json") -Items @()
    Write-AtGJsonArray -Path (Join-Path $runRoot "rejected.json") -Items @()
    [pscustomobject]@{
        RunRoot = $runRoot
        TestRuns = 0
        Accepted = 0
        Rejected = 0
        Message = "All batch entries were already mapped."
    }
    return
}

$activeMaps = New-Object System.Collections.Generic.List[object]
foreach ($assembly in $validAssemblies) {
    $backupPath = Join-Path $runRoot "baseline-$assembly.json"
    Copy-Item -LiteralPath $mapPaths[$assembly] -Destination $backupPath -Force
    $activeMaps.Add([pscustomobject]@{
        Assembly = $assembly
        MapPath = $mapPaths[$assembly]
        BaselineBackup = $backupPath
    })
}
$currentProcess = Get-Process -Id $PID
$activeState = [pscustomobject]@{
    ProcessId = $PID
    ProcessStartTime = $currentProcess.StartTime.ToUniversalTime().ToString("o")
    RunRoot = $runRoot
    StartedAt = (Get-Date).ToUniversalTime().ToString("o")
    Maps = $activeMaps.ToArray()
}
$activeState | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $activeRunPath -Encoding UTF8

Write-Host ("Trial localization will run up to {0} sequential smoke tests. A failing batch is bisected, so one batch command can intentionally launch the game multiple times, but never concurrently." -f $MaxTestRuns)

function Restore-AtGTrialBaselineMaps {
    foreach ($map in $activeMaps.ToArray()) {
        if (!(Test-Path -LiteralPath $map.BaselineBackup -PathType Leaf)) {
            throw "Trial baseline backup is missing: $($map.BaselineBackup)"
        }

        Copy-Item -LiteralPath $map.BaselineBackup -Destination $map.MapPath -Force
    }
}

function Move-AtGTrialEvidenceIfPresent {
    param(
        [string]$SourcePath,
        [string]$DestinationPath
    )

    if (Test-Path -LiteralPath $SourcePath -PathType Leaf) {
        Move-Item -LiteralPath $SourcePath -Destination $DestinationPath -Force
    }
}

function Stop-AtGInvalidTrialRun {
    param(
        [string]$Reason,
        [string]$StageRoot
    )

    Restore-AtGTrialBaselineMaps

    $acceptedPath = Join-Path $runRoot "accepted.json"
    $rejectedPath = Join-Path $runRoot "rejected.json"
    Write-AtGTrialResults
    Move-AtGTrialEvidenceIfPresent -SourcePath $acceptedPath -DestinationPath (Join-Path $runRoot "accepted.invalid-smoke.json")
    Move-AtGTrialEvidenceIfPresent -SourcePath $rejectedPath -DestinationPath (Join-Path $runRoot "rejected.invalid-smoke.json")

    $invalid = [pscustomobject]@{
        Reason = $Reason
        StageRoot = $StageRoot
        InputEntries = $batch.Count
        TrialEntries = $newBatch.Count
        TestRuns = $testRuns
        AcceptedBeforeInvalidation = $accepted.Count
        RejectedBeforeInvalidation = $rejected.Count
        WrittenAt = (Get-Date).ToUniversalTime().ToString("o")
    }
    $invalid | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $runRoot "invalid.json") -Encoding UTF8
    throw $Reason
}

function Test-AtGAnyTrialStageFailed {
    foreach ($result in $results.ToArray()) {
        if (!$result.Passed) {
            return $true
        }
    }

    return $false
}

function Write-AtGTrialResults {
    Write-AtGJsonArray -Path (Join-Path $runRoot "results.json") -Items $results.ToArray()
}

$accepted = New-Object System.Collections.Generic.List[object]
$rejected = New-Object System.Collections.Generic.List[object]
$testRuns = 0
$results = New-Object System.Collections.Generic.List[object]

function Write-TrialMaps {
    param([object[]]$TrialEntries)

    $byAssembly = @{
        UI = New-Object System.Collections.Generic.List[object]
        Common = New-Object System.Collections.Generic.List[object]
        Game = New-Object System.Collections.Generic.List[object]
        ElfTools = New-Object System.Collections.Generic.List[object]
    }

    foreach ($entry in $accepted.ToArray()) {
        $byAssembly[[string]$entry.Assembly].Add((ConvertTo-AtGRewriteEntry -Entry $entry))
    }

    foreach ($entry in @($TrialEntries)) {
        $byAssembly[[string]$entry.Assembly].Add((ConvertTo-AtGRewriteEntry -Entry $entry))
    }

    foreach ($assembly in $validAssemblies) {
        $combined = New-Object System.Collections.Generic.List[object]
        foreach ($entry in @($baseline[$assembly])) {
            $combined.Add($entry)
        }
        foreach ($entry in $byAssembly[$assembly].ToArray()) {
            $combined.Add($entry)
        }
        Write-AtGJsonArray -Path $mapPaths[$assembly] -Items $combined.ToArray()
    }
}

function Test-TrialEntries {
    param(
        [object[]]$Entries,
        [string]$Label
    )

    if ($script:testRuns -ge $MaxTestRuns) {
        throw "Trial localization exceeded MaxTestRuns=$MaxTestRuns."
    }

    $script:testRuns++
    $runLabel = "{0:D2}-{1}" -f $script:testRuns, $Label
    Write-Host ("Trial smoke {0}/{1}: {2} ({3} entries)" -f $script:testRuns, $MaxTestRuns, $Label, @($Entries).Count)
    $stageRoot = Join-Path $logRoot $runLabel
    New-Item -ItemType Directory -Force -Path $stageRoot | Out-Null

    Write-TrialMaps -TrialEntries $Entries

    Stop-Process -Name "At The Gates" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 300
    $buildOk = Invoke-AtGTrialCommand -Name "build" -LogPath (Join-Path $stageRoot "build.log") -ScriptBlock {
        & "$PSScriptRoot\Build-Patch.ps1"
    }
    if (!$buildOk) {
        Stop-Process -Name "At The Gates" -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
        $buildOk = Invoke-AtGTrialCommand -Name "build-retry" -LogPath (Join-Path $stageRoot "build-retry.log") -ScriptBlock {
            & "$PSScriptRoot\Build-Patch.ps1"
        }
    }
    if (!$buildOk) {
        $results.Add([pscustomobject]@{ Label = $Label; Count = @($Entries).Count; Passed = $false; Stage = "build"; Log = $stageRoot })
        return $false
    }

    $installOk = Invoke-AtGTrialCommand -Name "install" -LogPath (Join-Path $stageRoot "install.log") -ScriptBlock {
        if ([string]::IsNullOrWhiteSpace($GamePath)) {
            & (Join-Path $repoRoot "Install-ChinesePatch.ps1")
        }
        else {
            & (Join-Path $repoRoot "Install-ChinesePatch.ps1") -GamePath $GamePath
        }
    }
    if (!$installOk) {
        $results.Add([pscustomobject]@{ Label = $Label; Count = @($Entries).Count; Passed = $false; Stage = "install"; Log = $stageRoot })
        return $false
    }

    $smokeLog = Join-Path $stageRoot "smoke.log"
    $smokeJson = Join-Path $stageRoot "smoke.json"
    try {
        $smoke = if ([string]::IsNullOrWhiteSpace($GamePath)) {
            & "$PSScriptRoot\Test-GameLaunch.ps1" -IncludeNewGame -ScreenshotPath (Join-Path $stageRoot "smoke-main.png") -NewGameScreenshotPath (Join-Path $stageRoot "smoke-new-game.png")
        }
        else {
            & "$PSScriptRoot\Test-GameLaunch.ps1" -IncludeNewGame -GamePath $GamePath -ScreenshotPath (Join-Path $stageRoot "smoke-main.png") -NewGameScreenshotPath (Join-Path $stageRoot "smoke-new-game.png")
        }
        $smoke | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $smokeJson -Encoding UTF8
        $smoke | Format-List | Out-String | Set-Content -LiteralPath $smokeLog -Encoding UTF8

        $passed = ($smoke.WindowReady -and
            !$smoke.ProcessExitedBeforeCleanup -and
            $smoke.NewGameAttempted -and
            $smoke.NewGameReady -and
            !$smoke.CrashLogUpdated -and
            !$smoke.CrashDialogSeen -and
            !$smoke.WindowsErrorSeen)
        $results.Add([pscustomobject]@{
            Label = $Label
            Count = @($Entries).Count
            Passed = $passed
            Stage = if ($passed) { "smoke" } else { "smoke-failed" }
            Log = $stageRoot
        })
        return $passed
    }
    catch {
        $_ | Out-String | Set-Content -LiteralPath $smokeLog -Encoding UTF8
        $results.Add([pscustomobject]@{ Label = $Label; Count = @($Entries).Count; Passed = $false; Stage = "smoke-error"; Log = $stageRoot })
        return $false
    }
    finally {
        Stop-Process -Name "At The Gates" -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-TrialBisect {
    param(
        [object[]]$Entries,
        [string]$Label
    )

    $entries = @($Entries)
    if ($entries.Count -eq 0) {
        return
    }

    if (Test-TrialEntries -Entries $entries -Label $Label) {
        foreach ($entry in $entries) {
            $accepted.Add($entry)
        }
        return
    }

    if ($entries.Count -eq 1) {
        $rejected.Add($entries[0])
        return
    }

    $mid = [int][Math]::Floor($entries.Count / 2)
    Invoke-TrialBisect -Entries @($entries[0..($mid - 1)]) -Label "$Label-a"
    Invoke-TrialBisect -Entries @($entries[$mid..($entries.Count - 1)]) -Label "$Label-b"
}

try {
    Invoke-TrialBisect -Entries $newBatch -Label "batch"
}
finally {
    Write-TrialMaps -TrialEntries @()
    Write-AtGJsonArray -Path (Join-Path $runRoot "accepted.json") -Items $accepted.ToArray()
    Write-AtGJsonArray -Path (Join-Path $runRoot "rejected.json") -Items $rejected.ToArray()
    Write-AtGTrialResults
    Remove-Item -LiteralPath $activeRunPath -Force -ErrorAction SilentlyContinue
}

$needsFinalAccepted = ($rejected.Count -gt 0) -or (Test-AtGAnyTrialStageFailed)
if ($needsFinalAccepted) {
    $finalRoot = Join-Path $logRoot "final-accepted"
    New-Item -ItemType Directory -Force -Path $finalRoot | Out-Null
    $FinalAcceptedPassed = Test-TrialEntries -Entries @() -Label "final-accepted"
    if (!$FinalAcceptedPassed) {
        Stop-AtGInvalidTrialRun -Reason "Final accepted-only smoke failed after bisection; treating this as trial infrastructure failure, not unsafe text evidence." -StageRoot $finalRoot
    }
    Write-AtGTrialResults
}

[pscustomobject]@{
    RunRoot = $runRoot
    InputEntries = $batch.Count
    TrialEntries = $newBatch.Count
    TestRuns = $testRuns
    Accepted = $accepted.Count
    Rejected = $rejected.Count
    AcceptedPath = Join-Path $runRoot "accepted.json"
    RejectedPath = Join-Path $runRoot "rejected.json"
    ResultsPath = Join-Path $runRoot "results.json"
}
