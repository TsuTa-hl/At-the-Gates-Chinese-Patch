$ErrorActionPreference = "Stop"
. "$PSScriptRoot\AtGFileOps.ps1"

$root = Join-Path $PSScriptRoot "..\.tmp\file-ops-test"
New-Item -ItemType Directory -Force -Path $root | Out-Null
$source = Join-Path $root "source.bin"
$destination = Join-Path $root "destination.bin"
[System.IO.File]::WriteAllText($source, "same-content")
[System.IO.File]::WriteAllText($destination, "same-content")
$before = (Get-Item -LiteralPath $destination).LastWriteTimeUtc
$stream = [System.IO.File]::Open(
    $destination,
    [System.IO.FileMode]::Open,
    [System.IO.FileAccess]::Read,
    ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
$mapped = [System.IO.MemoryMappedFiles.MemoryMappedFile]::CreateFromFile(
    $stream,
    ("AtGFileOpsTest-" + [System.Guid]::NewGuid().ToString("N")),
    0,
    [System.IO.MemoryMappedFiles.MemoryMappedFileAccess]::Read,
    [System.IO.HandleInheritability]::None,
    $true)
try {
    $copied = Copy-AtGFileIfChanged -Source $source -Destination $destination
    if ($copied) { throw "Identical mapped file should not be copied." }
    if ((Get-Item -LiteralPath $destination).LastWriteTimeUtc -ne $before) {
        throw "Skipped destination timestamp changed."
    }
}
finally {
    $mapped.Dispose()
    $stream.Dispose()
}

[System.IO.File]::WriteAllText($source, "changed-content")
$copied = Copy-AtGFileIfChanged -Source $source -Destination $destination
if (!$copied) { throw "Changed file should be copied." }
if ([System.IO.File]::ReadAllText($destination) -ne "changed-content") {
    throw "Changed destination content was not installed."
}

$ready = Join-Path $root "mapped-ready.flag"
Remove-Item -LiteralPath $ready -Force -ErrorAction SilentlyContinue
[System.IO.File]::WriteAllText($source, "mapped-change")
[System.IO.File]::WriteAllText($destination, "mapped-old")
$job = Start-Job -ArgumentList $destination, $ready -ScriptBlock {
    param($Destination, $Ready)

    $stream = [System.IO.File]::Open(
        $Destination,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
    $mapped = [System.IO.MemoryMappedFiles.MemoryMappedFile]::CreateFromFile(
        $stream,
        ("AtGFileOpsRetryTest-" + [System.Guid]::NewGuid().ToString("N")),
        0,
        [System.IO.MemoryMappedFiles.MemoryMappedFileAccess]::Read,
        [System.IO.HandleInheritability]::None,
        $true)
    try {
        [System.IO.File]::WriteAllText($Ready, "ready")
        Start-Sleep -Milliseconds 500
    }
    finally {
        $mapped.Dispose()
        $stream.Dispose()
    }
}

try {
    $deadline = [DateTime]::UtcNow.AddSeconds(5)
    while (!(Test-Path -LiteralPath $ready) -and [DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 25
    }
    if (!(Test-Path -LiteralPath $ready)) {
        throw "Timed out waiting for the mapped-file test fixture."
    }

    $copied = Copy-AtGFileIfChanged -Source $source -Destination $destination
    if (!$copied) { throw "Changed mapped file should be copied after the transient lock clears." }
    if ([System.IO.File]::ReadAllText($destination) -ne "mapped-change") {
        throw "Mapped destination content was not replaced after retry."
    }
}
finally {
    Wait-Job -Job $job -Timeout 5 | Out-Null
    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
}

$buildPatch = Get-Content -LiteralPath (Join-Path $PSScriptRoot "Build-Patch.ps1") -Raw
if ($buildPatch -notmatch 'AtGFileOps\.ps1') {
    throw "Build-Patch.ps1 must load the shared file operation helpers."
}
if ($buildPatch -notmatch 'Copy-AtGFileIfChanged\s+-Source\s+\$managedGameOutput' -or
    $buildPatch -notmatch 'Copy-AtGFileIfChanged\s+-Source\s+\$managedElfToolsOutput') {
    throw "Managed Game and ElfTools outputs must use the mapped-file-safe copy helper."
}

Write-Host "AtG file operation tests passed."
