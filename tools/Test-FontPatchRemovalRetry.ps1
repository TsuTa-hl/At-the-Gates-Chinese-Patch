param()

$ErrorActionPreference = "Stop"

$scriptPath = Join-Path $PSScriptRoot "Build-Patch.ps1"
if (!(Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
    throw "Missing build script: $scriptPath"
}

$source = Get-Content -LiteralPath $scriptPath -Raw -Encoding UTF8

if ($source -notmatch "Remove-AtGGeneratedFontPatch") {
    throw "Build-Patch.ps1 must keep the generated font cleanup helper."
}

if ($source -notmatch "MaxAttempts" -or $source -notmatch "Start-Sleep") {
    throw "Generated font cleanup must retry transient Windows delete failures."
}

if ($source -notmatch "Unable to remove generated font patch") {
    throw "Generated font cleanup must keep a hard failure after retry attempts are exhausted."
}

"Font patch removal retry guard validation passed."
