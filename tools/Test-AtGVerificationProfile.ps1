param()

$ErrorActionPreference = 'Stop'

function Assert-AtGVerificationProfile {
    param([bool]$Condition, [string]$Message)

    if (!$Condition) {
        throw $Message
    }
}

$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'AtGVerificationProfile.ps1')

$manifest = Get-AtGVerificationSuiteManifest -ProjectRoot $root
$tests = @($manifest.Tests)
$dotNetGroups = @($manifest.DotNetTestGroups)

Assert-AtGVerificationProfile ([int]$manifest.SchemaVersion -eq 2) 'Verification suite manifest must use schema v2.'
Assert-AtGVerificationProfile ($tests.Count -gt 0) 'Verification suite manifest must classify PowerShell tests.'
Assert-AtGVerificationProfile ($dotNetGroups.Count -gt 0) 'Verification suite manifest must classify .NET test groups.'

$testIds = @($tests | ForEach-Object { [string]$_.Id })
$scripts = @($tests | ForEach-Object { [string]$_.Script })
Assert-AtGVerificationProfile (($testIds | Select-Object -Unique).Count -eq $testIds.Count) 'Verification suite test IDs must be unique.'
Assert-AtGVerificationProfile (($scripts | Select-Object -Unique).Count -eq $scripts.Count) 'Verification suite test scripts must be classified exactly once.'

$discoveredScripts = @(Get-ChildItem -LiteralPath (Join-Path $root 'tools') -Filter 'Test-*.ps1' -File |
    Select-Object -ExpandProperty Name | Sort-Object)
Assert-AtGVerificationProfile (($scripts | Sort-Object) -join "`n" -eq ($discoveredScripts -join "`n")) 'Every Test-*.ps1 must be classified exactly once in the verification suite manifest.'

