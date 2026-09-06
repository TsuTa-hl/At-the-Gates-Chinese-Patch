param(
    [string]$GamePath,
    [switch]$SkipSaveNameCompatibility,
    [switch]$NoSaveNameNotice
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

# Inlined release dependency: tools\AtGFileOps.ps1
$ErrorActionPreference = "Stop"

function Test-AtGTransientFileWriteFailure {
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    $exception = $ErrorRecord.Exception
    while ($null -ne $exception) {
        $win32Code = $exception.HResult -band 0xffff
        if ($win32Code -in @(32, 33, 1224)) {
            return $true
        }
        $exception = $exception.InnerException
    }

    $message = [string]$ErrorRecord
    return $message -match "user-mapped section|being used by another process|sharing violation|mapped.*open|映射|另一进程"
}

function Copy-AtGFileContentsInPlace {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Source,

        [Parameter(Mandatory = $true)]
        [string]$Destination
    )

    # A memory-mapped destination can forbid replacement/rename while still
    # permitting a shared write handle.  This narrowly scoped fallback keeps
    # the transaction recoverable: callers verify the final hash immediately.
    $resolvedSource = [System.IO.Path]::GetFullPath($Source)
    $resolvedDestination = [System.IO.Path]::GetFullPath($Destination)
    $sourceStream = [System.IO.File]::Open(
        $resolvedSource,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::ReadWrite)
    try {
        $destinationStream = [System.IO.File]::Open(
            $resolvedDestination,
            [System.IO.FileMode]::OpenOrCreate,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::ReadWrite)
        try {
            $destinationStream.SetLength(0)
            $sourceStream.CopyTo($destinationStream)
            $destinationStream.Flush($true)
        }
        finally {
            $destinationStream.Dispose()
        }
    }
    finally {
        $sourceStream.Dispose()
    }
}

