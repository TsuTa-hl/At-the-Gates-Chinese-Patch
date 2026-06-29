param(
    [string]$MapJson = "$PSScriptRoot\..\translations\config-strings.json",
    [string]$ProjectRoot = "$PSScriptRoot\..",
    [string]$PatchRoot = "$PSScriptRoot\..\patch"
)

$ErrorActionPreference = "Stop"

if (!(Test-Path -LiteralPath $MapJson)) {
    throw "Config string map not found: $MapJson"
}

$map = Get-Content -LiteralPath $MapJson -Raw -Encoding UTF8 | ConvertFrom-Json
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

foreach ($fileEntry in $map.PSObject.Properties) {
    $relativeOutput = [string]$fileEntry.Name
    $config = $fileEntry.Value
    $sourceRelative = [string]$config.Source
    $sourcePath = Join-Path $ProjectRoot $sourceRelative
    $outputPath = Join-Path $PatchRoot $relativeOutput

    if (!(Test-Path -LiteralPath $sourcePath)) {
        throw "Config source not found: $sourcePath"
    }

    $content = [IO.File]::ReadAllText($sourcePath, [Text.Encoding]::UTF8)
    foreach ($replacement in $config.Replacements.PSObject.Properties) {
        $source = [string]$replacement.Name
        $target = [string]$replacement.Value
        if ([string]::IsNullOrEmpty($source)) {
            throw "Empty config replacement source in $relativeOutput"
        }

        $count = ([regex]::Matches($content, [regex]::Escape($source))).Count
        if ($count -eq 0) {
            throw "Config source string not found in ${sourcePath}: $source"
        }

        $content = $content.Replace($source, $target)
        Write-Host "Patched config '$source' -> '$target' in $relativeOutput ($count occurrence(s))."
    }

    [void]([xml]$content)

    $outDir = Split-Path -Parent $outputPath
    if ($outDir) {
        New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    }

    [IO.File]::WriteAllText($outputPath, $content, $utf8NoBom)
    Write-Host "Built config patch: $outputPath"
}
