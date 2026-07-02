param()

$ErrorActionPreference = "Stop"

$scriptPath = Join-Path $PSScriptRoot "Invoke-AtGTrialLocalizationBatch.ps1"
if (!(Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
    throw "Missing trial localization script: $scriptPath"
}

$source = Get-Content -LiteralPath $scriptPath -Raw -Encoding UTF8

if ($source -notmatch "final-accepted") {
    throw "Trial localization script must run a final accepted-only smoke check after bisection."
}

if ($source -notmatch "FinalAcceptedPassed") {
    throw "Trial localization script must store and inspect the final accepted-only smoke result."
}

if ($source -notmatch "Test-AtGAnyTrialStageFailed") {
    throw "Trial localization script must detect any failed build/install/smoke stage before finalizing accepted entries."
}

if ($source -notmatch "needsFinalAccepted") {
    throw "Trial localization script must run the final accepted-only smoke check after any failed trial stage, not only after rejected singles."
}

if ($source -notmatch "invalid\.json") {
    throw "Trial localization script must write invalid.json when smoke infrastructure invalidates a run."
}

if ($source -notmatch "rejected\.invalid-smoke\.json") {
    throw "Trial localization script must preserve invalid rejected evidence without exporting it as unsafe text."
}

if ($source -notmatch "Write-AtGTrialResults") {
    throw "Trial localization script must rewrite results.json after final accepted-only smoke checks."
}

if ($source -notmatch "Restore-AtGTrialBaselineMaps") {
    throw "Trial localization script must restore baseline maps when the final accepted-only smoke check fails."
}

"Trial localization final-accepted guard validation passed."
