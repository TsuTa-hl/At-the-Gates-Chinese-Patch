param()

$ErrorActionPreference = "Stop"

$scriptPath = Join-Path $PSScriptRoot "Build-IlRewritePatch.ps1"
if (!(Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
    throw "Missing IL rewrite build script: $scriptPath"
}

$source = Get-Content -LiteralPath $scriptPath -Raw -Encoding UTF8

if ($source -notmatch "Invoke-AtGIlRewriteWithRetry") {
    throw "Build-IlRewritePatch.ps1 must wrap the dnlib rewrite invocation in a retry helper."
}

if ($source -notmatch "user-mapped section" -or $source -notmatch "0x7528, 0x6237, 0x6620, 0x5c04, 0x533a, 0x57df") {
    throw "IL rewrite retry logic must explicitly recognize Windows mapped-file write failures."
}

if ($source -notmatch "MaxAttempts" -or $source -notmatch "Start-Sleep") {
    throw "IL rewrite retry logic must use bounded retry attempts with a delay."
}

if ($source -notmatch "oldErrorActionPreference" -or $source -notmatch "ErrorActionPreference\s*=\s*`"Continue`"") {
    throw "IL rewrite retry logic must prevent native stderr from bypassing retry handling under ErrorActionPreference=Stop."
}

if ($source -notmatch "IL rewrite failed for") {
    throw "IL rewrite retry logic must keep the existing hard failure when retry attempts are exhausted."
}

"IL rewrite mapped-file retry guard validation passed."
