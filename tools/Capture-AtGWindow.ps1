param(
    [string]$OutputPath = "$PSScriptRoot\..\.tmp\atg-window.png",
    [switch]$MarkCursor
)

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\Get-AtGWindow.ps1"
$window = Get-AtGWindow

$screenshotDir = Split-Path -Parent $OutputPath
if ($screenshotDir) {
    New-Item -ItemType Directory -Force -Path $screenshotDir | Out-Null
}
if (Test-Path -LiteralPath $OutputPath) {
    Remove-Item -LiteralPath $OutputPath -Force
}

Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;

public static class AtGCaptureWindow {
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
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

    [StructLayout(LayoutKind.Sequential)]
    public struct POINT {
        public int X;
        public int Y;
    }

    [DllImport("user32.dll")]
    public static extern bool GetCursorPos(out POINT lpPoint);
}
"@

[AtGCaptureWindow]::SetProcessDpiAwarenessContext([IntPtr]::new(-4)) | Out-Null
[AtGCaptureWindow]::SetProcessDPIAware() | Out-Null

$rect = New-Object AtGCaptureWindow+RECT
if (![AtGCaptureWindow]::GetWindowRect($window.Handle, [ref]$rect)) {
    throw "Failed to read At the Gates window rectangle."
}

$width = $rect.Right - $rect.Left
$height = $rect.Bottom - $rect.Top
if ($width -le 0 -or $height -le 0) {
    throw "At the Gates window rectangle is empty."
}

$bitmap = New-Object System.Drawing.Bitmap $width, $height
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.CopyFromScreen(
    [System.Drawing.Point]::new($rect.Left, $rect.Top),
    [System.Drawing.Point]::Empty,
    [System.Drawing.Size]::new($width, $height)
)
if ($MarkCursor) {
    $cursor = New-Object AtGCaptureWindow+POINT
    if ([AtGCaptureWindow]::GetCursorPos([ref]$cursor)) {
        $cursorX = $cursor.X - $rect.Left
        $cursorY = $cursor.Y - $rect.Top
        $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::Red), 3
        $graphics.DrawLine($pen, $cursorX - 14, $cursorY, $cursorX + 14, $cursorY)
        $graphics.DrawLine($pen, $cursorX, $cursorY - 14, $cursorX, $cursorY + 14)
        $graphics.DrawEllipse($pen, $cursorX - 8, $cursorY - 8, 16, 16)
        $pen.Dispose()
    }
}
$bitmap.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
$graphics.Dispose()
$bitmap.Dispose()

[pscustomobject]@{
    ProcessId = $window.ProcessId
    Title = $window.Title
    Screenshot = (Resolve-Path -LiteralPath $OutputPath).Path
    Left = $rect.Left
    Top = $rect.Top
    Right = $rect.Right
    Bottom = $rect.Bottom
    Width = $width
    Height = $height
}
