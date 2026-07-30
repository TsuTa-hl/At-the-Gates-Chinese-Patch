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

function Show-AtGSaveNameCompatibilityNotice {
    param(
        [Parameter(Mandatory = $true)]
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
    $title = "At the Gates " + [string](ConvertFrom-Json '"\u6c49\u5316\u8865\u4e01"')
    $message = @(
        $uninstalled,
        "",
        ($renamedTemplate -f $RenamedSaves.Count),
        $contentsSafe,
        "",
        $preview
    ) -join [Environment]::NewLine

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
