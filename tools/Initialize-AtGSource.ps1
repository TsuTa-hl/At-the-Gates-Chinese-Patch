param(
    [string]$GamePath,
    [string]$SourceRoot = "$PSScriptRoot\..\source",
    [switch]$Refresh
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\AtGPaths.ps1"
. "$PSScriptRoot\AtGFileOps.ps1"

$resolvedGamePath = Resolve-AtGGamePath $GamePath
Assert-AtGGameNotRunning -Operation 'capturing Steam build inputs'
$manifestPath = Join-Path $resolvedGamePath '.atg-chinese-patch.json'
if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
    throw "The selected game has an active Chinese patch manifest. Uninstall it before capturing pristine Steam build inputs: $manifestPath"
}

$resolvedSourceRoot = [System.IO.Path]::GetFullPath($SourceRoot)
if (Test-Path -LiteralPath $resolvedSourceRoot -PathType Container) {
    $hasExistingInputs = @(Get-ChildItem -LiteralPath $resolvedSourceRoot -Force -ErrorAction SilentlyContinue).Count -gt 0
    if ($hasExistingInputs -and !$Refresh) {
        throw "Source root already contains captured inputs. Pass -Refresh only after confirming it is safe to replace: $resolvedSourceRoot"
    }
}

$fileMap = [ordered]@{
    'Content\Text\English.xml' = 'English.original.xml'
    'AtTheGatesUI.dll' = 'AtTheGatesUI.original.dll'
    'AtTheGatesCommon.dll' = 'AtTheGatesCommon.original.dll'
    'At The Gates.exe' = 'AtTheGatesGame.original.exe'
    'ElfTools.dll' = 'ElfTools.original.dll'
}
$directoryMap = [ordered]@{
    'Content\Config' = 'Content\Config'
    'Content\Images\Interface\ScreenSpecific\ClanCard' = 'Content\Images\Interface\ScreenSpecific\ClanCard'
}

$missing = @()
foreach ($relative in $fileMap.Keys) {
    if (!(Test-Path -LiteralPath (Join-Path $resolvedGamePath $relative) -PathType Leaf)) {
        $missing += $relative
    }
}
foreach ($relative in $directoryMap.Keys) {
    if (!(Test-Path -LiteralPath (Join-Path $resolvedGamePath $relative) -PathType Container)) {
        $missing += $relative
    }
}
if ($missing.Count -gt 0) {
    throw "The selected AtG directory is missing Steam build inputs:`n - $($missing -join "`n - ")"
}

$stageRoot = Join-Path (Split-Path -Parent $resolvedSourceRoot) (".{0}.staging-{1}" -f (Split-Path -Leaf $resolvedSourceRoot), [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $stageRoot | Out-Null
try {
    foreach ($relative in $fileMap.Keys) {
        Copy-AtGFileIfChanged -Source (Join-Path $resolvedGamePath $relative) -Destination (Join-Path $stageRoot $fileMap[$relative]) | Out-Null
    }
    foreach ($relative in $directoryMap.Keys) {
        $source = Join-Path $resolvedGamePath $relative
        $destination = Join-Path $stageRoot $directoryMap[$relative]
        if ($relative -eq 'Content\Config') {
            # Build inputs deliberately use the .original.xml suffix so a
            # source snapshot can never be mistaken for a generated patch XML.
            # Preserve the complete directory shape while renaming only XML
            # payloads; other config-side files retain their original names.
            foreach ($configFile in @(Get-ChildItem -LiteralPath $source -Recurse -File)) {
                $configRelative = $configFile.FullName.Substring($source.Length).TrimStart([char[]]@('\', '/'))
                $destinationRelative = if ($configRelative.EndsWith('.xml', [StringComparison]::OrdinalIgnoreCase)) {
                    $configRelative.Substring(0, $configRelative.Length - 4) + '.original.xml'
                }
                else {
                    $configRelative
                }
                $configDestination = Join-Path $destination $destinationRelative
                New-Item -ItemType Directory -Force -Path (Split-Path -Parent $configDestination) | Out-Null
                Copy-AtGFileIfChanged -Source $configFile.FullName -Destination $configDestination | Out-Null
            }
        }
        else {
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
            Copy-Item -LiteralPath $source -Destination $destination -Recurse -Force
        }
    }

    $files = @(Get-ChildItem -LiteralPath $stageRoot -Recurse -File | Sort-Object FullName | ForEach-Object {
        $relative = $_.FullName.Substring($stageRoot.Length).TrimStart([char[]]@('\', '/')).Replace('/', '\')
        [ordered]@{
            RelativePath = $relative
            Sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    })
    [System.IO.File]::WriteAllText(
        (Join-Path $stageRoot '.atg-source-manifest.json'),
        ([ordered]@{
            SchemaVersion = 1
            CapturedAtUtc = [DateTime]::UtcNow.ToString('o')
            GamePath = $resolvedGamePath
            Files = $files
        } | ConvertTo-Json -Depth 5),
        [System.Text.UTF8Encoding]::new($false))

    if (Test-Path -LiteralPath $resolvedSourceRoot) {
        Remove-Item -LiteralPath $resolvedSourceRoot -Recurse -Force
    }
    Move-Item -LiteralPath $stageRoot -Destination $resolvedSourceRoot
}
catch {
    if (Test-Path -LiteralPath $stageRoot) {
        Remove-Item -LiteralPath $stageRoot -Recurse -Force
    }
    throw
}

Write-Host "Captured Steam AtG source inputs: $resolvedSourceRoot"
