$ErrorActionPreference = "Stop"

function Assert-AtG {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (!$Condition) {
        throw $Message
    }
}

$repoRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
. (Join-Path $repoRoot "tools\AtGPatchNotice.ps1")

$notice = Get-AtGInstallationNotice
$requiredPhrases = @(
    "free, strictly non-commercial, unofficial fan-made patch",
    "does not include or redistribute any original At the Gates game files",
    "legitimate copy of the game",
    "Conifer Games cannot provide technical support",
    "crash reports and technical issues from patched games to this project",
    "granted in good faith and may be revoked"
)
foreach ($phrase in $requiredPhrases) {
    Assert-AtG ($notice.Message.Contains($phrase)) "Install notice is missing required permission text: $phrase"
}

$installSource = Get-Content -LiteralPath (Join-Path $repoRoot "Install-ChinesePatch.ps1") -Raw -Encoding UTF8
$noticeSource = Get-Content -LiteralPath (Join-Path $repoRoot "tools\AtGPatchNotice.ps1") -Raw -Encoding UTF8
Assert-AtG ($installSource -match "Show-AtGInstallationNotice") "Install script does not display the permission notice by default."
Assert-AtG ($installSource -match "NoInstallNotice") "Install script cannot suppress the popup for non-interactive test automation."
Assert-AtG ($noticeSource -match "MessageBox\]::Show") "Permission notice is not implemented as an installation popup."

Write-Host "Install permission notice checks passed."
