param()

$ErrorActionPreference = 'Stop'

function Assert-AtGPublishContract {
    param([bool]$Condition, [string]$Message)

    if (!$Condition) {
        throw $Message
    }
}

$scriptPath = Join-Path $PSScriptRoot 'Publish-AtGRelease.ps1'
Assert-AtGPublishContract (Test-Path -LiteralPath $scriptPath -PathType Leaf) 'Release publisher is missing.'
$tokens = $null
$errors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
Assert-AtGPublishContract ($errors.Count -eq 0) "Release publisher does not parse: $($errors[0].Message)"

$source = [IO.File]::ReadAllText($scriptPath, [Text.Encoding]::UTF8)
foreach ($required in @(
        "'main'",
        "'status', '--porcelain'",
        "'fetch', `$Remote, 'main'",
        'Invoke-AtGVerification.ps1',
        '-Profile Release',
        'Export-ReleasePackage.ps1',
        'Assert-AtGReleaseTree',
        "'init', '--initial-branch', 'release'",
        '--force-with-lease=',
        'HEAD:refs/heads/')) {
    Assert-AtGPublishContract ($source.Contains($required)) "Release publisher contract is missing: $required"
}
Assert-AtGPublishContract (!$source.Contains('git checkout')) 'Release publisher must not rewrite the caller worktree.'
Assert-AtGPublishContract (-not $source.Contains('ReleaseRootFiles')) 'Release publisher must enforce its own package whitelist rather than copying development metadata.'

Write-Host 'Release publisher contract validation passed.'
