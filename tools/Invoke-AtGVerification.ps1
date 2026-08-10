[CmdletBinding()]
param(
    [string]$GamePath,

    [switch]$StaticOnly,

    [ValidateSet('MergedFonts', 'DynamicCjk')]
    [string]$RendererMode = 'DynamicCjk',

    [string]$DotNetPath,

    [ValidateSet('Localization', 'Release')]
    [string]$Profile = 'Localization',

    [string[]]$ChangedPath = @()
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\AtGPaths.ps1"
. "$PSScriptRoot\AtGFileOps.ps1"
. "$PSScriptRoot\AtGPatchManifest.ps1"
. "$PSScriptRoot\AtGTiming.ps1"
. "$PSScriptRoot\AtGVerificationProfile.ps1"

$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$verificationSelection = Resolve-AtGVerificationSelection -ProjectRoot $projectRoot -Profile $Profile -ChangedPath $ChangedPath
$documentationOnly = [bool]$verificationSelection.IsDocumentationOnly
$resolvedGamePath = if ($documentationOnly) {
    $null
}
else {
    Resolve-AtGGamePath $GamePath
}
if ([string]::IsNullOrWhiteSpace($DotNetPath)) {
    $DotNetPath = Join-Path $projectRoot '.tools\dotnet\dotnet.exe'
}
$resolvedDotNetPath = [IO.Path]::GetFullPath($DotNetPath)
if (!(Test-Path -LiteralPath $resolvedDotNetPath -PathType Leaf)) {
    throw "Repo-local dotnet executable is missing: $resolvedDotNetPath"
}

function Invoke-AtGDotNet {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    & $resolvedDotNetPath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet $($Arguments -join ' ') failed with exit code $LASTEXITCODE."
    }
}

$patchRoot = Join-Path $projectRoot 'patch'
$manifestPath = if ($documentationOnly) { $null } else { Join-Path $resolvedGamePath '.atg-chinese-patch.json' }
$backupBase = if ($documentationOnly) { $null } else { Join-Path $resolvedGamePath '_ChinesePatchBackup' }
$verificationRunId = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N')
$evidenceRoot = Join-Path $projectRoot ('.tmp\runs\verification-' + $verificationRunId)
$verificationEvidencePath = Join-Path $evidenceRoot 'verification-result.json'
New-Item -ItemType Directory -Force -Path $evidenceRoot | Out-Null
$snapshotRoot = $null
$snapshotContentRoot = $null
$snapshotTransactionRoot = $null

$snapshotFiles = @{}
$directoryStates = @{}
$transactionState = [pscustomobject]@{
    ManifestExisted = $false
    BackupExisted = $false
}
$timing = New-AtGTimingSummary
$verificationStageResults = New-Object System.Collections.Generic.List[object]
$currentVerificationStage = ''
$gameMutationStarted = $false
$recoveryResult = 'Not needed.'
$smokeResult = 'Not run.'
$finalPatchFiles = @()

function Invoke-AtGVerificationStage {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$ScriptBlock
    )

    $script:currentVerificationStage = $Name
    try {
        Measure-AtGStage -Summary $timing -Name $Name -ScriptBlock $ScriptBlock
        $script:verificationStageResults.Add([pscustomobject]@{
                Name = $Name
                Status = 'Passed'
                Error = $null
            }) | Out-Null
    }
    catch {
        $script:verificationStageResults.Add([pscustomobject]@{
                Name = $Name
                Status = 'Failed'
                Error = $_.Exception.Message
            }) | Out-Null
        throw
    }
}

