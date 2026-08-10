param(
    [string]$GamePath,
    [switch]$InstallFonts,
    [switch]$PreserveFonts,
    [switch]$NoInstallNotice
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\tools\AtGPaths.ps1"
. "$PSScriptRoot\tools\AtGPatchManifest.ps1"
. "$PSScriptRoot\tools\AtGPatchNotice.ps1"

$GamePath = Resolve-AtGGamePath $GamePath
Assert-AtGGameNotRunning -Operation 'installing or refreshing the Chinese patch'
$patchRoot = Join-Path $PSScriptRoot "patch"
$patchText = Join-Path $patchRoot "Content\Text\English.xml"
if (!(Test-Path -LiteralPath $patchText -PathType Leaf)) {
    throw "Patch content not found. The patch package is incomplete."
}

if (!$NoInstallNotice) {
    Show-AtGInstallationNotice
}

$manifestPath = Join-Path $GamePath ".atg-chinese-patch.json"
$backupBase = Join-Path $GamePath "_ChinesePatchBackup"
if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
    $existingManifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $existingBackupRoot = [string]$existingManifest.BackupRoot
    if (!(Test-Path -LiteralPath $existingBackupRoot -PathType Container) -and
        (Test-AtGManifestRestoredState -GamePath $GamePath -Manifest $existingManifest)) {
        # An interrupted final cleanup can leave only a terminal manifest after
        # every game file was restored.  It is not an active transaction and
        # must not block a fresh install (notably the runtime text assembly).
        Remove-Item -LiteralPath $manifestPath -Force
        if ((Test-Path -LiteralPath $backupBase -PathType Container) -and
            @((Get-ChildItem -LiteralPath $backupBase -Force)).Count -eq 0) {
            Remove-Item -LiteralPath $backupBase -Force
        }
        Write-Warning "Removed a completed stale Chinese patch manifest before refresh."
    }
    else {
        Write-Host "Existing Chinese patch transaction found. Restoring its pre-install state before refresh..."
        & (Join-Path $PSScriptRoot "Uninstall-ChinesePatch.ps1") -GamePath $GamePath -SkipSaveNameCompatibility -NoSaveNameNotice
        Write-Host "Previous Chinese patch restored. Installing refreshed patch..."
    }
}
elseif (Test-Path -LiteralPath $backupBase -PathType Container) {
    $recoverableBackup = @(Get-ChildItem -LiteralPath $backupBase -Directory |
        Where-Object { Test-Path -LiteralPath (Join-AtGRelativePath $_.FullName "Content\Text\English.xml") } |
        Sort-Object Name |
        Select-Object -First 1)
    if ($recoverableBackup.Count -gt 0) {
        Write-Warning "A previous Chinese patch backup has no manifest. Restoring it before installing a new patch."
        & (Join-Path $PSScriptRoot "Uninstall-ChinesePatch.ps1") -GamePath $GamePath -SkipSaveNameCompatibility -NoSaveNameNotice
    }
    else {
        Write-Host "No recoverable Chinese patch transaction found. Installing patch..."
    }
}
else {
    Write-Host "No existing Chinese patch transaction found. Installing patch..."
}

