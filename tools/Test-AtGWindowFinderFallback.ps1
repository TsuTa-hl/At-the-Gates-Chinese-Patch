param()

$ErrorActionPreference = "Stop"

$scriptPath = Join-Path $PSScriptRoot "Get-AtGWindow.ps1"
if (!(Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
    throw "Missing window finder script: $scriptPath"
}

$source = Get-Content -LiteralPath $scriptPath -Raw -Encoding UTF8

if ($source -notmatch "MainWindowHandle") {
    throw "Get-AtGWindow.ps1 must fall back to the At The Gates process MainWindowHandle when EnumWindows finds no candidate."
}

if ($source -notmatch "EnumWindows candidate") {
    throw "Get-AtGWindow.ps1 must keep EnumWindows as the primary path and document the process-handle fallback."
}

if ($source -notmatch "ProcessHandleFallback") {
    throw "Get-AtGWindow.ps1 fallback candidates must identify themselves as ProcessHandleFallback for diagnostics."
}

"AtG window finder fallback validation passed."