function Write-AtGVerificationEvidence {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('Passed', 'Failed')][string]$Status,
        [string]$Failure = '',
        [bool]$PatchLeftInstalled = $false
    )

    $timingRows = @(
        foreach ($row in @(Get-AtGTimingReport -Summary $timing)) {
            [pscustomobject]@{
                Stage = [string]$row.Stage
                DurationMs = [int64]$row.DurationMs
                Percent = [double]$row.Percent
            }
        }
    )
    $selectedStatic = @(
        foreach ($test in @($verificationSelection.StaticTests)) {
            [pscustomobject]@{
                Id = [string]$test.Id
                Script = [string]$test.Script
                Triggers = @($test.Triggers)
            }
        }
    )
    $selectedDotNet = @(
        foreach ($group in @($verificationSelection.DotNetTestGroups)) {
            [pscustomobject]@{
                Id = [string]$group.Id
                Project = [string]$group.Project
                Triggers = @($group.Triggers)
            }
        }
    )
    $selectedSmoke = @(
        foreach ($test in @($verificationSelection.SmokeTests)) {
            [pscustomobject]@{
                Id = [string]$test.Id
                Script = [string]$test.Script
            }
        }
    )
    $result = [ordered]@{
        SchemaVersion = 1
        Id = 'verification-' + $verificationRunId
        Status = $Status
        Outcome = $Status
        Profile = $Profile
        GamePath = $resolvedGamePath
        RendererMode = $RendererMode
        StaticOnly = [bool]$StaticOnly
        DocumentationOnly = [bool]$documentationOnly
        ChangedPaths = @($verificationSelection.ChangedPaths)
        ChangedPathCategories = @($verificationSelection.ChangedPathCategories)
        UnmappedChangedPaths = @($verificationSelection.UnmappedChangedPaths)
        EnvironmentPrerequisites = @($verificationSelection.EnvironmentPrerequisites)
        SelectedChecks = [ordered]@{
            Static = $selectedStatic
            DotNet = $selectedDotNet
            Smoke = $selectedSmoke
        }
        StageResults = @($verificationStageResults.ToArray())
        Timing = $timingRows
        Smoke = $smokeResult
        PatchFiles = $finalPatchFiles.Count
        PatchLeftInstalled = $PatchLeftInstalled
        Recovery = $recoveryResult
        Failure = if ([string]::IsNullOrWhiteSpace($Failure)) { $null } else { $Failure }
        SnapshotPath = if ($Status -eq 'Failed' -and ![string]::IsNullOrWhiteSpace($snapshotRoot)) { $snapshotRoot } else { $null }
    }
    $json = ($result | ConvertTo-Json -Depth 16) -replace "`r`n", "`n"
    [IO.File]::WriteAllText($verificationEvidencePath, $json, (New-Object Text.UTF8Encoding($false)))
    return $verificationEvidencePath
}

function Invoke-AtGStaticTestSuite {
    param([Parameter(Mandatory = $true)][object]$Selection)

    $environmentNames = @(
        'ATG_GAME_PATH',
        'ATG_VERIFICATION_PROFILE',
        'ATG_VERIFICATION_SELECTED_TEST_IDS',
        'ATG_VERIFICATION_CHANGED_PATH_CATEGORIES'
    )
    $previousEnvironment = @{}
    foreach ($name in $environmentNames) {
        $previousEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
    }
    $allSelectedTests = @($Selection.StaticTests) + @($Selection.SmokeTests)
    $selectedTestIds = @($allSelectedTests | ForEach-Object { [string]$_.Id })
    try {
        [Environment]::SetEnvironmentVariable('ATG_GAME_PATH', $null, 'Process')
        [Environment]::SetEnvironmentVariable('ATG_VERIFICATION_PROFILE', [string]$Selection.Profile, 'Process')
        [Environment]::SetEnvironmentVariable('ATG_VERIFICATION_SELECTED_TEST_IDS', ($selectedTestIds -join ';'), 'Process')
        [Environment]::SetEnvironmentVariable('ATG_VERIFICATION_CHANGED_PATH_CATEGORIES',
            (@($Selection.ChangedPathCategories) -join ';'), 'Process')
        foreach ($group in @($Selection.DotNetTestGroups)) {
            $project = Join-Path $projectRoot ([string]$group.Project)
            if (!(Test-Path -LiteralPath $project -PathType Leaf)) {
                throw "Selected .NET test project is missing: $project"
            }
            Invoke-AtGVerificationStage -Name ('static/' + [string]$group.Id) -ScriptBlock {
                Invoke-AtGDotNet -Arguments @(
                    'test', $project, '-c', 'Release', '--no-restore', '-p:NuGetAudit=false'
                )
            }
        }
    }
    finally {
        foreach ($name in $environmentNames) {
            [Environment]::SetEnvironmentVariable($name, $previousEnvironment[$name], 'Process')
        }
    }
}

