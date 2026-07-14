param(
    [string]$TempRoot = "$PSScriptRoot\..\.tmp\cached-validation-tests"
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\AtGCache.ps1"

if (Test-Path -LiteralPath $TempRoot) {
    Remove-Item -LiteralPath $TempRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $TempRoot | Out-Null
$inputPath = Join-Path $TempRoot "input.txt"
$stampPath = Join-Path $TempRoot "stage.sha256"
Set-Content -LiteralPath $inputPath -Value "alpha" -Encoding UTF8
$script:runCount = 0
$action = { $script:runCount++ }

$firstHit = Invoke-AtGCachedValidation -Name "probe" -InputPaths @($inputPath) -StampPath $stampPath -ScriptBlock $action
$secondHit = Invoke-AtGCachedValidation -Name "probe" -InputPaths @($inputPath) -StampPath $stampPath -ScriptBlock $action
if ($firstHit) { throw "First validation run must not be a cache hit." }
if (!$secondHit) { throw "Second validation run must be a cache hit." }
if ($script:runCount -ne 1) { throw "Cached validation executed $script:runCount times instead of once." }

Set-Content -LiteralPath $inputPath -Value "beta" -Encoding UTF8
$thirdHit = Invoke-AtGCachedValidation -Name "probe" -InputPaths @($inputPath) -StampPath $stampPath -ScriptBlock $action
if ($thirdHit) { throw "Changed input must invalidate the validation cache." }
if ($script:runCount -ne 2) { throw "Changed input did not rerun validation." }

$stageInput = Join-Path $TempRoot "stage-input.txt"
$stageOutput = Join-Path $TempRoot "stage-output.txt"
$stageStamp = Join-Path $TempRoot "stage.json"
Set-Content -LiteralPath $stageInput -Value "source" -Encoding UTF8
$script:stageRunCount = 0
$stageAction = {
    $script:stageRunCount++
    Set-Content -LiteralPath $stageOutput -Value "generated" -Encoding UTF8
}
$stageFirstHit = Invoke-AtGCachedStage -Name "generated probe" -InputPaths @($stageInput) `
    -OutputPaths @($stageOutput) -StampPath $stageStamp -ScriptBlock $stageAction
$stageSecondHit = Invoke-AtGCachedStage -Name "generated probe" -InputPaths @($stageInput) `
    -OutputPaths @($stageOutput) -StampPath $stageStamp -ScriptBlock $stageAction
if ($stageFirstHit -or !$stageSecondHit -or $script:stageRunCount -ne 1) {
    throw "Generated stage did not reuse a verified output."
}

Set-Content -LiteralPath $stageOutput -Value "tampered" -Encoding UTF8
$tamperedHit = Invoke-AtGCachedStage -Name "generated probe" -InputPaths @($stageInput) `
    -OutputPaths @($stageOutput) -StampPath $stageStamp -ScriptBlock $stageAction
if ($tamperedHit -or $script:stageRunCount -ne 2) {
    throw "Tampered generated output did not invalidate the stage cache."
}

Remove-Item -LiteralPath $stageOutput -Force
$missingHit = Invoke-AtGCachedStage -Name "generated probe" -InputPaths @($stageInput) `
    -OutputPaths @($stageOutput) -StampPath $stageStamp -ScriptBlock $stageAction
if ($missingHit -or $script:stageRunCount -ne 3) {
    throw "Missing generated output did not invalidate the stage cache."
}

Write-Host "Cached validation behavior passed."