foreach ($test in $tests) {
    foreach ($field in @('Id', 'Script', 'Kind', 'Profiles', 'Triggers', 'EnvironmentPrerequisites')) {
        Assert-AtGVerificationProfile ($null -ne $test.PSObject.Properties[$field]) "Verification test '$($test.Id)' is missing '$field'."
    }
    Assert-AtGVerificationProfile (([string]$test.Kind) -in @('Static', 'Smoke')) "Verification test '$($test.Id)' has an unsupported Kind."
    Assert-AtGVerificationProfile (@($test.Profiles | Where-Object { $_ -eq 'Release' }).Count -eq 1) "Release must cover '$($test.Id)'."
    Assert-AtGVerificationProfile (Test-Path -LiteralPath (Join-Path $root ('tools\' + [string]$test.Script)) -PathType Leaf) "Verification test script is missing: $($test.Script)"
}

$smoke = @($tests | Where-Object { [string]$_.Kind -eq 'Smoke' })
Assert-AtGVerificationProfile ($smoke.Count -eq 1 -and [string]$smoke[0].Script -eq 'Test-GameLaunch.ps1') 'The main-menu smoke must be classified exactly once.'

foreach ($id in @('initialize-atg-source', 'install-refresh', 'patch-uninstall-completeness', 'release-package', 'uninstall-chinese-patch')) {
    $test = @($tests | Where-Object { [string]$_.Id -eq $id })
    Assert-AtGVerificationProfile ($test.Count -eq 1 -and @($test[0].EnvironmentPrerequisites) -contains 'AtGProcessStopped') "Transaction fixture '$id' must declare the active-game precondition."
}

$dotNetIds = @($dotNetGroups | ForEach-Object { [string]$_.Id })
Assert-AtGVerificationProfile (($dotNetIds | Select-Object -Unique).Count -eq $dotNetIds.Count) '.NET test group IDs must be unique.'
foreach ($group in $dotNetGroups) {
    foreach ($field in @('Id', 'Project', 'Profiles', 'Triggers', 'EnvironmentPrerequisites')) {
        Assert-AtGVerificationProfile ($null -ne $group.PSObject.Properties[$field]) ".NET test group '$($group.Id)' is missing '$field'."
    }
    Assert-AtGVerificationProfile (@($group.Profiles | Where-Object { $_ -eq 'Release' }).Count -eq 1) "Release must cover .NET test group '$($group.Id)'."
    Assert-AtGVerificationProfile (Test-Path -LiteralPath (Join-Path $root ([string]$group.Project)) -PathType Leaf) ".NET test project is missing: $($group.Project)"
}

function Get-SelectedIds {
    param([object]$Selection)

    return @($Selection.StaticTests | ForEach-Object { [string]$_.Id })
}

$textSelection = Resolve-AtGVerificationSelection -ProjectRoot $root -ChangedPath @('translations/zh-CN.json')
$textIds = Get-SelectedIds $textSelection
Assert-AtGVerificationProfile ($textSelection.ChangedPathCategories -contains 'text') 'Text input must select the text category.'
Assert-AtGVerificationProfile ($textIds -contains 'text-tags' -and $textIds -contains 'generated-text-aliases') 'Text input must select text checks.'
Assert-AtGVerificationProfile ($textIds -notcontains 'release-package' -and $textIds -notcontains 'known-text-review-export') 'Localization must not select release-only catalog/package audits.'
Assert-AtGVerificationProfile (!$textSelection.IsDocumentationOnly -and $textSelection.RequiresGameTransaction -and $textSelection.SmokeTests.Count -eq 1) 'A player-visible localization must retain its game transaction and main-menu smoke.'

$compositeSelection = Resolve-AtGVerificationSelection -ProjectRoot $root -ChangedPath @('translations/runtime-display-strings.json')
$compositeIds = Get-SelectedIds $compositeSelection
Assert-AtGVerificationProfile ($compositeSelection.ChangedPathCategories -contains 'composite') 'Runtime display input must select the composition category.'
Assert-AtGVerificationProfile ($compositeIds -contains 'composite-text-catalog' -and $compositeIds -contains 'concept-key-translation-map') 'Composition input must select composition checks.'

$managedSelection = Resolve-AtGVerificationSelection -ProjectRoot $root -ChangedPath @('translations/hardcoded-ui-il-rewrite.json')
$managedIds = Get-SelectedIds $managedSelection
Assert-AtGVerificationProfile ($managedSelection.ChangedPathCategories -contains 'managed') 'Managed rewrite input must select the managed category.'
Assert-AtGVerificationProfile ($managedIds -contains 'il-rewrite-map-risk' -and $managedIds -contains 'hover-localization-regressions' -and $managedIds -contains 'notification-composition-localization') 'Managed input must select IL, hover, and notification regressions.'

$fontSelection = Resolve-AtGVerificationSelection -ProjectRoot $root -ChangedPath @('tools/Build-FontPatch.ps1')
Assert-AtGVerificationProfile ((Get-SelectedIds $fontSelection) -contains 'font-patch-budget') 'Font input must select font checks.'

$automationSelection = Resolve-AtGVerificationSelection -ProjectRoot $root -ChangedPath @('docs/agent/black-box-scenarios.json')
Assert-AtGVerificationProfile ((Get-SelectedIds $automationSelection) -contains 'black-box-scenario-schema') 'Automation input must select scenario checks.'
Assert-AtGVerificationProfile (@($automationSelection.DotNetTestGroups | Where-Object { $_.Id -eq 'test-harness' }).Count -eq 1) 'Automation input must select TestHarness coverage.'

$documentationSelection = Resolve-AtGVerificationSelection -ProjectRoot $root -ChangedPath @('docs/agent/operations/build-and-install.md')
Assert-AtGVerificationProfile ((Get-SelectedIds $documentationSelection) -contains 'documentation-routing') 'Documentation input must select documentation checks.'
Assert-AtGVerificationProfile $documentationSelection.IsDocumentationOnly 'A documentation-only input must use the no-game verification branch.'
Assert-AtGVerificationProfile (!$documentationSelection.RequiresGameTransaction) 'A documentation-only input must not require a game transaction.'
Assert-AtGVerificationProfile ($documentationSelection.SmokeTests.Count -eq 0) 'A documentation-only input must not select the game smoke.'
$documentationDotNetIds = @($documentationSelection.DotNetTestGroups | ForEach-Object { [string]$_.Id })
Assert-AtGVerificationProfile ($documentationDotNetIds.Count -eq 1 -and $documentationDotNetIds[0] -eq 'script-integration') 'A documentation-only input must select only script integration coverage.'
Assert-AtGVerificationProfile ((Get-SelectedIds $documentationSelection) -notcontains 'text-tags') 'A documentation-only input must not select the localization core text checks.'

$fallbackSelection = Resolve-AtGVerificationSelection -ProjectRoot $root -ChangedPath @('unmapped/future-localization-input.json')
$fallbackIds = Get-SelectedIds $fallbackSelection
Assert-AtGVerificationProfile ($fallbackSelection.UnmappedChangedPaths -contains 'unmapped/future-localization-input.json') 'Unmapped changed paths must be reported.'
Assert-AtGVerificationProfile ($fallbackIds -contains 'text-tags' -and $fallbackIds -contains 'runtime-build-report') 'Unmapped changed paths must retain local core checks.'
Assert-AtGVerificationProfile ($fallbackSelection.RequiresGameTransaction -and $fallbackSelection.SmokeTests.Count -eq 1) 'An unmapped path must remain on the conservative game gate.'

$releaseSelection = Resolve-AtGVerificationSelection -ProjectRoot $root -Profile Release -ChangedPath @('translations/zh-CN.json')
Assert-AtGVerificationProfile ($releaseSelection.StaticTests.Count -eq @($tests | Where-Object { $_.Kind -eq 'Static' }).Count) 'Release must select every static PowerShell check.'
Assert-AtGVerificationProfile ($releaseSelection.DotNetTestGroups.Count -eq $dotNetGroups.Count) 'Release must select every .NET test group.'
Assert-AtGVerificationProfile ((Get-SelectedIds $releaseSelection) -contains 'release-package' -and (Get-SelectedIds $releaseSelection) -contains 'known-text-review-export') 'Release must retain package and full catalog audits.'

$verificationSource = Get-Content -LiteralPath (Join-Path $root 'tools\Invoke-AtGVerification.ps1') -Raw -Encoding UTF8
foreach ($required in @('source-capture', 'build', 'install', 'smoke', 'Invoke-AtGInstalledSmokeTest')) {
    Assert-AtGVerificationProfile ($verificationSource.Contains($required)) "Unified verification must retain '$required' for a localization task."
}

Write-Host 'Verification profile selection validation passed.'