if ($documentationOnly) {
    Write-Host 'Documentation-only verification: running selected static checks without source capture, installation, or smoke.'
    try {
        Invoke-AtGStaticTestSuite -Selection $verificationSelection
        $smokeResult = 'Not applicable: documentation-only task.'
        $evidencePath = Write-AtGVerificationEvidence -Status Passed -PatchLeftInstalled $false
        [pscustomobject]@{
            GamePath = $null
            RendererMode = $RendererMode
            Profile = $Profile
            StaticOnly = [bool]$StaticOnly
            DocumentationOnly = $true
            ChangedPaths = @($verificationSelection.ChangedPaths)
            ChangedPathCategories = @($verificationSelection.ChangedPathCategories)
            UnmappedChangedPaths = @($verificationSelection.UnmappedChangedPaths)
            StaticChecks = @($verificationSelection.StaticTests | ForEach-Object { [string]$_.Id })
            DotNetTestGroups = @($verificationSelection.DotNetTestGroups | ForEach-Object { [string]$_.Id })
            Timing = @(Get-AtGTimingReport -Summary $timing)
            EvidencePath = $evidencePath
            PatchFiles = 0
            Smoke = $smokeResult
            PatchLeftInstalled = $false
        }
        return
    }
    catch {
        $failure = "Stage '$currentVerificationStage' failed: $($_.Exception.Message)"
        $recoveryResult = 'Not required: documentation-only verification does not mutate a game directory.'
        $evidencePath = Write-AtGVerificationEvidence -Status Failed -Failure $failure
        throw "Documentation-only verification failed: $($_.Exception.Message)`nEvidence: $evidencePath"
    }
}

Write-Host "Verification profile: $Profile"
Write-Host "Selected static checks: $($verificationSelection.StaticTests.Count); .NET groups: $($verificationSelection.DotNetTestGroups.Count)."
if ($verificationSelection.UnmappedChangedPaths.Count -gt 0) {
    Write-Warning "Changed paths without a profile mapping: $($verificationSelection.UnmappedChangedPaths -join '; '). Local core checks remain selected."
}

# Resolve locked test dependencies before creating any game snapshot or touching
# the selected game directory. A package-source outage must leave the game
# entirely untouched, rather than exercise rollback for a tooling-only failure.
try {
    Invoke-AtGVerificationStage -Name 'game-process-preflight' -ScriptBlock {
        Assert-AtGGameNotRunning -Operation 'verification'
    }
    Invoke-AtGVerificationStage -Name 'locked-restore' -ScriptBlock {
        Invoke-AtGDotNet -Arguments @(
            'restore', (Join-Path $projectRoot 'AtG.Patch.sln'), '--locked-mode', '--ignore-failed-sources', '-p:NuGetAudit=false'
        )
    }
}
catch {
    $evidencePath = Write-AtGVerificationEvidence -Status Failed -Failure $_.Exception.Message
    throw "Verification failed before any game transaction: $($_.Exception.Message)`nEvidence: $evidencePath"
}

$verificationBase = Join-Path $projectRoot '.tmp\verification\transactions'
$snapshotRoot = Join-Path $verificationBase $verificationRunId
$snapshotContentRoot = Join-Path $snapshotRoot 'files'
$snapshotTransactionRoot = Join-Path $snapshotRoot 'transaction-before'
New-Item -ItemType Directory -Force -Path $snapshotContentRoot, $snapshotTransactionRoot | Out-Null

