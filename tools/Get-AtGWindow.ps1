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

    function Add-AtGWindowCandidate {
        param(
            [IntPtr]$Handle,
            [int]$ProcessId,
            [string]$ProcessName,
            [string]$Title,
            [string]$Source
        )

        if ($Handle -eq [IntPtr]::Zero) {
            return
        }

        $rect = New-Object AtGWindowFinder+RECT
        if (![AtGWindowFinder]::GetWindowRect($Handle, [ref]$rect)) {
            return
        }

        $width = $rect.Right - $rect.Left
        $height = $rect.Bottom - $rect.Top
        if ($width -lt 200 -or $height -lt 200) {
            return
        }

        [void]$candidates.Add([pscustomobject]@{
            Handle = $Handle
            ProcessId = $ProcessId
            ProcessName = $ProcessName
            Title = $Title
            Left = $rect.Left
            Top = $rect.Top
            Right = $rect.Right
            Bottom = $rect.Bottom
            Width = $width
            Height = $height
            Area = $width * $height
            Source = $Source
        })
    }

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

        if ($processName -ne "At The Gates") {
            return $true
        }

        Add-AtGWindowCandidate `
            -Handle $hWnd `
            -ProcessId $processId `
            -ProcessName $processName `
            -Title $title `
            -Source "EnumWindows candidate"

        return $true
    }

    [AtGWindowFinder]::EnumWindows($callback, [IntPtr]::Zero) | Out-Null

    if ($candidates.Count -eq 0) {
        foreach ($process in @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -eq "At The Gates" -and $_.MainWindowHandle -ne 0 })) {
            Add-AtGWindowCandidate `
                -Handle $process.MainWindowHandle `
                -ProcessId $process.Id `
                -ProcessName $process.ProcessName `
                -Title $process.MainWindowTitle `
                -Source "ProcessHandleFallback"
        }
    }

    $window = $candidates |
        Sort-Object `
            @{ Expression = { if ($_.Title -like "*At the Gates*") { 0 } else { 1 } } }, `
            @{ Expression = { $_.Area }; Descending = $true } |
        Select-Object -First 1

    if (!$window) {
        throw "At the Gates window not found."
    }

    return $window
}
