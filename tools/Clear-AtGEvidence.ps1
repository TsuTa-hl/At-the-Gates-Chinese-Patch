[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$EvidenceRoot,

    [int]$OlderThanDays = 14,

    [int]$KeepLatestPerScenario = 2,

    [switch]$IncludeLegacy,

    [switch]$Force
)

$ErrorActionPreference = "Stop"

$workspaceRoot = Join-Path $PSScriptRoot ".."
$cleaner = Join-Path $PSScriptRoot "Clear-AtGWorkspace.ps1"
$arguments = @{
    WorkspaceRoot = $workspaceRoot
    RunsOnly = $true
}
if (![string]::IsNullOrWhiteSpace($EvidenceRoot)) {
    $arguments["TempRoot"] = $EvidenceRoot
}
if ($Force) {
    $arguments["Apply"] = $true
}
if ($WhatIfPreference) {
    $arguments["WhatIf"] = $true
}

Write-Warning "Clear-AtGEvidence.ps1 is a compatibility wrapper. It now delegates to Clear-AtGWorkspace.ps1 for classified run evidence only. OlderThanDays, KeepLatestPerScenario, and IncludeLegacy are retained for callers but no longer select deletion targets."
& $cleaner @arguments
