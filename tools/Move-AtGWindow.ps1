param(
    [Parameter(Mandatory = $true)]
    [int]$X,

    [Parameter(Mandatory = $true)]
    [int]$Y
)

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\Get-AtGWindow.ps1"
$window = Get-AtGWindow

Add-Type @"
using System;
using System.Runtime.InteropServices;

public static class AtGMoveWindow {
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

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool SetCursorPos(int X, int Y);
}
"@

[AtGMoveWindow]::SetProcessDpiAwarenessContext([IntPtr]::new(-4)) | Out-Null
[AtGMoveWindow]::SetProcessDPIAware() | Out-Null

$rect = New-Object AtGMoveWindow+RECT
if (![AtGMoveWindow]::GetWindowRect($window.Handle, [ref]$rect)) {
    throw "Failed to read At the Gates window rectangle."
}

$screenX = $rect.Left + $X
$screenY = $rect.Top + $Y
[AtGMoveWindow]::SetForegroundWindow($window.Handle) | Out-Null
Start-Sleep -Milliseconds 100
[AtGMoveWindow]::SetCursorPos($screenX, $screenY) | Out-Null

[pscustomobject]@{
    ProcessId = $window.ProcessId
    Title = $window.Title
    WindowX = $X
    WindowY = $Y
    WindowLeft = $rect.Left
    WindowTop = $rect.Top
    WindowRight = $rect.Right
    WindowBottom = $rect.Bottom
    ScreenX = $screenX
    ScreenY = $screenY
}
