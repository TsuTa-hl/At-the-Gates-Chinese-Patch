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
