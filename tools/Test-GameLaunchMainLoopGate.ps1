param()

$ErrorActionPreference = "Stop"

$scriptPath = Join-Path $PSScriptRoot "Test-GameLaunch.ps1"
if (!(Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
    throw "Missing smoke-test script: $scriptPath"
}

$source = Get-Content -LiteralPath $scriptPath -Raw -Encoding UTF8
$mainLoopMarkerPattern = [regex]::Escape("Controller\s+- Giving Control to Human")
$newGameCompletePattern = [regex]::Escape("Game World\s+- New Game Complete")

if ($source -notmatch $mainLoopMarkerPattern) {
    throw "Test-GameLaunch.ps1 must wait for the main-loop marker 'Controller - Giving Control to Human'."
}

if ($source -match "$newGameCompletePattern[\s\S]{0,120}-or[\s\S]{0,120}$mainLoopMarkerPattern") {
    throw "Test-GameLaunch.ps1 must not treat 'Game World - New Game Complete' as sufficient new-game readiness."
}

if ($source -notmatch "NewGameReadyMarker") {
    throw "Smoke-test output must include NewGameReadyMarker evidence."
}

if ($source -notmatch "PostNewGameReadyDelayMs") {
    throw "Smoke test must keep the game alive briefly after the main-loop marker before screenshot/cleanup."
}

"Game launch main-loop gate validation passed."
