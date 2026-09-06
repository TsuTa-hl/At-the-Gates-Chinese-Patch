param(
    [string]$GamePath,
    [switch]$InstallFonts,
    [switch]$PreserveFonts,
    [switch]$NoInstallNotice
)

$ErrorActionPreference = "Stop"
# Inlined release dependency: tools\AtGPaths.ps1
function Test-AtGGamePath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $false
    }

    $exe = Join-Path $Path "At The Gates.exe"
    $text = Join-Path $Path "Content\Text\English.xml"
    return ((Test-Path -LiteralPath $exe) -and (Test-Path -LiteralPath $text))
}

function Get-SteamLibraryPaths {
    $roots = New-Object System.Collections.Generic.List[string]

    foreach ($name in "ATG_STEAM_PATH", "STEAM_PATH", "STEAM_DIR") {
        $value = [Environment]::GetEnvironmentVariable($name)
        if (![string]::IsNullOrWhiteSpace($value) -and (Test-Path -LiteralPath $value)) {
            $roots.Add($value)
        }
    }

    foreach ($registryPath in "HKCU:\Software\Valve\Steam", "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam", "HKLM:\SOFTWARE\Valve\Steam") {
        try {
            $props = Get-ItemProperty -Path $registryPath -ErrorAction Stop
            foreach ($prop in "SteamPath", "InstallPath") {
                if ($props.$prop -and (Test-Path -LiteralPath $props.$prop)) {
                    $roots.Add([string]$props.$prop)
                }
            }
        }
        catch {
        }
    }

    $programFilesX86 = [Environment]::GetFolderPath("ProgramFilesX86")
    if (![string]::IsNullOrWhiteSpace($programFilesX86)) {
        $defaultSteam = Join-Path $programFilesX86 "Steam"
        if (Test-Path -LiteralPath $defaultSteam) {
            $roots.Add($defaultSteam)
        }
    }

    $libraries = New-Object System.Collections.Generic.List[string]
    foreach ($root in @($roots | Select-Object -Unique)) {
        $libraries.Add($root)
        $libraryFile = Join-Path $root "steamapps\libraryfolders.vdf"
        if (!(Test-Path -LiteralPath $libraryFile)) {
            continue
        }

        $content = Get-Content -LiteralPath $libraryFile -Raw -Encoding UTF8
        foreach ($match in [regex]::Matches($content, '"path"\s+"([^"]+)"')) {
            $path = $match.Groups[1].Value -replace "\\\\", "\"
            if (Test-Path -LiteralPath $path) {
                $libraries.Add($path)
            }
        }
    }

    return @($libraries | Select-Object -Unique)
}

