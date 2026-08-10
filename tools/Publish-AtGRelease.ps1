[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$GamePath,

    [string]$Remote = 'origin',

    [string]$ReleaseBranch = 'codex/release-chinese-patch',

    [ValidateSet('MergedFonts', 'DynamicCjk')]
    [string]$RendererMode = 'DynamicCjk'
)

$ErrorActionPreference = 'Stop'

$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$releaseRoot = Join-Path $projectRoot '.tmp\release-publish'
$packageRoot = Join-Path $releaseRoot 'package'
$historyRoot = Join-Path $releaseRoot 'history'

function Invoke-AtGGit {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [string]$WorkingDirectory = $projectRoot,
        [switch]$AllowFailure
    )

    & git -C $WorkingDirectory @Arguments
    $exitCode = $LASTEXITCODE
    if (!$AllowFailure -and $exitCode -ne 0) {
        throw "git $($Arguments -join ' ') failed with exit code $exitCode."
    }
    return $exitCode
}

function Get-AtGGitText {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [string]$WorkingDirectory = $projectRoot
    )

    $output = & git -C $WorkingDirectory @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed with exit code $LASTEXITCODE."
    }
    return (($output | Out-String).Trim())
}

function Assert-AtGCleanSynchronizedMain {
    $branch = Get-AtGGitText -Arguments @('branch', '--show-current')
    if ($branch -ne 'main') {
        throw "Publishing is allowed only from main; current branch is '$branch'."
    }
    $status = Get-AtGGitText -Arguments @('status', '--porcelain')
    if (!([string]::IsNullOrWhiteSpace($status))) {
        throw "Publishing requires a clean main worktree.\n$status"
    }

    Invoke-AtGGit -Arguments @('fetch', $Remote, 'main') | Out-Null
    $head = Get-AtGGitText -Arguments @('rev-parse', 'HEAD')
    $remoteHead = Get-AtGGitText -Arguments @('rev-parse', "$Remote/main")
    if ($head -ne $remoteHead) {
        throw "Publishing requires main to exactly match $Remote/main. Local=$head Remote=$remoteHead"
    }
    return $head
}

function Get-AtGRemoteReleaseSha {
    param([Parameter(Mandatory = $true)][string]$RemoteUrl)

    $lines = & git ls-remote --heads $RemoteUrl ("refs/heads/{0}" -f $ReleaseBranch)
    if ($LASTEXITCODE -ne 0) {
        throw "Could not inspect remote release branch '$ReleaseBranch'."
    }
    $line = @($lines | Select-Object -First 1)
    if ($line.Count -eq 0 -or [string]::IsNullOrWhiteSpace([string]$line[0])) {
        # The all-zero expected value makes --force-with-lease require that a
        # previously absent release branch is still absent at push time.
        return '0000000000000000000000000000000000000000'
    }
    return ([string]$line[0]).Split([char[]]@("`t", ' '), [System.StringSplitOptions]::RemoveEmptyEntries)[0]
}

function Assert-AtGReleaseTree {
    param([Parameter(Mandatory = $true)][string]$Path)

    $rootFiles = @(Get-ChildItem -LiteralPath $Path -File | Select-Object -ExpandProperty Name | Sort-Object)
    $expectedRootFiles = @('Install-ChinesePatch.ps1', 'README.md', 'Uninstall-ChinesePatch.ps1')
    if (($rootFiles -join '|') -ne ($expectedRootFiles -join '|')) {
        throw "Release root violates the minimal whitelist: $($rootFiles -join ', ')"
    }
    $rootDirectories = @(Get-ChildItem -LiteralPath $Path -Directory | Select-Object -ExpandProperty Name | Sort-Object)
    if (($rootDirectories -join '|') -ne 'patch') {
        throw "Release root contains development directories: $($rootDirectories -join ', ')"
    }
    if (@(Get-ChildItem -LiteralPath (Join-Path $Path 'patch') -Recurse -File).Count -eq 0) {
        throw 'Release package has no installable patch files.'
    }
}

try {
    if (!(Get-Command git -ErrorAction SilentlyContinue)) {
        throw 'git is required to publish the release branch.'
    }
    $mainSha = Assert-AtGCleanSynchronizedMain
    $remoteUrl = Get-AtGGitText -Arguments @('remote', 'get-url', $Remote)
    $leaseSha = Get-AtGRemoteReleaseSha -RemoteUrl $remoteUrl

    & (Join-Path $projectRoot 'tools\Invoke-AtGVerification.ps1') -GamePath $GamePath -RendererMode $RendererMode -Profile Release

    # The full gate is expected to be reproducible from an already clean main.
    # Do not publish generated or accidental local changes under a trusted SHA.
    $postGateStatus = Get-AtGGitText -Arguments @('status', '--porcelain')
    if (!([string]::IsNullOrWhiteSpace($postGateStatus))) {
        throw "The verification gate changed the tracked main worktree; review and commit those changes before publishing.\n$postGateStatus"
    }

    if (Test-Path -LiteralPath $releaseRoot) {
        Remove-Item -LiteralPath $releaseRoot -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $releaseRoot | Out-Null
    & (Join-Path $projectRoot 'tools\Export-ReleasePackage.ps1') -SourceRoot $projectRoot -OutputPath $packageRoot
    Assert-AtGReleaseTree -Path $packageRoot

    Copy-Item -LiteralPath $packageRoot -Destination $historyRoot -Recurse -Force
    Invoke-AtGGit -WorkingDirectory $historyRoot -Arguments @('init', '--initial-branch', 'release') | Out-Null
    $authorName = Get-AtGGitText -WorkingDirectory $projectRoot -Arguments @('config', 'user.name')
    $authorEmail = Get-AtGGitText -WorkingDirectory $projectRoot -Arguments @('config', 'user.email')
    Invoke-AtGGit -WorkingDirectory $historyRoot -Arguments @('add', '--all') | Out-Null
    $patchFileCount = @(Get-ChildItem -LiteralPath (Join-Path $historyRoot 'patch') -Recurse -File).Count
    $commitMessage = "Release Chinese patch from main $mainSha ($patchFileCount patch files)"
    Invoke-AtGGit -WorkingDirectory $historyRoot -Arguments @(
        '-c', "user.name=$authorName", '-c', "user.email=$authorEmail", 'commit', '-m', $commitMessage
    ) | Out-Null
    $releaseSha = Get-AtGGitText -WorkingDirectory $historyRoot -Arguments @('rev-parse', 'HEAD')

    # Re-read the remote head immediately before pushing. The exact lease value
    # prevents a concurrent release from being overwritten silently.
    $currentLeaseSha = Get-AtGRemoteReleaseSha -RemoteUrl $remoteUrl
    if ($currentLeaseSha -ne $leaseSha) {
        throw "Remote $ReleaseBranch changed while the local gate was running; refusing to overwrite it."
    }
    $leaseArgument = "--force-with-lease=refs/heads/$ReleaseBranch`:$leaseSha"
    Invoke-AtGGit -WorkingDirectory $historyRoot -Arguments @(
        'push', $leaseArgument, $remoteUrl, "HEAD:refs/heads/$ReleaseBranch"
    ) | Out-Null

    [pscustomobject]@{
        SourceMainSha = $mainSha
        ReleaseBranch = $ReleaseBranch
        ReleaseCommitSha = $releaseSha
        PatchFileCount = $patchFileCount
        Remote = $Remote
        Pushed = $true
    }
}
finally {
    if (Test-Path -LiteralPath $releaseRoot) {
        Remove-Item -LiteralPath $releaseRoot -Recurse -Force
    }
}
