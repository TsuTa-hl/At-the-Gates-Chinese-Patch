param(
    [string]$GamePath,
    [int]$WaitSeconds = 25,
    [string]$ScreenshotPath = "$PSScriptRoot\..\.tmp\game-smoke.png"
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\AtGPaths.ps1"

$GamePath = Resolve-AtGGamePath $GamePath

function Get-AtGProcess {
    Get-Process | Where-Object {
        $_.ProcessName -eq "At The Gates" -or
        $_.MainWindowTitle -like "*At the Gates*" -or
        $_.MainWindowTitle -like "*HE'S DEAD*"
    }
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
$beforeCrashTime = $null
if (Test-Path -LiteralPath $crashLog) {
    $beforeCrashTime = (Get-Item -LiteralPath $crashLog).LastWriteTimeUtc
}

$process = Start-Process -FilePath $exe -WorkingDirectory $GamePath -PassThru
$launchWait = [System.Diagnostics.Stopwatch]::StartNew()
$windowReady = $false
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
$launchWait.Stop()

$windows = @(Get-AtGProcess | Select-Object Id, ProcessName, MainWindowTitle)
$crashUpdated = $false
$crashSummary = ""

if (Test-Path -LiteralPath $crashLog) {
    $afterCrashTime = (Get-Item -LiteralPath $crashLog).LastWriteTimeUtc
    $crashUpdated = ($beforeCrashTime -eq $null -or $afterCrashTime -gt $beforeCrashTime)
    if ($crashUpdated) {
        $crashSummary = (Get-Content -LiteralPath $crashLog -Raw -Encoding UTF8) -replace "\s+", " "
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
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

    [DllImport("user32.dll")]
    public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
}
"@

    [AtGWindow]::SetProcessDpiAwarenessContext([IntPtr]::new(-4)) | Out-Null
    [AtGWindow]::SetProcessDPIAware() | Out-Null

    $mainWindow = @(Get-AtGProcess | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1)
    if ($mainWindow.Count -gt 0) {
        $handle = $mainWindow[0].MainWindowHandle
        $flags = 0x0001 -bor 0x0002 -bor 0x0040
        [AtGWindow]::ShowWindow($handle, 9) | Out-Null
        [AtGWindow]::SetWindowPos($handle, [IntPtr]::new(-1), 0, 0, 0, 0, $flags) | Out-Null
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
        [AtGWindow]::SetWindowPos($handle, [IntPtr]::new(-2), 0, 0, 0, 0, $flags) | Out-Null
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

foreach ($atg in @(Get-AtGProcess)) {
    $null = $atg.CloseMainWindow()
}
Start-Sleep -Seconds 5
foreach ($atg in @(Get-AtGProcess)) {
    Stop-Process -Id $atg.Id -Force
}

$programLog = Join-Path $GamePath "Logs\Program.AtGLog"
$programTail = ""
if (Test-Path -LiteralPath $programLog) {
    $programTail = ((Get-Content -LiteralPath $programLog -Tail 30 -Encoding UTF8) -join "`n")
}

[pscustomobject]@{
    StartedProcessId = $process.Id
    WindowReady = $windowReady
    StartupWaitSeconds = [Math]::Round($launchWait.Elapsed.TotalSeconds, 2)
    CrashLogUpdated = $crashUpdated
    WindowsSeen = $windows
    Screenshot = (Resolve-Path -LiteralPath $ScreenshotPath -ErrorAction SilentlyContinue).Path
    ProgramLogTail = $programTail
    CrashSummary = $crashSummary
}