function Copy-AtGFileIfChanged {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Source,

        [Parameter(Mandatory = $true)]
        [string]$Destination,

        [ValidateRange(1, 30)]
        [int]$MaxAttempts = 10,

        [ValidateRange(1, 5000)]
        [int]$InitialDelayMilliseconds = 100
    )

    $resolvedSource = [System.IO.Path]::GetFullPath($Source)
    $resolvedDestination = [System.IO.Path]::GetFullPath($Destination)
    if (!(Test-Path -LiteralPath $resolvedSource -PathType Leaf)) {
        throw "Source file not found: $resolvedSource"
    }

    if (Test-Path -LiteralPath $resolvedDestination -PathType Leaf) {
        $sourceInfo = Get-Item -LiteralPath $resolvedSource
        $destinationInfo = Get-Item -LiteralPath $resolvedDestination
        if ($sourceInfo.Length -eq $destinationInfo.Length) {
            $sourceHash = (Get-FileHash -LiteralPath $resolvedSource -Algorithm SHA256).Hash
            $destinationHash = (Get-FileHash -LiteralPath $resolvedDestination -Algorithm SHA256).Hash
            if ($sourceHash -eq $destinationHash) {
                return $false
            }
        }
    }

    $destinationDirectory = Split-Path -Parent $resolvedDestination
    New-Item -ItemType Directory -Force -Path $destinationDirectory | Out-Null
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            Copy-Item -LiteralPath $resolvedSource -Destination $resolvedDestination -Force
            return $true
        }
        catch {
            $isTransient = Test-AtGTransientFileWriteFailure -ErrorRecord $_
            if (!$isTransient) {
                throw
            }

            if ($attempt -ge $MaxAttempts) {
                Write-Warning "Destination remains mapped after $MaxAttempts replacement attempts; trying a hash-verified in-place copy: $resolvedDestination"
                Copy-AtGFileContentsInPlace -Source $resolvedSource -Destination $resolvedDestination
                return $true
            }

            $delayMilliseconds = [Math]::Min(
                800,
                $InitialDelayMilliseconds * [Math]::Pow(2, $attempt - 1))
            Write-Warning ("Destination is temporarily mapped; retrying copy attempt {0}/{1} after {2} ms: {3}" -f `
                ($attempt + 1), $MaxAttempts, [int]$delayMilliseconds, $resolvedDestination)
            [GC]::Collect()
            [GC]::WaitForPendingFinalizers()
            Start-Sleep -Milliseconds ([int]$delayMilliseconds)
        }
    }

    throw "Failed to copy file after $MaxAttempts attempts: $resolvedDestination"
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

# Inlined release dependency: tools\AtGSaveNameCompatibility.ps1
function Test-AtGOriginalSaveNameCharacter {
    param(
        [Parameter(Mandatory = $true)]
        [char]$Character
    )

    # The original save-list fonts are an English/Latin UI surface.  Printable
    # ASCII is the deliberate compatibility floor shared by those fonts; do
    # not attempt transliteration, because it could make two distinct saves
    # look like the same world to the player.
    $codePoint = [int][char]$Character
    return $codePoint -ge 0x20 -and $codePoint -le 0x7E
}

function ConvertTo-AtGOriginalCompatibleSaveBaseName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaseName
    )

    $builder = New-Object System.Text.StringBuilder
    foreach ($character in $BaseName.ToCharArray()) {
        if (Test-AtGOriginalSaveNameCharacter $character) {
            [void]$builder.Append($character)
        }
    }

    $compatible = $builder.ToString()
    if ([string]::IsNullOrWhiteSpace($compatible)) {
        return "SavedGame"
    }

    return $compatible
}

function Get-AtGAvailableSaveName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaseName,

        [Parameter(Mandatory = $true)]
        [string]$Extension,

        [Parameter(Mandatory = $true)]
        [object]$OccupiedNames
    )

    $maximumBaseLength = [Math]::Max(1, 255 - $Extension.Length)
    $trimmedBase = $BaseName.Substring(0, [Math]::Min($BaseName.Length, $maximumBaseLength))
    $candidate = "$trimmedBase$Extension"
    if (!$OccupiedNames.Contains($candidate)) {
        return $candidate
    }

    $counter = 2
    while ($true) {
        $suffix = "-$counter"
        $allowedBaseLength = [Math]::Max(1, 255 - $Extension.Length - $suffix.Length)
        $candidateBase = $trimmedBase.Substring(0, [Math]::Min($trimmedBase.Length, $allowedBaseLength))
        $candidate = "$candidateBase$suffix$Extension"
        if (!$OccupiedNames.Contains($candidate)) {
            return $candidate
        }

        $counter++
    }
}

function Convert-AtGSavedGameNamesForOriginalFonts {
    param(
        [Parameter(Mandatory = $true)]
        [string]$GamePath
    )

    $saveDirectory = Join-Path $GamePath "Saved Games"
    if (!(Test-Path -LiteralPath $saveDirectory -PathType Container)) {
        return @()
    }

    $saves = @(Get-ChildItem -LiteralPath $saveDirectory -File -Filter "*.AtGSave" | Sort-Object Name)
    $occupiedNames = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($save in $saves) {
        [void]$occupiedNames.Add($save.Name)
    }

    $renamed = New-Object System.Collections.Generic.List[object]
    foreach ($save in $saves) {
        $baseName = [IO.Path]::GetFileNameWithoutExtension($save.Name)
        $extension = [IO.Path]::GetExtension($save.Name)
        $compatibleBaseName = ConvertTo-AtGOriginalCompatibleSaveBaseName $baseName
        if ($compatibleBaseName -eq $baseName) {
            continue
        }

        [void]$occupiedNames.Remove($save.Name)
        $newName = Get-AtGAvailableSaveName -BaseName $compatibleBaseName -Extension $extension -OccupiedNames $occupiedNames
        $destination = Join-Path $saveDirectory $newName
        Move-Item -LiteralPath $save.FullName -Destination $destination -ErrorAction Stop
        [void]$occupiedNames.Add($newName)
        $renamed.Add([pscustomobject]@{
                OldName = $save.Name
                NewName = $newName
            })
    }

    return $renamed.ToArray()
}

function Get-AtGSaveNameCompatibilityMessage {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$RenamedSaves
    )

    if ($RenamedSaves.Count -eq 0) {
        return
    }

    $preview = @($RenamedSaves | Select-Object -First 6 | ForEach-Object {
            "- $($_.OldName) -> $($_.NewName)"
        })
    if ($RenamedSaves.Count -gt $preview.Count) {
        $moreTemplate = [string](ConvertFrom-Json '"\u53e6\u6709 {0} \u4e2a\u5b58\u6863\u5df2\u6539\u540d"')
        $preview += ("- " + ($moreTemplate -f ($RenamedSaves.Count - $preview.Count)))
    }

    # Keep this script ASCII-only: Windows PowerShell 5.1 otherwise reads a
    # UTF-8 script without a BOM through the active ANSI code page.
    $uninstalled = [string](ConvertFrom-Json '"\u6c49\u5316\u8865\u4e01\u5df2\u5378\u8f7d\u3002"')
    $renamedTemplate = [string](ConvertFrom-Json '"\u4e3a\u907f\u514d\u539f\u7248\u6e38\u620f\u8bfb\u53d6\u542b\u4e2d\u6587\u7684\u5b58\u6863\u540d\u65f6\u5d29\u6e83\uff0c\u5df2\u5728\u6062\u590d\u539f\u59cb\u6587\u4ef6\u524d\u81ea\u52a8\u4fee\u6539 {0} \u4e2a\u5b58\u6863\u540d\u3002"')
    $contentsSafe = [string](ConvertFrom-Json '"\u4ec5\u79fb\u9664\u4e86\u539f\u7248\u4e0d\u652f\u6301\u7684\u5b57\u7b26\uff0c\u672a\u4fee\u6539\u5b58\u6863\u5185\u5bb9\u3002"')
    # Add preview lines individually. In PowerShell, placing the preview array
    # as one element in @(...)-join can stringify it as System.Object[] (or
    # leave an empty object at the end of the dialog) instead of rendering the
    # actual rename lines.
    $messageLines = New-Object 'System.Collections.Generic.List[string]'
    [void]$messageLines.Add($uninstalled)
    [void]$messageLines.Add("")
    [void]$messageLines.Add($renamedTemplate -f $RenamedSaves.Count)
    [void]$messageLines.Add($contentsSafe)
    [void]$messageLines.Add("")
    foreach ($line in @($preview)) {
        if (![string]::IsNullOrEmpty([string]$line)) {
            [void]$messageLines.Add([string]$line)
        }
    }
    return $messageLines -join [Environment]::NewLine
}

function Show-AtGSaveNameCompatibilityNotice {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$RenamedSaves
    )

    if ($RenamedSaves.Count -eq 0) {
        return
    }

    $message = Get-AtGSaveNameCompatibilityMessage -RenamedSaves $RenamedSaves
    $title = "At the Gates " + [string](ConvertFrom-Json '"\u6c49\u5316\u8865\u4e01"')

    try {
        Add-Type -AssemblyName System.Windows.Forms
        [void][System.Windows.Forms.MessageBox]::Show(
            $message,
            $title,
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information)
    }
    catch {
        Write-Warning $message
    }
}


$GamePath = Resolve-AtGGamePath $GamePath
Assert-AtGGameNotRunning -Operation 'uninstalling the Chinese patch'
$manifestPath = Join-Path $GamePath ".atg-chinese-patch.json"
$backupBasePath = Join-Path $GamePath "_ChinesePatchBackup"
$manifestEntries = @()
$manifest = $null
$usedOrphanRecovery = $false

if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $backupRoot = [string]$manifest.BackupRoot
    if ([string]::IsNullOrWhiteSpace($backupRoot)) {
        throw "Patch manifest does not contain a backup path: $manifestPath"
    }
    if (!(Test-Path -LiteralPath $backupRoot -PathType Container) -and
        (Test-AtGManifestRestoredState -GamePath $GamePath -Manifest $manifest)) {
        # Cleanup completed before its final metadata deletion.  The recorded
        # hashes prove that the original bytes are already back in place, so
        # remove only the stale marker instead of treating it as a broken
        # active transaction.
        Remove-Item -LiteralPath $manifestPath -Force
        if ((Test-Path -LiteralPath $backupBasePath -PathType Container) -and
            @((Get-ChildItem -LiteralPath $backupBasePath -Force)).Count -eq 0) {
            Remove-Item -LiteralPath $backupBasePath -Force
        }

        $renamedSaves = @()
        if (!$SkipSaveNameCompatibility) {
            $renamedSaves = @(Convert-AtGSavedGameNamesForOriginalFonts -GamePath $GamePath)
            foreach ($renamedSave in $renamedSaves) {
                Write-Host "Renamed save for original-font compatibility: $($renamedSave.OldName) -> $($renamedSave.NewName)"
            }
        }

        Write-Host "Chinese patch was already fully restored; removed its stale transaction manifest."
        if (!$NoSaveNameNotice) {
            Show-AtGSaveNameCompatibilityNotice -RenamedSaves $renamedSaves
        }
        return
    }
    $manifestEntries = @(Get-AtGManifestEntries -Manifest $manifest)
    $manifest | Add-Member -NotePropertyName InstallState -NotePropertyValue "Uninstalling" -Force
    $manifest | Add-Member -NotePropertyName LastUpdated -NotePropertyValue (Get-Date).ToString("s") -Force
    Write-AtGPatchManifest -ManifestPath $manifestPath -Manifest $manifest
}
else {
    $backupBase = $backupBasePath
    $backupRoot = $null
    if (Test-Path -LiteralPath $backupBase -PathType Container) {
        $backupRoot = Get-ChildItem -LiteralPath $backupBase -Directory |
            Where-Object { Test-Path -LiteralPath (Join-AtGRelativePath $_.FullName "Content\Text\English.xml") } |
            Sort-Object Name |
            Select-Object -First 1 -ExpandProperty FullName
    }
    if ([string]::IsNullOrWhiteSpace($backupRoot)) {
        throw "Patch manifest not found and no recoverable Chinese patch backup exists: $manifestPath"
    }

    $usedOrphanRecovery = $true
    Write-Warning "Patch manifest is missing. Recovering managed files from the Chinese patch backup inventory."
}

if (!(Test-Path -LiteralPath $backupRoot -PathType Container)) {
    throw "Patch backup directory is missing: $backupRoot"
}

$resolvedBackupBase = (Resolve-Path -LiteralPath $backupBasePath).Path.TrimEnd([char[]]@('\', '/'))
$resolvedBackupRoot = (Resolve-Path -LiteralPath $backupRoot).Path.TrimEnd([char[]]@('\', '/'))
if (!$resolvedBackupRoot.StartsWith($resolvedBackupBase + "\", [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Patch backup must stay under the game's _ChinesePatchBackup directory: $backupRoot"
}

function Get-AtGManifestCreatedDirectories {
    param([object]$Manifest)

    if ($null -eq $Manifest -or $null -eq $Manifest.PSObject.Properties['CreatedDirectories']) {
        return @()
    }

    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $directories = @()
    foreach ($value in @($Manifest.CreatedDirectories)) {
        if ($null -eq $value) {
            continue
        }
        $relative = ConvertTo-AtGNormalizedRelativePath ([string]$value)
        if ($seen.Add($relative)) {
            $directories += $relative
        }
    }
    return @($directories)
}

function Update-AtGManifestEntryState {
    param(
        [Parameter(Mandatory = $true)][object]$Manifest,
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$State
    )

    foreach ($file in @($Manifest.Files)) {
        if ([string]::Equals([string]$file.RelativePath, $RelativePath, [System.StringComparison]::OrdinalIgnoreCase)) {
            $file | Add-Member -NotePropertyName TransactionState -NotePropertyValue $State -Force
            $file | Add-Member -NotePropertyName Restored -NotePropertyValue (Get-Date).ToString("s") -Force
            break
        }
    }
    $Manifest | Add-Member -NotePropertyName LastUpdated -NotePropertyValue (Get-Date).ToString("s") -Force
    Write-AtGPatchManifest -ManifestPath $manifestPath -Manifest $Manifest
}

$recoveryEntries = @{}
function Add-AtGRecoveryEntry {
    param(
        [Parameter(Mandatory = $true)][object]$Entry
    )

    $relative = ConvertTo-AtGNormalizedRelativePath ([string]$Entry.RelativePath)
    $candidate = [pscustomobject]@{
        RelativePath       = $relative
        HadOriginal        = [bool]$Entry.HadOriginal
        OriginalSha256     = [string]$Entry.OriginalSha256
        BackupRelativePath = if ($null -ne $Entry.PSObject.Properties['BackupRelativePath']) {
            ConvertTo-AtGNormalizedRelativePath ([string]$Entry.BackupRelativePath)
        } else {
            $relative
        }
        PatchSha256        = [string]$Entry.PatchSha256
        PatchExclusive     = if ($null -ne $Entry.PSObject.Properties['PatchExclusive']) {
            [bool]$Entry.PatchExclusive
        } else {
            -not [bool]$Entry.HadOriginal
        }
        TransactionState   = if ($null -ne $Entry.PSObject.Properties['TransactionState']) {
            [string]$Entry.TransactionState
        } else {
            'Legacy'
        }
        RecoverySource     = [string]$Entry.RecoverySource
    }

    if (!$recoveryEntries.ContainsKey($relative)) {
        $recoveryEntries[$relative] = $candidate
        return
    }

    $existing = $recoveryEntries[$relative]
    if ($candidate.HadOriginal -and !$existing.HadOriginal) {
        $recoveryEntries[$relative] = $candidate
    }
}

foreach ($entry in $manifestEntries) {
    Add-AtGRecoveryEntry $entry
}

$backupEntries = @(Get-AtGBackupEntries -BackupRoot $backupRoot)
foreach ($entry in $backupEntries) {
    Add-AtGRecoveryEntry $entry
}

$patchRoot = Join-Path $PSScriptRoot "patch"
$patchInventoryByPath = @{}
if (Test-Path -LiteralPath $patchRoot -PathType Container) {
    foreach ($entry in @(Get-AtGPatchInventory -PatchRoot $patchRoot)) {
        $patchInventoryByPath[[string]$entry.RelativePath] = $entry
        if (!$recoveryEntries.ContainsKey($entry.RelativePath) -and (Test-AtGKnownPatchOnlyArtifact $entry.RelativePath)) {
            Add-AtGRecoveryEntry ([pscustomobject]@{
                    RelativePath = $entry.RelativePath
                    HadOriginal = $false
                    OriginalSha256 = $null
                    BackupRelativePath = $entry.RelativePath
                    PatchSha256 = $entry.PatchSha256
                    PatchExclusive = $true
                    TransactionState = 'LegacyPatchInventory'
                    RecoverySource = 'KnownPatchOnlyRecovery'
                })
        }
    }
}

foreach ($legacyEntry in @(Get-AtGLegacyPatchOnlyEntries)) {
    $relative = ConvertTo-AtGNormalizedRelativePath ([string]$legacyEntry.RelativePath)
    if (!$recoveryEntries.ContainsKey($relative)) {
        $knownPatchHash = if ($patchInventoryByPath.ContainsKey($relative)) { [string]$patchInventoryByPath[$relative].PatchSha256 } else { $null }
        Add-AtGRecoveryEntry ([pscustomobject]@{
                RelativePath = $relative
                HadOriginal = $false
                OriginalSha256 = $null
                BackupRelativePath = $relative
                PatchSha256 = $knownPatchHash
                PatchExclusive = $true
                TransactionState = 'HistoricalRegistry'
                RecoverySource = [string]$legacyEntry.Reason
            })
    }
}

# The old package used generated Chinese ClanCard directory names.  Scan that
# narrow ownership namespace so a corrupt old manifest cannot strand aliases.
$legacyClanCardRoot = Join-Path $GamePath "Content\Images\Interface\ScreenSpecific\ClanCard"
if (Test-Path -LiteralPath $legacyClanCardRoot -PathType Container) {
    $gameRootFull = (Resolve-Path -LiteralPath $GamePath).Path.TrimEnd([char[]]@('\', '/'))
    foreach ($file in @(Get-ChildItem -LiteralPath $legacyClanCardRoot -Recurse -File -ErrorAction SilentlyContinue)) {
        $relative = ConvertTo-AtGNormalizedRelativePath ($file.FullName.Substring($gameRootFull.Length).TrimStart([char[]]@('\', '/')))
        if ((Test-AtGKnownPatchOnlyArtifact $relative) -and !$recoveryEntries.ContainsKey($relative)) {
            Add-AtGRecoveryEntry ([pscustomobject]@{
                    RelativePath = $relative
                    HadOriginal = $false
                    OriginalSha256 = $null
                    BackupRelativePath = $relative
                    PatchSha256 = $null
                    PatchExclusive = $true
                    TransactionState = 'HistoricalRegistry'
                    RecoverySource = 'HistoricalClanCardAlias'
                })
        }
    }
}

$restoredCount = 0
$removedCount = 0
foreach ($entry in @($recoveryEntries.Values | Sort-Object RelativePath)) {
    $relative = [string]$entry.RelativePath
    $target = Join-AtGRelativePath $GamePath $relative
    $backup = Join-AtGRelativePath $backupRoot ([string]$entry.BackupRelativePath)

    if ($entry.HadOriginal) {
        if (!(Test-Path -LiteralPath $backup -PathType Leaf)) {
            throw "Backup file missing for uninstall recovery: $backup"
        }

        $backupHash = Get-AtGFileSha256 -Path $backup
        if (![string]::IsNullOrWhiteSpace($entry.OriginalSha256) -and $backupHash -ne $entry.OriginalSha256) {
            throw "Backup hash changed since install for: $relative"
        }

        Copy-AtGFileIfChanged -Source $backup -Destination $target | Out-Null
        if ((Get-AtGFileSha256 -Path $target) -ne $backupHash) {
            throw "Uninstall did not restore the original file exactly: $relative"
        }
        $restoredCount++
    }
    else {
        if (!$entry.PatchExclusive) {
            throw "Manifest incorrectly marks a non-original file as non-exclusive: $relative"
        }
        if (Test-Path -LiteralPath $target -PathType Container) {
            throw "Refusing to remove a directory where a patch file is expected: $target"
        }
        if (Test-Path -LiteralPath $target -PathType Leaf) {
            $actualHash = Get-AtGFileSha256 -Path $target
            # New transaction manifests retain a patch hash. Do not erase a
            # file a player or MOD replaced after installation; leave the
            # transaction recoverable and ask for a manual decision instead.
            if (![string]::IsNullOrWhiteSpace($entry.PatchSha256) -and $actualHash -ne $entry.PatchSha256) {
                throw "Patch-only file changed after installation; refusing to delete it: $relative"
            }
            Remove-Item -LiteralPath $target -Force
            $removedCount++
        }
        if (Test-Path -LiteralPath $target) {
            throw "Uninstall did not remove patch-only file: $relative"
        }
    }

    if ($null -ne $manifest) {
        Update-AtGManifestEntryState -Manifest $manifest -RelativePath $relative -State "Restored"
    }
}

foreach ($relativeDirectory in @(Get-AtGManifestCreatedDirectories -Manifest $manifest | Sort-Object Length -Descending)) {
    $directory = Join-AtGRelativePath $GamePath $relativeDirectory
    if ((Test-Path -LiteralPath $directory -PathType Container) -and
        @((Get-ChildItem -LiteralPath $directory -Force -ErrorAction Stop)).Count -eq 0) {
        Remove-Item -LiteralPath $directory -Force
    }
}

if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
    Remove-Item -LiteralPath $manifestPath -Force
}
Remove-Item -LiteralPath $backupRoot -Recurse -Force
if ((Test-Path -LiteralPath $backupBasePath -PathType Container) -and
    @((Get-ChildItem -LiteralPath $backupBasePath -Force)).Count -eq 0) {
    Remove-Item -LiteralPath $backupBasePath -Force
}

$renamedSaves = @()
if (!$SkipSaveNameCompatibility) {
    $renamedSaves = @(Convert-AtGSavedGameNamesForOriginalFonts -GamePath $GamePath)
    foreach ($renamedSave in $renamedSaves) {
        Write-Host "Renamed save for original-font compatibility: $($renamedSave.OldName) -> $($renamedSave.NewName)"
    }
}

Write-Host "Chinese patch uninstall verification passed. Restored $restoredCount original file(s) and removed $removedCount patch-only file(s)."
if ($usedOrphanRecovery -or $backupEntries.Count -gt $manifestEntries.Count) {
    Write-Host "Recovery inventory included $($backupEntries.Count) backup file(s)."
}
Write-Host "Chinese patch uninstalled and transaction backup removed."

if (!$NoSaveNameNotice) {
    Show-AtGSaveNameCompatibilityNotice -RenamedSaves $renamedSaves
}
