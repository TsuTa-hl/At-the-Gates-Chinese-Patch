[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$EvidenceRoot,

    [int]$OlderThanDays = 14,

    [int]$KeepLatestPerScenario = 2,

    [switch]$IncludeLegacy,

    [switch]$Force
)

$ErrorActionPreference = "Stop"

function Get-AtGDirectorySize {
    param([Parameter(Mandatory = $true)][string]$Path)

    $total = 0L
    if (!(Test-Path -LiteralPath $Path)) {
        return $total
    }

    foreach ($file in Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue) {
        $total += [int64]$file.Length
    }

    return $total
}

if ([string]::IsNullOrWhiteSpace($EvidenceRoot)) {
    $EvidenceRoot = Join-Path $PSScriptRoot "..\.tmp"
}

$workspaceRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path.TrimEnd("\", "/")
$resolvedRoot = if (Test-Path -LiteralPath $EvidenceRoot) {
    (Resolve-Path -LiteralPath $EvidenceRoot).Path.TrimEnd("\", "/")
}
else {
    $EvidenceRoot
}

if (!(Test-Path -LiteralPath $resolvedRoot)) {
    [pscustomobject]@{
        EvidenceRoot = $resolvedRoot
        CandidateCount = 0
        CandidateBytes = 0
        Message = "Evidence root does not exist."
    }
    return
}

if (!$resolvedRoot.StartsWith($workspaceRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to inspect evidence outside workspace: $resolvedRoot"
}

$cutoff = (Get-Date).AddDays(-1 * [Math]::Max(0, $OlderThanDays))
$candidateDirectories = New-Object System.Collections.Generic.List[object]

$runsRoot = Join-Path $resolvedRoot "runs"
if (Test-Path -LiteralPath $runsRoot) {
    $runDirs = Get-ChildItem -LiteralPath $runsRoot -Directory | Sort-Object LastWriteTime -Descending
    $byScenario = @{}
    foreach ($dir in $runDirs) {
        $scenario = $dir.Name -replace '^\d{8}-\d{6}-', ''
        if (!$byScenario.ContainsKey($scenario)) {
            $byScenario[$scenario] = 0
        }
        $byScenario[$scenario]++

        if ($byScenario[$scenario] -le $KeepLatestPerScenario) {
            continue
        }
        if ($dir.LastWriteTime -gt $cutoff) {
            continue
        }

        $size = Get-AtGDirectorySize -Path $dir.FullName
        $candidateDirectories.Add([pscustomobject]@{
            Path = $dir.FullName
            Kind = "run"
            Scenario = $scenario
            LastWriteTime = $dir.LastWriteTime
            Bytes = $size
        }) | Out-Null
    }
}

if ($IncludeLegacy) {
    foreach ($dir in Get-ChildItem -LiteralPath $resolvedRoot -Directory | Where-Object { $_.Name -ne "runs" }) {
        if ($dir.LastWriteTime -gt $cutoff) {
            continue
        }

        $size = Get-AtGDirectorySize -Path $dir.FullName
        $candidateDirectories.Add([pscustomobject]@{
            Path = $dir.FullName
            Kind = "legacy"
            Scenario = $null
            LastWriteTime = $dir.LastWriteTime
            Bytes = $size
        }) | Out-Null
    }
}

$candidateBytes = 0L
foreach ($candidate in $candidateDirectories) {
    $candidateBytes += [int64]$candidate.Bytes
}

if ($Force) {
    foreach ($candidate in $candidateDirectories) {
        if (!$candidate.Path.StartsWith($workspaceRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to remove path outside workspace: $($candidate.Path)"
        }

        if ($PSCmdlet.ShouldProcess($candidate.Path, "Remove evidence directory")) {
            Remove-Item -LiteralPath $candidate.Path -Recurse -Force
        }
    }
}

[pscustomobject]@{
    EvidenceRoot = $resolvedRoot
    OlderThanDays = $OlderThanDays
    KeepLatestPerScenario = $KeepLatestPerScenario
    IncludeLegacy = [bool]$IncludeLegacy
    Deleted = [bool]$Force
    CandidateCount = $candidateDirectories.Count
    CandidateBytes = $candidateBytes
    CandidateMiB = [Math]::Round($candidateBytes / 1MB, 2)
    Candidates = @($candidateDirectories | Sort-Object Bytes -Descending)
}
