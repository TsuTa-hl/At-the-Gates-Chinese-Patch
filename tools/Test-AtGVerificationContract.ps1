param()

$ErrorActionPreference = 'Stop'

function Assert-AtGVerificationContract {
    param([bool]$Condition, [string]$Message)

    if (!$Condition) {
        throw $Message
    }
}

$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$scriptPath = Join-Path $PSScriptRoot 'Invoke-AtGVerification.ps1'
Assert-AtGVerificationContract (Test-Path -LiteralPath $scriptPath -PathType Leaf) 'Unified verification script is missing.'

$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
Assert-AtGVerificationContract ($errors.Count -eq 0) "Unified verification script does not parse: $($errors[0].Message)"

$source = [IO.File]::ReadAllText($scriptPath, [Text.Encoding]::UTF8)
foreach ($required in @(
        'Initialize-AtGSource.ps1',
        'Build-Patch.ps1',
        "'restore'",
        "'test'",
        '--locked-mode',
        '--ignore-failed-sources',
        'Invoke-AtGStaticTestSuite',
        'Install-ChinesePatch.ps1',
        'Invoke-AtGInstalledSmokeTest',
        'Restore-AtGVerificationSnapshot',
        'Get-AtGPatchInventory',
        'Copy-AtGFileIfChanged',
        'Remove-AtGVerificationFileIfPresent',
        'Assert-AtGGameNotRunning',
        'AtGVerificationProfile.ps1',
        'Resolve-AtGVerificationSelection',
        'Invoke-AtGVerificationStage',
        'verification-result.json')) {
    Assert-AtGVerificationContract ($source.Contains($required)) "Unified verification contract is missing: $required"
}

Assert-AtGVerificationContract ($source.Contains('if ($StaticOnly)')) 'Unified verification must expose an explicit StaticOnly smoke bypass.'
Assert-AtGVerificationContract ($source.Contains("[ValidateSet('Localization', 'Release')]") -and
    $source.Contains("[string]`$Profile = 'Localization'")) 'Unified verification must default to the Localization profile.'
Assert-AtGVerificationContract ($source.Contains('[string[]]$ChangedPath = @()')) 'Unified verification must accept explicit changed paths.'
Assert-AtGVerificationContract ($source.Contains('UnmappedChangedPaths')) 'Unified verification must record unmapped changed paths.'
Assert-AtGVerificationContract ($source.Contains('IsDocumentationOnly') -and
    $source.Contains('Documentation-only verification')) 'Unified verification must keep documentation-only work out of the game transaction.'
$documentationBranchIndex = $source.IndexOf('Documentation-only verification: running selected static checks')
$gamePreflightIndex = $source.IndexOf("-Name 'game-process-preflight'")
Assert-AtGVerificationContract ($documentationBranchIndex -ge 0 -and $gamePreflightIndex -ge 0 -and
    $documentationBranchIndex -lt $gamePreflightIndex) 'Documentation-only verification must stop before game-process preflight.'
Assert-AtGVerificationContract ($source.Contains("-Name 'source-capture'") -and
    $source.Contains("-Name 'build'") -and
    $source.Contains("-Name 'install'") -and
    $source.Contains("-Name 'smoke'")) 'Localization verification must time source capture, build, install, and smoke.'
Assert-AtGVerificationContract ($source.Contains("'static/' + [string]`$group.Id")) 'Static verification must time each selected test group.'
Assert-AtGVerificationContract (!$source.Contains('git diff')) 'Verification selection must not inspect the dirty worktree with git diff.'
Assert-AtGVerificationContract (!$source.Contains('IncludeNewGame')) 'Default verification must not invoke black-box/new-game coverage.'
Assert-AtGVerificationContract (!$source.Contains('VersionFingerprint')) 'Installation verification must not require a version fingerprint.'
Assert-AtGVerificationContract (!$source.Contains('SteamFingerprint')) 'Installation verification must not require a Steam fingerprint.'
Assert-AtGVerificationContract ($source.Contains('Save-AtGVerificationTransactionArtifacts')) 'Verification must preserve the pre-gate transaction artifacts.'
Assert-AtGVerificationContract ($source.Contains('PatchLeftInstalled = $true')) 'Successful verification must leave the verified patch installed.'
Assert-AtGVerificationContract ($source.Contains("Assert-AtGGameNotRunning -Operation 'verification'")) 'Verification must refuse to mutate a running game.'
Assert-AtGVerificationContract ($source.Contains("Join-Path `$projectRoot '.tools\dotnet\dotnet.exe'")) 'Verification must resolve its default repo-local dotnet path after locating the project root.'
Assert-AtGVerificationContract ($source.Contains('Test-AtGTransientFileWriteFailure')) 'Verification recovery must retry mapped files.'
Assert-AtGVerificationContract ($source.Contains('Resolve locked test dependencies before creating any game snapshot')) 'Locked dependency restoration must be an explicit pre-transaction preflight.'
$restoreIndex = $source.IndexOf("'restore'")
$snapshotTryIndex = $source.IndexOf('try {', $source.IndexOf('function Invoke-AtGInstalledSmokeTest'))
Assert-AtGVerificationContract ($restoreIndex -ge 0 -and $snapshotTryIndex -ge 0 -and $restoreIndex -lt $snapshotTryIndex) 'Locked dependency restoration must occur before the game transaction starts.'

Write-Host 'Unified verification contract validation passed.'