function Resolve-AtGGamePath {
    param([string]$GamePath)

    $candidates = New-Object System.Collections.Generic.List[string]

    if (![string]::IsNullOrWhiteSpace($GamePath)) {
        $candidates.Add($GamePath)
    }

    foreach ($name in "ATG_GAME_PATH", "AT_THE_GATES_PATH") {
        $value = [Environment]::GetEnvironmentVariable($name)
        if (![string]::IsNullOrWhiteSpace($value)) {
            $candidates.Add($value)
        }
    }

    foreach ($library in Get-SteamLibraryPaths) {
        $candidates.Add((Join-Path $library "steamapps\common\Jon Shafer's At the Gates"))
    }

    foreach ($candidate in @($candidates | Select-Object -Unique)) {
        if (Test-AtGGamePath $candidate) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    throw @"
Could not find Jon Shafer's At the Gates.
Set ATG_GAME_PATH to the game folder or pass -GamePath explicitly.
Example:
  `$env:ATG_GAME_PATH = 'D:\SteamLibrary\steamapps\common\Jon Shafer''s At the Gates'
"@
}

function Get-AtGGameProcesses {
    # The Steam executable normally reports its process name as "At The Gates",
    # but some launchers and diagnostic tools expose the assembly-style name.
    # Treat either as an active game before modifying its installation.
    return @(Get-Process -Name @("At The Gates", "AtTheGates") -ErrorAction SilentlyContinue)
}

function Assert-AtGGameNotRunning {
    param(
        [string]$Operation = "modifying the At the Gates installation"
    )

    $running = @(Get-AtGGameProcesses)
    if ($running.Count -eq 0) {
        return
    }

    $details = ($running | ForEach-Object {
            "{0} (PID {1})" -f $_.ProcessName, $_.Id
        }) -join ", "
    throw "Close At the Gates before $Operation. Active process(es): $details"
}

function Join-AtGRelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    if ([IO.Path]::IsPathRooted($RelativePath) -or $RelativePath.Split([char[]]@("\", "/")) -contains "..") {
        throw "Unsafe relative path in patch manifest: $RelativePath"
    }

    return Join-Path $Root $RelativePath
}

# Inlined release dependency: tools\AtGPatchManifest.ps1
# Inlined release dependency: tools\AtGLegacyPatchOwnership.ps1
Set-StrictMode -Version Latest

# These files were introduced by released Chinese-patch revisions rather than by
# At the Gates itself.  Keep this small registry with the installer so an old
# or incomplete manifest can still be removed without guessing from a player's
# version, Steam build, or file hashes.
$script:AtGLegacyPatchOnlyExactPaths = @(
    '.atg-build-report.json',
    'AtG.RuntimeText.dll',
    'Content\Text\AtG.RuntimeText.tsv',
    'Content\Fonts\AtG.RuntimeGlyphWarmset.tsv',
    'Content\Fonts\NotoSansSC-Bold.otf',
    'Content\Fonts\NotoSansSC-Regular.otf',
    'Content\Fonts\OFL.txt',
    'Content\Images\Interface\Components\Fonts\.atg-merged-fonts'
)

function Get-AtGLegacyPatchOnlyEntries {
    [CmdletBinding()]
    param()

    return @($script:AtGLegacyPatchOnlyExactPaths | ForEach-Object {
        [pscustomobject]@{
            RelativePath = $_
            Reason = 'HistoricalChinesePatchArtifact'
        }
    })
}

function Test-AtGLegacyPatchOnlyArtifact {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    $normalized = $RelativePath.Trim().Replace([char]'/', [char]'\')
    if ($normalized -in $script:AtGLegacyPatchOnlyExactPaths) {
        return $true
    }

    # Earlier builds used Chinese-named ClanCard alias directories. They are
    # deterministic patch artifacts, whereas the six original English
    # discipline directories are game assets and must never be removed here.
    $parts = $normalized.Split([char[]]@('\'))
    return $parts.Count -ge 7 -and
        $parts[0] -eq 'Content' -and
        $parts[1] -eq 'Images' -and
        $parts[2] -eq 'Interface' -and
        $parts[3] -eq 'ScreenSpecific' -and
        $parts[4] -eq 'ClanCard' -and
        $parts[5] -match '[\u4E00-\u9FFF]'
}


function ConvertTo-AtGNormalizedRelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    if ([string]::IsNullOrWhiteSpace($RelativePath)) {
        throw "Patch manifest contains an empty relative path."
    }

    $normalized = $RelativePath.Trim().Replace([char]'/', [char]'\')
    if ([IO.Path]::IsPathRooted($normalized)) {
        throw "Patch manifest contains an absolute path: $RelativePath"
    }

    foreach ($segment in $normalized.Split([char[]]@('\'))) {
        if ([string]::IsNullOrWhiteSpace($segment) -or $segment -eq "." -or $segment -eq "..") {
            throw "Patch manifest contains an unsafe relative path: $RelativePath"
        }
    }

    return $normalized
}

function Get-AtGFileSha256 {
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )

    if (!(Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }

    return [string](Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Get-AtGPatchInventory {
    param(
        [Parameter(Mandatory = $true)][string]$PatchRoot
    )

    if (!(Test-Path -LiteralPath $PatchRoot -PathType Container)) {
        throw "Patch root not found: $PatchRoot"
    }

    $resolvedPatchRoot = (Resolve-Path -LiteralPath $PatchRoot).Path.TrimEnd([char[]]@('\', '/'))
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $inventory = @()

    foreach ($file in @(Get-ChildItem -LiteralPath $resolvedPatchRoot -Recurse -File | Sort-Object FullName)) {
        $relative = ConvertTo-AtGNormalizedRelativePath ($file.FullName.Substring($resolvedPatchRoot.Length).TrimStart([char[]]@('\', '/')))
        if ($relative.StartsWith('.atg-', [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }
        if (!$seen.Add($relative)) {
            throw "Patch root contains duplicate relative path: $relative"
        }

        $inventory += [pscustomobject]@{
            RelativePath = $relative
            SourcePath   = $file.FullName
            PatchSha256  = Get-AtGFileSha256 -Path $file.FullName
        }
    }

    return @($inventory)
}

function ConvertTo-AtGManifestBoolean {
    param(
        [Parameter(Mandatory = $true)][object]$Value,
        [Parameter(Mandatory = $true)][string]$FieldName
    )

    if ($Value -is [bool]) {
        return [bool]$Value
    }

    if ($Value -is [string]) {
        if ($Value -match '^(?i:true|1)$') {
            return $true
        }
        if ($Value -match '^(?i:false|0)$') {
            return $false
        }
    }

    throw "Patch manifest has an invalid boolean value for $FieldName."
}

function Get-AtGManifestEntries {
    param(
        [Parameter(Mandatory = $true)][object]$Manifest
    )

    if ($null -eq $Manifest.PSObject.Properties['Files']) {
        throw "Patch manifest does not contain a Files collection."
    }

    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $entries = @()
    foreach ($file in @($Manifest.Files)) {
        if ($null -eq $file) {
            throw "Patch manifest contains an empty file entry."
        }

        $relative = ConvertTo-AtGNormalizedRelativePath ([string]$file.RelativePath)
        if (!$seen.Add($relative)) {
            throw "Patch manifest contains duplicate file entry: $relative"
        }
        if ($null -eq $file.PSObject.Properties['HadOriginal']) {
            throw "Patch manifest does not record whether $relative had an original file."
        }

        $entries += [pscustomobject]@{
            RelativePath    = $relative
            HadOriginal     = ConvertTo-AtGManifestBoolean -Value $file.HadOriginal -FieldName "Files[$relative].HadOriginal"
            OriginalSha256  = if ($null -ne $file.PSObject.Properties['OriginalSha256']) { [string]$file.OriginalSha256 } else { $null }
            PatchSha256     = if ($null -ne $file.PSObject.Properties['PatchSha256']) { [string]$file.PatchSha256 } else { $null }
            BackupRelativePath = if ($null -ne $file.PSObject.Properties['BackupRelativePath']) {
                ConvertTo-AtGNormalizedRelativePath ([string]$file.BackupRelativePath)
            } else {
                $relative
            }
            PatchExclusive = if ($null -ne $file.PSObject.Properties['PatchExclusive']) {
                ConvertTo-AtGManifestBoolean -Value $file.PatchExclusive -FieldName "Files[$relative].PatchExclusive"
            } else {
                -not (ConvertTo-AtGManifestBoolean -Value $file.HadOriginal -FieldName "Files[$relative].HadOriginal")
            }
            TransactionState = if ($null -ne $file.PSObject.Properties['TransactionState']) {
                [string]$file.TransactionState
            } else {
                'Legacy'
            }
            RecoverySource  = 'Manifest'
        }
    }

    return @($entries)
}

function Test-AtGManifestRestoredState {
    param(
        [Parameter(Mandatory = $true)][string]$GamePath,
        [Parameter(Mandatory = $true)][object]$Manifest
    )

    try {
        $entries = @(Get-AtGManifestEntries -Manifest $Manifest)
        if ($entries.Count -eq 0) {
            return $false
        }

        foreach ($entry in $entries) {
            if (![string]::Equals([string]$entry.TransactionState, 'Restored', [System.StringComparison]::OrdinalIgnoreCase)) {
                return $false
            }

            $target = Join-AtGRelativePath $GamePath ([string]$entry.RelativePath)
            if ($entry.HadOriginal) {
                if ([string]::IsNullOrWhiteSpace([string]$entry.OriginalSha256) -or
                    !(Test-Path -LiteralPath $target -PathType Leaf) -or
                    (Get-AtGFileSha256 -Path $target) -ne [string]$entry.OriginalSha256) {
                    return $false
                }
            }
            elseif (Test-Path -LiteralPath $target) {
                return $false
            }
        }

        return $true
    }
    catch {
        return $false
    }
}

function Test-AtGManifestInstalledState {
    param(
        [Parameter(Mandatory = $true)][string]$GamePath,
        [Parameter(Mandatory = $true)][object]$Manifest
    )

    try {
        $entries = @(Get-AtGManifestEntries -Manifest $Manifest)
        if ($entries.Count -eq 0 -or
            ![string]::Equals([string]$Manifest.InstallState, 'Installed', [System.StringComparison]::OrdinalIgnoreCase)) {
            return $false
        }

        foreach ($entry in $entries) {
            if (![string]::Equals([string]$entry.TransactionState, 'Installed', [System.StringComparison]::OrdinalIgnoreCase) -or
                [string]::IsNullOrWhiteSpace([string]$entry.PatchSha256)) {
                return $false
            }

            $target = Join-AtGRelativePath $GamePath ([string]$entry.RelativePath)
            if (!(Test-Path -LiteralPath $target -PathType Leaf) -or
                (Get-AtGFileSha256 -Path $target) -ne [string]$entry.PatchSha256) {
                return $false
            }
        }

        return $true
    }
    catch {
        return $false
    }
}

function Get-AtGBackupEntries {
    param(
        [Parameter(Mandatory = $true)][string]$BackupRoot
    )

    if (!(Test-Path -LiteralPath $BackupRoot -PathType Container)) {
        return @()
    }

    $resolvedBackupRoot = (Resolve-Path -LiteralPath $BackupRoot).Path.TrimEnd([char[]]@('\', '/'))
    $entries = @()
    foreach ($file in @(Get-ChildItem -LiteralPath $resolvedBackupRoot -Recurse -File | Sort-Object FullName)) {
        $relative = ConvertTo-AtGNormalizedRelativePath ($file.FullName.Substring($resolvedBackupRoot.Length).TrimStart([char[]]@('\', '/')))
        $entries += [pscustomobject]@{
            RelativePath   = $relative
            HadOriginal    = $true
            OriginalSha256 = Get-AtGFileSha256 -Path $file.FullName
            PatchSha256    = $null
            BackupRelativePath = $relative
            PatchExclusive = $false
            TransactionState = 'BackupInventory'
            RecoverySource = 'BackupInventory'
        }
    }

    return @($entries)
}

function Test-AtGKnownPatchOnlyArtifact {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    $normalized = ConvertTo-AtGNormalizedRelativePath $RelativePath
    return Test-AtGLegacyPatchOnlyArtifact -RelativePath $normalized
}

function Write-AtGPatchManifest {
    param(
        [Parameter(Mandatory = $true)][string]$ManifestPath,
        [Parameter(Mandatory = $true)][object]$Manifest
    )

    $directory = Split-Path -Parent $ManifestPath
    if ($directory) {
        New-Item -ItemType Directory -Force -Path $directory | Out-Null
    }

    $temporaryPath = "$ManifestPath.$([Guid]::NewGuid().ToString('N')).tmp"
    try {
        $json = $Manifest | ConvertTo-Json -Depth 8
        [IO.File]::WriteAllText($temporaryPath, $json, (New-Object System.Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $temporaryPath -Destination $ManifestPath -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath) {
            Remove-Item -LiteralPath $temporaryPath -Force
        }
    }
}

# Inlined release dependency: tools\AtGPatchNotice.ps1
function Get-AtGInstallationNotice {
    # Keep this script ASCII-only: Windows PowerShell 5.1 otherwise reads a
    # UTF-8 script without a BOM through the active ANSI code page.
    $titleText = [string](ConvertFrom-Json '"\u300aAt the Gates\u300b\u7b80\u4f53\u4e2d\u6587\u8865\u4e01\u58f0\u660e"')
    $freeText = [string](ConvertFrom-Json '"\u672c\u8865\u4e01\u514d\u8d39\u63d0\u4f9b\uff0c\u4e25\u683c\u7981\u6b62\u5546\u4e1a\u7528\u9014\uff0c\u5c5e\u4e8e\u975e\u5b98\u65b9\u7c89\u4e1d\u5236\u4f5c\u8865\u4e01\u3002"')
    $filesText = [string](ConvertFrom-Json '"\u8865\u4e01\u4e0d\u5305\u542b\u6216\u518d\u5206\u53d1\u300aAt the Gates\u300b\u7684\u4efb\u4f55\u539f\u59cb\u6e38\u620f\u6587\u4ef6\u3002\u4f60\u5fc5\u987b\u62e5\u6709\u6e38\u620f\u7684\u6b63\u7248\u526f\u672c\u3002"')
    $supportText = [string](ConvertFrom-Json '"Conifer Games \u65e0\u6cd5\u4e3a\u4fee\u6539\u540e\u7684\u5b89\u88c5\u63d0\u4f9b\u6280\u672f\u652f\u6301\u3002\u4fee\u6539\u7248\u6e38\u620f\u7684\u5d29\u6e83\u62a5\u544a\u548c\u6280\u672f\u95ee\u9898\u8bf7\u63d0\u4ea4\u7ed9\u672c\u9879\u76ee\uff0c\u4e0d\u8981\u63d0\u4ea4\u7ed9 Conifer Games\uff1a"')
    $permissionText = [string](ConvertFrom-Json '"\u672c\u8865\u4e01\u7684\u53d1\u5e03\u4e0e\u63a8\u5e7f\u8bb8\u53ef\u57fa\u4e8e\u5584\u610f\u6388\u4e88\uff0c\u4e14\u53ef\u80fd\u88ab\u64a4\u9500\u3002"')
    $message = @(
        $freeText,
        "",
        $filesText,
        "",
        $supportText,
        "https://github.com/TsuTa-hl/At-the-Gates-Chinese-Patch/issues",
        "",
        $permissionText
    ) -join [Environment]::NewLine

    return [pscustomobject]@{
        Title   = $titleText
        Message = $message
    }
}

function Show-AtGInstallationNotice {
    $notice = Get-AtGInstallationNotice

    try {
        Add-Type -AssemblyName System.Windows.Forms
        [void][System.Windows.Forms.MessageBox]::Show(
            $notice.Message,
            $notice.Title,
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information)
    }
    catch {
        Write-Warning ($notice.Title + [Environment]::NewLine + $notice.Message)
    }
}


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
