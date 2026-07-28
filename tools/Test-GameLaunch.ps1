param(
    [string]$GamePath,
    [int]$WaitSeconds = 25,
    [string]$ScreenshotPath = "$PSScriptRoot\..\.tmp\game-smoke.png",
    [switch]$IncludeNewGame,
    [switch]$SkipNewGame,
    [int]$NewGameWaitSeconds = 35,
    [string]$NewGameScreenshotPath = "$PSScriptRoot\..\.tmp\game-smoke-new-game.png",
    [int]$PostNewGameReadyDelayMs = 1500,
    [string]$SmokeLockName = "Local\AtGChinesePatch.TestGameLaunch",
    [switch]$KeepRunning,
    [int]$StabilitySeconds = 4,
    [int]$StabilityPollMilliseconds = 500
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\AtGPaths.ps1"

$smokeMutex = [System.Threading.Mutex]::new($false, $SmokeLockName)
$smokeLockTaken = $false

try {
    $smokeLockTaken = $smokeMutex.WaitOne(0)
    if (!$smokeLockTaken) {
        throw "Another At the Gates smoke test is already running. Wait for it to finish before starting a new smoke test."
    }

$GamePath = Resolve-AtGGamePath $GamePath

function Get-AtGProcess {
    Get-Process | Where-Object {
        $_.ProcessName -eq "At The Gates"
    }
}

function Get-AtGNormalizedTitle {
    param([string]$Title)

    return (($Title -replace "\s+", " ").Trim())
}

$existing = @(Get-AtGProcess)
if ($existing.Count -gt 0) {
    throw "At the Gates is already running. Close it before running this smoke test."
}

$exe = Join-Path $GamePath "At The Gates.exe"
if (!(Test-Path -LiteralPath $exe)) {
    throw "Game executable not found: $exe"
}

$crashLog = Join-Path $GamePath "Logs\Crash.AtGLog"
$programLog = Join-Path $GamePath "Logs\Program.AtGLog"
$beforeCrashTime = $null
if (Test-Path -LiteralPath $crashLog) {
    $beforeCrashTime = (Get-Item -LiteralPath $crashLog).LastWriteTimeUtc
}

$eventStartTime = (Get-Date).AddSeconds(-2)
$process = Start-Process -FilePath $exe -WorkingDirectory $GamePath -PassThru
$launchWait = [System.Diagnostics.Stopwatch]::StartNew()
$windowReady = $false
$mainMenuStable = $false
$stableWindowChecks = 0
$deadline = [DateTime]::UtcNow.AddSeconds($WaitSeconds)
while ([DateTime]::UtcNow -lt $deadline) {
    $readyWindow = @(Get-AtGProcess | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1)
    if ($readyWindow.Count -gt 0) {
        $windowReady = $true
        break
    }

    if ($process.HasExited) {
        break
    }

    Start-Sleep -Milliseconds 500
}

if ($windowReady) {
    Start-Sleep -Seconds 2
}
$stabilityStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
if ($windowReady -and $StabilitySeconds -gt 0) {
    $stabilityDeadline = [DateTime]::UtcNow.AddSeconds($StabilitySeconds)
    while ([DateTime]::UtcNow -lt $stabilityDeadline) {
        try {
            $process.Refresh()
        }
        catch {
            break
        }

        if ($process.HasExited) {
            break
        }

        $visibleWindows = @(Get-AtGProcess | Where-Object { $_.MainWindowHandle -ne 0 })
        $hasNormalWindow = @($visibleWindows | Where-Object {
            $title = Get-AtGNormalizedTitle $_.MainWindowTitle
            $title -notlike "*HE'S DEAD*" -and $title -notlike "*Error Loading User Settings*"
        }).Count -gt 0

        if (!$hasNormalWindow) {
            break
        }

        $stableWindowChecks++
        Start-Sleep -Milliseconds $StabilityPollMilliseconds
    }

    $mainMenuStable = $stableWindowChecks -gt 0 -and !$process.HasExited -and ([DateTime]::UtcNow -ge $stabilityDeadline)
}
$stabilityStopwatch.Stop()
$launchWait.Stop()

$windows = @(Get-AtGProcess | Select-Object Id, ProcessName, MainWindowTitle)
$crashUpdated = $false
$crashSummary = ""
$crashDialogSeen = $false
$shouldRunNewGame = [bool]$IncludeNewGame -and !$SkipNewGame
$newGameAttempted = $false
$newGameClickCount = 0
$newGameSmokeSeconds = 0
$newGameScreenshot = $null
$newGameReady = $false
$newGameReadyMarker = ""
$processExitedBeforeCleanup = $false
$processExitCode = $null
$processKeptRunning = $false
$windowsErrorEvents = @()
$settingsErrorSeen = @($windows | Where-Object { $_.MainWindowTitle -like "*Error Loading User Settings*" }).Count -gt 0

if (Test-Path -LiteralPath $crashLog) {
    $afterCrashTime = (Get-Item -LiteralPath $crashLog).LastWriteTimeUtc
    $crashUpdated = ($beforeCrashTime -eq $null -or $afterCrashTime -gt $beforeCrashTime)
    if ($crashUpdated) {
        $crashSummary = (Get-Content -LiteralPath $crashLog -Raw -Encoding UTF8) -replace "\s+", " "
    }
}

function Update-AtGCrashStatus {
    $script:windows = @(Get-AtGProcess | Select-Object Id, ProcessName, MainWindowTitle)
    $script:crashDialogSeen = @($script:windows | Where-Object {
        (Get-AtGNormalizedTitle $_.MainWindowTitle) -like "*HE'S DEAD*"
    }).Count -gt 0
    $script:settingsErrorSeen = @($script:windows | Where-Object { $_.MainWindowTitle -like "*Error Loading User Settings*" }).Count -gt 0
    $script:crashUpdated = $false
    $script:crashSummary = ""

    if (Test-Path -LiteralPath $crashLog) {
        $afterCrashTime = (Get-Item -LiteralPath $crashLog).LastWriteTimeUtc
        $script:crashUpdated = ($beforeCrashTime -eq $null -or $afterCrashTime -gt $beforeCrashTime)
        if ($script:crashUpdated) {
            $script:crashSummary = (Get-Content -LiteralPath $crashLog -Raw -Encoding UTF8) -replace "\s+", " "
        }
    }
}

function Get-AtGNewGameReadyMarker {
    if (!(Test-Path -LiteralPath $programLog)) {
        return ""
    }

    try {
        $tail = (Get-Content -LiteralPath $programLog -Tail 60 -Encoding UTF8) -join "`n"
        if ($tail -match "Controller\s+- Giving Control to Human") {
            return "Controller - Giving Control to Human"
        }

        return ""
    }
    catch {
        return ""
    }
}

function Get-AtGWindowsErrorEvents {
    try {
        $events = Get-WinEvent -FilterHashtable @{
            LogName = "Application"
            StartTime = $eventStartTime
        } -ErrorAction SilentlyContinue
    }
    catch {
        return @()
    }

    foreach ($event in @($events)) {
        if ($event.ProviderName -notmatch "Application Error|\.NET Runtime|Windows Error Reporting") {
            continue
        }

        if ($event.Message -notmatch "At The Gates\.exe|AtTheGates|At the Gates") {
            continue
        }

        $message = ($event.Message -replace "\s+", " ").Trim()
        if ($message.Length -gt 700) {
            $message = $message.Substring(0, 700)
        }

        [pscustomobject]@{
            TimeCreated = $event.TimeCreated
            ProviderName = $event.ProviderName
            Id = $event.Id
            Level = $event.LevelDisplayName
            Message = $message
        }
    }
}

$screenshotDir = Split-Path -Parent $ScreenshotPath
if ($screenshotDir) {
    New-Item -ItemType Directory -Force -Path $screenshotDir | Out-Null
}
if (Test-Path -LiteralPath $ScreenshotPath) {
    Remove-Item -LiteralPath $ScreenshotPath -Force
}

try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    Add-Type @"
using System;
using System.Runtime.InteropServices;

public static class AtGWindow {
    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();

    [DllImport("user32.dll")]
    public static extern bool SetProcessDpiAwarenessContext(IntPtr dpiContext);

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

}
"@

    [AtGWindow]::SetProcessDpiAwarenessContext([IntPtr]::new(-4)) | Out-Null
    [AtGWindow]::SetProcessDPIAware() | Out-Null

    $mainWindow = @(Get-AtGProcess | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1)
    if ($mainWindow.Count -gt 0) {
        $handle = $mainWindow[0].MainWindowHandle
        [AtGWindow]::SetForegroundWindow($handle) | Out-Null
        Start-Sleep -Seconds 1

        $rect = New-Object AtGWindow+RECT
        if ([AtGWindow]::GetWindowRect($handle, [ref]$rect)) {
            $width = $rect.Right - $rect.Left
            $height = $rect.Bottom - $rect.Top
            if ($width -gt 0 -and $height -gt 0) {
                $bitmap = New-Object System.Drawing.Bitmap $width, $height
                $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
                $graphics.CopyFromScreen(
                    [System.Drawing.Point]::new($rect.Left, $rect.Top),
                    [System.Drawing.Point]::Empty,
                    [System.Drawing.Size]::new($width, $height)
                )
                $bitmap.Save($ScreenshotPath, [System.Drawing.Imaging.ImageFormat]::Png)
                $graphics.Dispose()
                $bitmap.Dispose()
                $bitmap = $null
                $graphics = $null
            }
        }
    }

    if (!(Test-Path -LiteralPath $ScreenshotPath)) {
        $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
        $bitmap = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        $graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
        $bitmap.Save($ScreenshotPath, [System.Drawing.Imaging.ImageFormat]::Png)
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}
catch {
    Write-Warning "Screenshot failed: $($_.Exception.Message)"
}

Update-AtGCrashStatus

if ($shouldRunNewGame -and $windowReady -and !$process.HasExited -and !$crashDialogSeen -and !$settingsErrorSeen) {
    $newGameAttempted = $true
    $newGameStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $newGameSteps = @(
        @{ Name = "New Game"; X = 1280; Y = 714; WaitMs = 1200 },
        @{ Name = "Default Tribe"; X = 1280; Y = 526; WaitMs = 1200 },
        @{ Name = "Normal Difficulty"; X = 1280; Y = 654; WaitMs = 500 }
    )

    foreach ($step in $newGameSteps) {
        if ($process.HasExited) {
            break
        }

        Update-AtGCrashStatus
        if ($crashDialogSeen -or $crashUpdated) {
            break
        }

        & "$PSScriptRoot\Click-AtGWindow.ps1" -X ([int]$step.X) -Y ([int]$step.Y) | Out-Null
        $newGameClickCount++
        Start-Sleep -Milliseconds ([int]$step.WaitMs)
    }

    $newGameDeadline = [DateTime]::UtcNow.AddSeconds($NewGameWaitSeconds)
    while ([DateTime]::UtcNow -lt $newGameDeadline) {
        if ($process.HasExited) {
            break
        }

        Update-AtGCrashStatus
        if ($crashDialogSeen -or $crashUpdated) {
            break
        }

        $readyMarker = Get-AtGNewGameReadyMarker
        if (![string]::IsNullOrWhiteSpace($readyMarker)) {
            $newGameReady = $true
            $newGameReadyMarker = $readyMarker
            break
        }

        Start-Sleep -Milliseconds 500
    }
    $newGameStopwatch.Stop()
    $newGameSmokeSeconds = [Math]::Round($newGameStopwatch.Elapsed.TotalSeconds, 2)

    if ($newGameReady -and $PostNewGameReadyDelayMs -gt 0 -and !$process.HasExited) {
        Start-Sleep -Milliseconds $PostNewGameReadyDelayMs
        Update-AtGCrashStatus
    }

    $newGameScreenshotDir = Split-Path -Parent $NewGameScreenshotPath
    if ($newGameScreenshotDir) {
        New-Item -ItemType Directory -Force -Path $newGameScreenshotDir | Out-Null
    }

    try {
        & "$PSScriptRoot\Capture-AtGWindow.ps1" -OutputPath $NewGameScreenshotPath | Out-Null
        $newGameScreenshot = (Resolve-Path -LiteralPath $NewGameScreenshotPath -ErrorAction SilentlyContinue).Path
    }
    catch {
        Write-Warning "New-game screenshot failed: $($_.Exception.Message)"
    }
}

Update-AtGCrashStatus

$processExitedBeforeCleanup = $true
try {
    $process.Refresh()
    $processExitedBeforeCleanup = $process.HasExited
    if ($processExitedBeforeCleanup) {
        $processExitCode = $process.ExitCode
    }
}
catch {
    $processExitedBeforeCleanup = $true
}

$canKeepRunning = $KeepRunning -and $windowReady -and $mainMenuStable -and !$processExitedBeforeCleanup -and !$crashDialogSeen -and !$crashUpdated -and !$settingsErrorSeen
if ($canKeepRunning) {
    $processKeptRunning = $true
}
else {
    foreach ($atg in @(Get-AtGProcess)) {
        $null = $atg.CloseMainWindow()
    }
    Start-Sleep -Seconds 5
    foreach ($atg in @(Get-AtGProcess)) {
        Stop-Process -Id $atg.Id -Force
    }
}

$programTail = ""
if (Test-Path -LiteralPath $programLog) {
    $programTail = ((Get-Content -LiteralPath $programLog -Tail 30 -Encoding UTF8) -join "`n")
}
if ($programTail -match "Error loading Settings\.xml|Error Loading User Settings") {
    $settingsErrorSeen = $true
}

$windowsErrorEvents = @(Get-AtGWindowsErrorEvents)
$failureReasons = New-Object System.Collections.Generic.List[string]
if (!$windowReady) {
    $failureReasons.Add("Game window did not become ready.")
}
if ($windowReady -and !$mainMenuStable) {
    $failureReasons.Add("Game window did not remain stable for $StabilitySeconds seconds.")
}
if ($processExitedBeforeCleanup) {
    if ($null -ne $processExitCode) {
        $failureReasons.Add("Game process exited before smoke-test cleanup. ExitCode=$processExitCode.")
    }
    else {
        $failureReasons.Add("Game process exited before smoke-test cleanup.")
    }
}
if ($crashDialogSeen) {
    $failureReasons.Add("Crash dialog was visible.")
}
if ($crashUpdated) {
    $failureReasons.Add("Crash.AtGLog was updated.")
}
if ($settingsErrorSeen) {
    $failureReasons.Add("Error Loading User Settings was detected.")
}
if ($shouldRunNewGame -and (!$newGameAttempted -or !$newGameReady)) {
    $failureReasons.Add("New-game smoke did not reach the main loop.")
}
if ($windowsErrorEvents.Count -gt 0) {
    $failureReasons.Add("Windows Application Error/.NET/WER event was recorded.")
}

[pscustomobject]@{
    StartedProcessId = $process.Id
    WindowReady = $windowReady
    StartupWaitSeconds = [Math]::Round($launchWait.Elapsed.TotalSeconds, 2)
    MainMenuStable = $mainMenuStable
    StableWindowChecks = $stableWindowChecks
    StabilitySeconds = [Math]::Round($stabilityStopwatch.Elapsed.TotalSeconds, 2)
    ProcessExitedBeforeCleanup = $processExitedBeforeCleanup
    ProcessExitCode = $processExitCode
    ProcessKeptRunning = $processKeptRunning
    IncludeNewGame = $shouldRunNewGame
    NewGameAttempted = $newGameAttempted
    NewGameClickCount = $newGameClickCount
    NewGameReady = $newGameReady
    NewGameReadyMarker = $newGameReadyMarker
    NewGameSmokeSeconds = $newGameSmokeSeconds
    CrashLogUpdated = $crashUpdated
    CrashDialogSeen = $crashDialogSeen
    SettingsErrorSeen = $settingsErrorSeen
    WindowsErrorSeen = ($windowsErrorEvents.Count -gt 0)
    WindowsErrorEvents = $windowsErrorEvents
    FailureReason = ($failureReasons.ToArray() -join " ")
    WindowsSeen = $windows
    Screenshot = (Resolve-Path -LiteralPath $ScreenshotPath -ErrorAction SilentlyContinue).Path
    NewGameScreenshot = $newGameScreenshot
    ProgramLogTail = $programTail
    CrashSummary = $crashSummary
}
}
finally {
    if ($smokeLockTaken) {
        $smokeMutex.ReleaseMutex()
    }
    $smokeMutex.Dispose()
}
