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
            RecoverySource  = 'Manifest'
        }
    }

    return @($entries)
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
    if ($normalized -in @(
        '.atg-build-report.json',
        'AtG.RuntimeText.dll',
        'Content\Text\AtG.RuntimeText.tsv',
        'Content\Fonts\AtG.RuntimeGlyphWarmset.tsv',
        'Content\Fonts\NotoSansSC-Bold.otf',
        'Content\Fonts\NotoSansSC-Regular.otf',
        'Content\Fonts\OFL.txt'
    )) {
        return $true
    }

    $parts = $normalized.Split([char[]]@('\'))
    if ($parts.Count -ge 7 -and
        $parts[0] -eq 'Content' -and
        $parts[1] -eq 'Images' -and
        $parts[2] -eq 'Interface' -and
        $parts[3] -eq 'ScreenSpecific' -and
        $parts[4] -eq 'ClanCard' -and
        $parts[5] -match '[\u4E00-\u9FFF]') {
        return $true
    }

    return $false
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
