$ErrorActionPreference = "Stop"

if (-not ("AtGWindowFinder" -as [type])) {
    Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class AtGWindowFinder {
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();

    [DllImport("user32.dll")]
    public static extern bool SetProcessDpiAwarenessContext(IntPtr dpiContext);

    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern int GetWindowTextLength(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out int lpdwProcessId);

    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
}
"@
}

[AtGWindowFinder]::SetProcessDpiAwarenessContext([IntPtr]::new(-4)) | Out-Null
[AtGWindowFinder]::SetProcessDPIAware() | Out-Null

function Get-AtGWindow {
    $candidates = New-Object System.Collections.Generic.List[object]

    $callback = [AtGWindowFinder+EnumWindowsProc]{
        param([IntPtr]$hWnd, [IntPtr]$lParam)

        if (![AtGWindowFinder]::IsWindowVisible($hWnd)) {
            return $true
        }

        $processId = 0
        [AtGWindowFinder]::GetWindowThreadProcessId($hWnd, [ref]$processId) | Out-Null

        $processName = ""
        if ($processId -gt 0) {
            try {
                $processName = (Get-Process -Id $processId -ErrorAction Stop).ProcessName
            }
            catch {
                $processName = ""
            }
        }

        $length = [AtGWindowFinder]::GetWindowTextLength($hWnd)
        $builder = New-Object System.Text.StringBuilder ([Math]::Max($length + 1, 256))
        [AtGWindowFinder]::GetWindowText($hWnd, $builder, $builder.Capacity) | Out-Null
        $title = $builder.ToString()

        if ($processName -ne "At The Gates" -and $title -notlike "*At the Gates*") {
            return $true
        }

        $rect = New-Object AtGWindowFinder+RECT
        if (![AtGWindowFinder]::GetWindowRect($hWnd, [ref]$rect)) {
            return $true
        }

        $width = $rect.Right - $rect.Left
        $height = $rect.Bottom - $rect.Top
        if ($width -lt 200 -or $height -lt 200) {
            return $true
        }

        [void]$candidates.Add([pscustomobject]@{
            Handle = $hWnd
            ProcessId = $processId
            ProcessName = $processName
            Title = $title
            Left = $rect.Left
            Top = $rect.Top
            Right = $rect.Right
            Bottom = $rect.Bottom
            Width = $width
            Height = $height
            Area = $width * $height
        })

        return $true
    }

    [AtGWindowFinder]::EnumWindows($callback, [IntPtr]::Zero) | Out-Null

    $window = $candidates |
        Sort-Object `
            @{ Expression = { if ($_.ProcessName -eq "At The Gates") { 0 } else { 1 } } }, `
            @{ Expression = { if ($_.Title -like "*At the Gates*") { 0 } else { 1 } } }, `
            @{ Expression = { $_.Area }; Descending = $true } |
        Select-Object -First 1

    if (!$window) {
        throw "At the Gates window not found."
    }

    return $window
}
