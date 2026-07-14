param()

$ErrorActionPreference = "Stop"
$wrapperPath = Join-Path $PSScriptRoot "Invoke-AtGPatchCli.ps1"
$source = Get-Content -LiteralPath $wrapperPath -Raw -Encoding UTF8

if ($source -notmatch "cli-build\.sha256") {
    throw "Patch CLI wrapper must persist a content-hash build stamp."
}
if ($source -notmatch "buildHash") {
    throw "Patch CLI wrapper must compare the current tool input hash with the build stamp."
}
if ($source -match 'LastWriteTimeUtc\s*-gt\s*\$toolTime') {
    throw "Patch CLI wrapper must not use the entry DLL timestamp for multi-project rebuild decisions."
}

Write-Host "Patch CLI content-hash build cache validation passed."
