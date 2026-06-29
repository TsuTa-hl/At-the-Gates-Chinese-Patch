param(
    [Parameter(Mandatory = $true)]
    [int]$X,

    [Parameter(Mandatory = $true)]
    [int]$Y,

    [ValidateSet("MouseEvent", "SendInput", "PostMessage", "All")]
    [string]$Method = "MouseEvent"
)

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\Get-AtGWindow.ps1"
$window = Get-AtGWindow

Add-Type @"
using System;
using System.Runtime.InteropServices;

public static class AtGClickWindow {
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

    [DllImport("user32.dll")]
    public static extern void mouse_event(uint dwFlags, int dx, int dy, uint dwData, UIntPtr dwExtraInfo);

    [DllImport("user32.dll")]
    public static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

    [DllImport("user32.dll")]
    public static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    public struct INPUT {
        public uint type;
        public MOUSEINPUT mi;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct MOUSEINPUT {
        public int dx;
        public int dy;
        public uint mouseData;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }
}
"@

[AtGClickWindow]::SetProcessDpiAwarenessContext([IntPtr]::new(-4)) | Out-Null
[AtGClickWindow]::SetProcessDPIAware() | Out-Null

$rect = New-Object AtGClickWindow+RECT
if (![AtGClickWindow]::GetWindowRect($window.Handle, [ref]$rect)) {
    throw "Failed to read At the Gates window rectangle."
}

$screenX = $rect.Left + $X
$screenY = $rect.Top + $Y
[AtGClickWindow]::SetForegroundWindow($window.Handle) | Out-Null
Start-Sleep -Milliseconds 100
[AtGClickWindow]::SetCursorPos($screenX, $screenY) | Out-Null
Start-Sleep -Milliseconds 150

if ($Method -eq "MouseEvent" -or $Method -eq "All") {
    [AtGClickWindow]::mouse_event(0x0001, 1, 1, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 40
    [AtGClickWindow]::mouse_event(0x0001, -1, -1, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 40
    [AtGClickWindow]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 80
    [AtGClickWindow]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 100
}

if ($Method -eq "SendInput" -or $Method -eq "All") {
    $down = New-Object AtGClickWindow+INPUT
    $down.type = 0
    $down.mi.dwFlags = 0x0002
    $up = New-Object AtGClickWindow+INPUT
    $up.type = 0
    $up.mi.dwFlags = 0x0004
    $moveA = New-Object AtGClickWindow+INPUT
    $moveA.type = 0
    $moveA.mi.dx = 1
    $moveA.mi.dy = 1
    $moveA.mi.dwFlags = 0x0001
    $moveB = New-Object AtGClickWindow+INPUT
    $moveB.type = 0
    $moveB.mi.dx = -1
    $moveB.mi.dy = -1
    $moveB.mi.dwFlags = 0x0001
    $inputs = [AtGClickWindow+INPUT[]]@($moveA, $moveB, $down, $up)
    $sent = [AtGClickWindow]::SendInput([uint32]$inputs.Length, $inputs, [System.Runtime.InteropServices.Marshal]::SizeOf([type][AtGClickWindow+INPUT]))
    if ($sent -ne $inputs.Length) {
        throw "SendInput failed. Sent $sent of $($inputs.Length) events."
    }
}

if ($Method -eq "PostMessage" -or $Method -eq "All") {
    $lParam = [IntPtr](($Y -shl 16) -bor ($X -band 0xffff))
    [AtGClickWindow]::PostMessage($window.Handle, 0x0200, [IntPtr]::Zero, $lParam) | Out-Null
    Start-Sleep -Milliseconds 50
    [AtGClickWindow]::PostMessage($window.Handle, 0x0201, [IntPtr]1, $lParam) | Out-Null
    Start-Sleep -Milliseconds 80
    [AtGClickWindow]::PostMessage($window.Handle, 0x0202, [IntPtr]::Zero, $lParam) | Out-Null
}

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
    Method = $Method
}