function Get-AtGVerificationRelativePath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $fullPath = [IO.Path]::GetFullPath($Path)
    $gameRoot = $resolvedGamePath.TrimEnd([char[]]@('\', '/'))
    if (!$fullPath.StartsWith($gameRoot + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Verification snapshot path is outside the selected game directory: $fullPath"
    }
    return ConvertTo-AtGNormalizedRelativePath ($fullPath.Substring($gameRoot.Length).TrimStart([char[]]@('\', '/')))
}

function Add-AtGVerificationDirectoryState {
    param([Parameter(Mandatory = $true)][string]$FilePath)

    $gameRoot = $resolvedGamePath.TrimEnd([char[]]@('\', '/'))
    $directory = Split-Path -Parent ([IO.Path]::GetFullPath($FilePath))
    while (!([string]::IsNullOrWhiteSpace($directory)) -and
        !$directory.Equals($gameRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        if (!$directory.StartsWith($gameRoot + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Verification directory state is outside the selected game directory: $directory"
        }
        $relative = Get-AtGVerificationRelativePath $directory
        if (!$directoryStates.ContainsKey($relative)) {
            $directoryStates[$relative] = [pscustomobject]@{
                RelativePath = $relative
                Existed = Test-Path -LiteralPath $directory -PathType Container
            }
        }
        $directory = Split-Path -Parent $directory
    }
}

function Add-AtGVerificationSnapshotFile {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    $relative = ConvertTo-AtGNormalizedRelativePath $RelativePath
    if ($snapshotFiles.ContainsKey($relative)) {
        return
    }

    $target = Join-AtGRelativePath $resolvedGamePath $relative
    if (Test-Path -LiteralPath $target -PathType Container) {
        throw "Verification cannot snapshot a directory as a patch file target: $relative"
    }
    Add-AtGVerificationDirectoryState -FilePath $target

    $exists = Test-Path -LiteralPath $target -PathType Leaf
    $backupRelative = ('{0:D5}.bin' -f $snapshotFiles.Count)
    $backup = Join-Path $snapshotContentRoot $backupRelative
    $hash = $null
    if ($exists) {
        Copy-Item -LiteralPath $target -Destination $backup -Force
        $hash = Get-AtGFileSha256 -Path $backup
        if ([string]::IsNullOrWhiteSpace($hash)) {
            throw "Verification did not create a readable snapshot for: $relative"
        }
    }

    $snapshotFiles[$relative] = [pscustomobject]@{
        RelativePath = $relative
        Existed = [bool]$exists
        Sha256 = $hash
        BackupRelativePath = $backupRelative
    }
}

function Save-AtGVerificationTransactionArtifacts {
    if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
        Copy-Item -LiteralPath $manifestPath -Destination (Join-Path $snapshotTransactionRoot '.atg-chinese-patch.json') -Force
        $transactionState.ManifestExisted = $true
    }
    if (Test-Path -LiteralPath $backupBase -PathType Container) {
        Copy-Item -LiteralPath $backupBase -Destination $snapshotTransactionRoot -Recurse -Force
        $transactionState.BackupExisted = $true
    }
}

function Remove-AtGVerificationFileIfPresent {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (!(Test-Path -LiteralPath $Path -PathType Leaf)) {
        return
    }

    for ($attempt = 1; $attempt -le 10; $attempt++) {
        try {
            Remove-Item -LiteralPath $Path -Force
            return
        }
        catch {
            if ($attempt -ge 10 -or !(Test-AtGTransientFileWriteFailure -ErrorRecord $_)) {
                throw
            }
            $delayMilliseconds = [Math]::Min(800, 100 * [Math]::Pow(2, $attempt - 1))
            Write-Warning ("Verification recovery is waiting for a mapped file ({0}/{1}): {2}" -f `
                ($attempt + 1), 10, $Path)
            [GC]::Collect()
            [GC]::WaitForPendingFinalizers()
            Start-Sleep -Milliseconds ([int]$delayMilliseconds)
        }
    }
}

function Restore-AtGVerificationSnapshot {
    Write-Warning 'Verification failed; restoring the selected game directory to its pre-verification state.'

    foreach ($entry in @($snapshotFiles.Values | Sort-Object RelativePath)) {
        $target = Join-AtGRelativePath $resolvedGamePath ([string]$entry.RelativePath)
        if ($entry.Existed) {
            $backup = Join-Path $snapshotContentRoot ([string]$entry.BackupRelativePath)
            if (!(Test-Path -LiteralPath $backup -PathType Leaf)) {
                throw "Verification snapshot backup is missing: $backup"
            }
            # Copy-AtGFileIfChanged avoids a needless write when the failed
            # phase never modified this target and retries a transient mapped
            # executable rather than declaring rollback incomplete.
            Copy-AtGFileIfChanged -Source $backup -Destination $target | Out-Null
            if ((Get-AtGFileSha256 -Path $target) -ne [string]$entry.Sha256) {
                throw "Verification did not restore the pre-existing file exactly: $($entry.RelativePath)"
            }
        }
        elseif (Test-Path -LiteralPath $target -PathType Leaf) {
            Remove-AtGVerificationFileIfPresent -Path $target
        }
        elseif (Test-Path -LiteralPath $target -PathType Container) {
            throw "Verification refuses to remove a directory where a patch file was created: $target"
        }
    }

    # Transaction metadata and backups are part of the original state. Replace
    # the gate-created transaction only after all content targets are restored.
    if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
        Remove-AtGVerificationFileIfPresent -Path $manifestPath
    }
    if (Test-Path -LiteralPath $backupBase -PathType Container) {
        Remove-Item -LiteralPath $backupBase -Recurse -Force
    }
    if ($transactionState.ManifestExisted) {
        Copy-Item -LiteralPath (Join-Path $snapshotTransactionRoot '.atg-chinese-patch.json') -Destination $manifestPath -Force
    }
    if ($transactionState.BackupExisted) {
        Copy-Item -LiteralPath (Join-Path $snapshotTransactionRoot '_ChinesePatchBackup') -Destination $resolvedGamePath -Recurse -Force
    }

    foreach ($directory in @($directoryStates.Values | Where-Object { !$_.Existed } |
            Sort-Object { $_.RelativePath.Length } -Descending)) {
        $path = Join-AtGRelativePath $resolvedGamePath ([string]$directory.RelativePath)
        if ((Test-Path -LiteralPath $path -PathType Container) -and
            @(Get-ChildItem -LiteralPath $path -Force).Count -eq 0) {
            Remove-Item -LiteralPath $path -Force
        }
    }
}

function Invoke-AtGInstalledSmokeTest {
    param([Parameter(Mandatory = $true)][object]$Selection)

    Assert-AtGGameNotRunning -Operation 'starting the real-game smoke test'
    $environmentNames = @(
        'ATG_GAME_PATH',
        'ATG_VERIFICATION_PROFILE',
        'ATG_VERIFICATION_SELECTED_TEST_IDS',
        'ATG_VERIFICATION_CHANGED_PATH_CATEGORIES'
    )
    $previousEnvironment = @{}
    foreach ($name in $environmentNames) {
        $previousEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
    }
    $allSelectedTests = @($Selection.StaticTests) + @($Selection.SmokeTests)
    $selectedTestIds = @($allSelectedTests | ForEach-Object { [string]$_.Id })
    try {
        [Environment]::SetEnvironmentVariable('ATG_GAME_PATH', $resolvedGamePath, 'Process')
        [Environment]::SetEnvironmentVariable('ATG_VERIFICATION_PROFILE', [string]$Selection.Profile, 'Process')
        [Environment]::SetEnvironmentVariable('ATG_VERIFICATION_SELECTED_TEST_IDS', ($selectedTestIds -join ';'), 'Process')
        [Environment]::SetEnvironmentVariable('ATG_VERIFICATION_CHANGED_PATH_CATEGORIES',
            (@($Selection.ChangedPathCategories) -join ';'), 'Process')
        Invoke-AtGDotNet -Arguments @(
            'test', (Join-Path $projectRoot 'tools\AtG.ScriptIntegration.Tests\AtG.ScriptIntegration.Tests.csproj'),
            '-c', 'Release', '--no-restore',
            '--filter', 'FullyQualifiedName~RealGameSmokePassesWhenGateSuppliesGamePath',
            '-p:NuGetAudit=false'
        )
    }
    finally {
        foreach ($name in $environmentNames) {
            [Environment]::SetEnvironmentVariable($name, $previousEnvironment[$name], 'Process')
        }
    }
}

try {
    # Snapshot the currently installed transaction before asking it to restore
    # itself. This is what lets a failed gate return MOD content and an older
    # patch transaction byte-for-byte, rather than merely returning to vanilla.
    Invoke-AtGVerificationStage -Name 'transaction-snapshot' -ScriptBlock {
        Save-AtGVerificationTransactionArtifacts
        if (Test-Path -LiteralPath $patchRoot -PathType Container) {
            foreach ($file in @(Get-AtGPatchInventory -PatchRoot $patchRoot)) {
                Add-AtGVerificationSnapshotFile -RelativePath ([string]$file.RelativePath)
            }
        }
    }
    if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
        $script:gameMutationStarted = $true
        Invoke-AtGVerificationStage -Name 'restore-existing-transaction' -ScriptBlock {
            $existingManifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($entry in @(Get-AtGManifestEntries -Manifest $existingManifest)) {
                Add-AtGVerificationSnapshotFile -RelativePath ([string]$entry.RelativePath)
            }
            & (Join-Path $projectRoot 'Uninstall-ChinesePatch.ps1') -GamePath $resolvedGamePath `
                -SkipSaveNameCompatibility -NoSaveNameNotice
        }
    }
    elseif (Test-Path -LiteralPath $backupBase -PathType Container) {
        # A legacy or interrupted patch can have a backup without its manifest.
        # Recover it before using the directory as a development source.
        $script:gameMutationStarted = $true
        Invoke-AtGVerificationStage -Name 'restore-legacy-transaction' -ScriptBlock {
            & (Join-Path $projectRoot 'Uninstall-ChinesePatch.ps1') -GamePath $resolvedGamePath `
                -SkipSaveNameCompatibility -NoSaveNameNotice
        }
    }

    Invoke-AtGVerificationStage -Name 'source-capture' -ScriptBlock {
        & (Join-Path $projectRoot 'tools\Initialize-AtGSource.ps1') -GamePath $resolvedGamePath -Refresh
    }
    Invoke-AtGVerificationStage -Name 'build' -ScriptBlock {
        & (Join-Path $projectRoot 'tools\Build-Patch.ps1') -PatchRoot $patchRoot -RendererMode $RendererMode
    }

    # The final patch can add an artifact after a previous installation. Record
    # its now-restored pre-install state before the new transaction touches it.
    Invoke-AtGVerificationStage -Name 'transaction-inventory' -ScriptBlock {
        $script:finalPatchFiles = @(Get-AtGPatchInventory -PatchRoot $patchRoot)
        foreach ($file in $script:finalPatchFiles) {
            Add-AtGVerificationSnapshotFile -RelativePath ([string]$file.RelativePath)
        }
    }

    Invoke-AtGStaticTestSuite -Selection $verificationSelection

    $script:gameMutationStarted = $true
    Invoke-AtGVerificationStage -Name 'install' -ScriptBlock {
        & (Join-Path $projectRoot 'Install-ChinesePatch.ps1') -GamePath $resolvedGamePath -NoInstallNotice
        if (!(Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
            throw 'Transactional installation did not create its manifest.'
        }
        $installedManifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if (!(Test-AtGManifestInstalledState -GamePath $resolvedGamePath -Manifest $installedManifest)) {
            throw 'Transactional installation did not leave a complete, hash-verified installed patch state.'
        }
    }

    $smokeResult = if ($StaticOnly) {
        'Skipped by explicit -StaticOnly.'
    }
    else {
        Invoke-AtGVerificationStage -Name 'smoke' -ScriptBlock {
            Invoke-AtGInstalledSmokeTest -Selection $verificationSelection
        }
        'Passed via xUnit real-game main-menu smoke.'
    }

    $evidencePath = Write-AtGVerificationEvidence -Status Passed -PatchLeftInstalled $true
    if (Test-Path -LiteralPath $snapshotRoot) {
        try {
            Remove-Item -LiteralPath $snapshotRoot -Recurse -Force
        }
        catch {
            Write-Warning "Verification passed, but the rollback snapshot was retained: $snapshotRoot. $($_.Exception.Message)"
        }
    }
    [pscustomobject]@{
        GamePath = $resolvedGamePath
        RendererMode = $RendererMode
        Profile = $Profile
        StaticOnly = [bool]$StaticOnly
        ChangedPaths = @($verificationSelection.ChangedPaths)
        ChangedPathCategories = @($verificationSelection.ChangedPathCategories)
        UnmappedChangedPaths = @($verificationSelection.UnmappedChangedPaths)
        StaticChecks = @($verificationSelection.StaticTests | ForEach-Object { [string]$_.Id })
        DotNetTestGroups = @($verificationSelection.DotNetTestGroups | ForEach-Object { [string]$_.Id })
        Timing = @(Get-AtGTimingReport -Summary $timing)
        EvidencePath = $evidencePath
        PatchFiles = $finalPatchFiles.Count
        Smoke = $smokeResult
        PatchLeftInstalled = $true
    }
}
catch {
    $verificationError = $_
    $recoveryFailure = $null
    if ($gameMutationStarted) {
        try {
            Invoke-AtGVerificationStage -Name 'recovery' -ScriptBlock {
                Restore-AtGVerificationSnapshot
            }
            $recoveryResult = 'Passed: selected game directory restored to its pre-verification state.'
        }
        catch {
            $recoveryFailure = $_
            $recoveryResult = 'Failed: ' + $_.Exception.Message
        }
    }
    else {
        $recoveryResult = 'Not required: verification failed before mutating the selected game directory.'
    }

    $failure = "Stage '$currentVerificationStage' failed: $($verificationError.Exception.Message)"
    $evidencePath = Write-AtGVerificationEvidence -Status Failed -Failure $failure
    if ($null -ne $recoveryFailure) {
        throw "Verification failed: $($verificationError.Exception.Message)`nRecovery also failed: $($recoveryFailure.Exception.Message)`nSnapshot retained at: $snapshotRoot`nEvidence: $evidencePath"
    }
    if ($gameMutationStarted) {
        throw "Verification failed and the selected game directory was restored: $($verificationError.Exception.Message)`nEvidence: $evidencePath"
    }
    throw "Verification failed before mutating the selected game directory: $($verificationError.Exception.Message)`nEvidence: $evidencePath"
}
