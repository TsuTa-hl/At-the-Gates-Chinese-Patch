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
# Keep the regression test ASCII-only for Windows PowerShell 5.1.
$phrase1 = [string](ConvertFrom-Json '"\u672c\u8865\u4e01\u514d\u8d39\u63d0\u4f9b\uff0c\u4e25\u683c\u7981\u6b62\u5546\u4e1a\u7528\u9014\uff0c\u5c5e\u4e8e\u975e\u5b98\u65b9\u7c89\u4e1d\u5236\u4f5c\u8865\u4e01\u3002"')
$phrase2 = [string](ConvertFrom-Json '"\u8865\u4e01\u4e0d\u5305\u542b\u6216\u518d\u5206\u53d1\u300aAt the Gates\u300b\u7684\u4efb\u4f55\u539f\u59cb\u6e38\u620f\u6587\u4ef6\u3002\u4f60\u5fc5\u987b\u62e5\u6709\u6e38\u620f\u7684\u6b63\u7248\u526f\u672c\u3002"')
$phrase3 = [string](ConvertFrom-Json '"Conifer Games \u65e0\u6cd5\u4e3a\u4fee\u6539\u540e\u7684\u5b89\u88c5\u63d0\u4f9b\u6280\u672f\u652f\u6301\u3002"')
$phrase4 = [string](ConvertFrom-Json '"\u4fee\u6539\u7248\u6e38\u620f\u7684\u5d29\u6e83\u62a5\u544a\u548c\u6280\u672f\u95ee\u9898\u8bf7\u63d0\u4ea4\u7ed9\u672c\u9879\u76ee\uff0c\u4e0d\u8981\u63d0\u4ea4\u7ed9 Conifer Games\uff1a"')
$phrase5 = [string](ConvertFrom-Json '"\u672c\u8865\u4e01\u7684\u53d1\u5e03\u4e0e\u63a8\u5e7f\u8bb8\u53ef\u57fa\u4e8e\u5584\u610f\u6388\u4e88\uff0c\u4e14\u53ef\u80fd\u88ab\u64a4\u9500\u3002"')
$requiredPhrases = @(
    $phrase1,
    $phrase2,
    $phrase3,
    $phrase4,
    $phrase5
)
foreach ($phrase in $requiredPhrases) {
    Assert-AtG ($notice.Message.Contains($phrase)) "Install notice is missing required permission text: $phrase"
}

$installSource = Get-Content -LiteralPath (Join-Path $repoRoot "Install-ChinesePatch.ps1") -Raw -Encoding UTF8
$noticeSource = Get-Content -LiteralPath (Join-Path $repoRoot "tools\AtGPatchNotice.ps1") -Raw -Encoding UTF8
Assert-AtG ($installSource -match "Show-AtGInstallationNotice") "Install script does not display the permission notice by default."
Assert-AtG ($installSource -match "NoInstallNotice") "Install script cannot suppress the popup for non-interactive test automation."
Assert-AtG ($noticeSource -match "MessageBox\]::Show") "Permission notice is not implemented as an installation popup."
$expectedTitle = [string](ConvertFrom-Json '"\u300aAt the Gates\u300b\u7b80\u4f53\u4e2d\u6587\u8865\u4e01\u58f0\u660e"')
Assert-AtG ($notice.Title -eq $expectedTitle) "Install notice title is not Chinese."

Write-Host "Install permission notice checks passed."
