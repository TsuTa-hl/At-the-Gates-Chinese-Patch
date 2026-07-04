param()

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$batchPath = Join-Path $repoRoot ".tmp\trial-elftools-support-test.json"

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $batchPath) | Out-Null

$batch = @(
    [pscustomobject]@{
        Assembly = "ElfTools"
        Original = "This action can be performed by pressing"
        Translation = "按下"
        MethodToken = "0x060003fa"
        ILOffset = 45
        TypeFullName = "ElfTools.Inputs.Hotkey"
        MethodName = "BuildTooltip"
    }
)

$batch | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $batchPath -Encoding UTF8

try {
    $plan = & "$PSScriptRoot\Invoke-AtGTrialLocalizationBatch.ps1" -BatchJson $batchPath -PlanOnly
    if ($null -eq $plan) {
        throw "PlanOnly returned no result for ElfTools batch."
    }

    if ([int]$plan.InputEntries -ne 1) {
        throw "Expected one ElfTools input entry, got $($plan.InputEntries)."
    }
}
finally {
    Remove-Item -LiteralPath $batchPath -Force -ErrorAction SilentlyContinue
}

"Trial localization ElfTools support validation passed."
