param()

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$activeRunPath = Join-Path $repoRoot ".tmp\trial-localization\active-run.json"
$tempRoot = Join-Path $repoRoot ".tmp\trial-localization-recovery-test"

if (Test-Path -LiteralPath $tempRoot) {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $activeRunPath) | Out-Null

$mapPath = Join-Path $tempRoot "map.json"
$backupPath = Join-Path $tempRoot "baseline-map.json"
$clean = "[`n  {`"Original`":`"Clean`",`"Translation`":`"CleanCN`",`"MethodToken`":`"0x1`",`"ILOffset`":1}`n]`n"
$dirty = "[`n  {`"Original`":`"Dirty`",`"Translation`":`"DirtyCN`",`"MethodToken`":`"0x2`",`"ILOffset`":2}`n]`n"
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($backupPath, $clean, $utf8NoBom)
[System.IO.File]::WriteAllText($mapPath, $dirty, $utf8NoBom)

$active = [pscustomobject]@{
    ProcessId = 999999
    RunRoot = $tempRoot
    StartedAt = (Get-Date).AddMinutes(-10).ToString("o")
    Maps = @(
        [pscustomobject]@{
            Assembly = "UI"
            MapPath = $mapPath
            BaselineBackup = $backupPath
        }
    )
}
$active | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $activeRunPath -Encoding UTF8

try {
    & "$PSScriptRoot\Invoke-AtGTrialLocalizationBatch.ps1" `
        -BatchJson (Join-Path $repoRoot "translations\trial-ui-exact-next2-batch.json") `
        -PlanOnly | Out-Null

    $restored = Get-Content -LiteralPath $mapPath -Raw -Encoding UTF8
    if ($restored -ne $clean) {
        throw "Incomplete trial restore did not copy the baseline map back."
    }

    if (Test-Path -LiteralPath $activeRunPath) {
        throw "Incomplete trial active-run manifest was not cleared after restore."
    }
}
finally {
    Remove-Item -LiteralPath $activeRunPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

"Trial localization recovery guard validation passed."