function Test-AtGFontPatchFile {
    param([string]$RelativePath)

    $normalized = $RelativePath -replace "/", "\"
    return $normalized.StartsWith("Content\Images\Interface\Components\Fonts\", [System.StringComparison]::OrdinalIgnoreCase)
}

function Ensure-AtGTargetDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$Directory,
        [Parameter(Mandatory = $true)][string]$GameRoot,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.HashSet[string]]$CreatedDirectories
    )

    $missing = New-Object 'System.Collections.Generic.List[string]'
    $current = [IO.Path]::GetFullPath($Directory)
    $resolvedGameRoot = [IO.Path]::GetFullPath($GameRoot).TrimEnd([char[]]@('\', '/'))
    while (!(Test-Path -LiteralPath $current -PathType Container)) {
        if (!$current.StartsWith($resolvedGameRoot + "\", [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to create a patch directory outside the game root: $current"
        }
        $missing.Add($current)
        $parent = Split-Path -Parent $current
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $current) {
            throw "Could not find an existing parent directory for: $Directory"
        }
        $current = $parent
    }

    for ($missingIndex = $missing.Count - 1; $missingIndex -ge 0; $missingIndex--) {
        $path = $missing[$missingIndex]
        New-Item -ItemType Directory -Force -Path $path | Out-Null
        $relative = ConvertTo-AtGNormalizedRelativePath ($path.Substring($resolvedGameRoot.Length).TrimStart([char[]]@('\', '/')))
        [void]$CreatedDirectories.Add($relative)
    }
}

$fontMarkerRelative = "Content\Images\Interface\Components\Fonts\.atg-merged-fonts"
$fontMarker = Join-AtGRelativePath $patchRoot $fontMarkerRelative
$shouldInstallFonts = ($InstallFonts -or (Test-Path -LiteralPath $fontMarker)) -and !$PreserveFonts

$allPatchFiles = @(Get-AtGPatchInventory -PatchRoot $patchRoot)
if ($allPatchFiles.Count -eq 0) {
    throw "Patch package contains no installable files: $patchRoot"
}

$files = @()
foreach ($file in $allPatchFiles) {
    $relative = [string]$file.RelativePath
    if (($relative -replace "/", "\") -eq $fontMarkerRelative) {
        continue
    }
    if ((Test-AtGFontPatchFile $relative) -and !$shouldInstallFonts) {
        continue
    }
    $files += $file
}

if ($files.Count -eq 0) {
    throw "Patch package contains no files selected for installation."
}

if (@($allPatchFiles | Where-Object { (Test-AtGFontPatchFile ([string]$_.RelativePath)) -and !$shouldInstallFonts }).Count -gt 0) {
    Write-Host "Skipping SpriteFont files to preserve the game's embedded icon glyphs. Build merged fonts first or pass -InstallFonts to override."
}

$transactionId = [Guid]::NewGuid().ToString("N")
$backupRoot = Join-Path $backupBase ((Get-Date -Format "yyyyMMdd-HHmmss") + "-" + $transactionId.Substring(0, 8))
New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null

$createdDirectories = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
$manifestFiles = @()
foreach ($file in $files) {
    $relative = ConvertTo-AtGNormalizedRelativePath ([string]$file.RelativePath)
    $target = Join-AtGRelativePath $GamePath $relative
    if (Test-Path -LiteralPath $target -PathType Container) {
        throw "Refusing to replace a directory with a patch file: $relative"
    }

    $backupRelative = $relative
    $backup = Join-AtGRelativePath $backupRoot $backupRelative
    $hadOriginal = Test-Path -LiteralPath $target -PathType Leaf
    if ($hadOriginal) {
        $backupDirectory = Split-Path -Parent $backup
        if ($backupDirectory) {
            New-Item -ItemType Directory -Force -Path $backupDirectory | Out-Null
        }
        Copy-Item -LiteralPath $target -Destination $backup -Force
        $backupHash = Get-AtGFileSha256 -Path $backup
        if ([string]::IsNullOrWhiteSpace($backupHash)) {
            throw "Could not verify backup created for: $relative"
        }
    }
    else {
        $backupHash = $null
    }

    $manifestFiles += [pscustomobject]@{
        RelativePath        = $relative
        HadOriginal         = [bool]$hadOriginal
        OriginalSha256      = $backupHash
        BackupRelativePath  = $backupRelative
        PatchSha256         = [string]$file.PatchSha256
        PatchExclusive      = [bool](-not $hadOriginal)
        TransactionState    = "Prepared"
        Installed           = $null
    }
}

$manifest = [pscustomobject]@{
    SchemaVersion       = 3
    Name                = "At the Gates Chinese Patch"
    TransactionId       = $transactionId
    InstallState        = "Prepared"
    Prepared            = (Get-Date).ToString("s")
    Installed           = $null
    LastUpdated         = (Get-Date).ToString("s")
    GamePath            = (Resolve-Path -LiteralPath $GamePath).Path
    BackupRoot          = $backupRoot
    CreatedDirectories  = @()
    Files               = $manifestFiles
}

# The prepared manifest is durable before the first game file is overwritten.
# If the process stops at any following copy, uninstall can still restore every
# recorded path to exactly the state captured above.
Write-AtGPatchManifest -ManifestPath $manifestPath -Manifest $manifest

try {
    $manifest.InstallState = "Installing"
    $manifest.LastUpdated = (Get-Date).ToString("s")
    Write-AtGPatchManifest -ManifestPath $manifestPath -Manifest $manifest

    for ($index = 0; $index -lt $files.Count; $index++) {
        $file = $files[$index]
        $relative = [string]$file.RelativePath
        $target = Join-AtGRelativePath $GamePath $relative
        $targetDirectory = Split-Path -Parent $target
        if ($targetDirectory) {
            Ensure-AtGTargetDirectory -Directory $targetDirectory -GameRoot $GamePath -CreatedDirectories $createdDirectories
        }
        $manifest.CreatedDirectories = @($createdDirectories | Sort-Object)
        $manifest.LastUpdated = (Get-Date).ToString("s")
        Write-AtGPatchManifest -ManifestPath $manifestPath -Manifest $manifest

        Copy-Item -LiteralPath $file.SourcePath -Destination $target -Force
        $actualHash = Get-AtGFileSha256 -Path $target
        if ($actualHash -ne $file.PatchSha256) {
            throw "Installed patch file hash does not match the planned artifact: $relative"
        }

        $manifest.Files[$index].TransactionState = "Installed"
        $manifest.Files[$index].Installed = (Get-Date).ToString("s")
        $manifest.LastUpdated = (Get-Date).ToString("s")
        Write-AtGPatchManifest -ManifestPath $manifestPath -Manifest $manifest
    }

    $manifest.InstallState = "Installed"
    $manifest.Installed = (Get-Date).ToString("s")
    $manifest.LastUpdated = (Get-Date).ToString("s")
    if (!(Test-AtGManifestInstalledState -GamePath $GamePath -Manifest $manifest)) {
        throw "Patch transaction cannot be finalized because one or more installed files are missing or have an unexpected hash."
    }
    Write-AtGPatchManifest -ManifestPath $manifestPath -Manifest $manifest
}
catch {
    $manifest.InstallState = "Interrupted"
    $manifest.LastUpdated = (Get-Date).ToString("s")
    $manifest | Add-Member -NotePropertyName Failure -NotePropertyValue $_.Exception.Message -Force
    try {
        Write-AtGPatchManifest -ManifestPath $manifestPath -Manifest $manifest
    }
    catch {
        Write-Warning "Could not update the interrupted-install manifest: $($_.Exception.Message)"
    }
    throw
}

Write-Host "Chinese patch installed transactionally."
Write-Host "Backup: $backupRoot"
Write-Host "Manifest: $manifestPath"
