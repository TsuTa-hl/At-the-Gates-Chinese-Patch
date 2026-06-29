param(
    [Parameter(Mandatory = $true)]
    [string]$SourceDll,

    [Parameter(Mandatory = $true)]
    [string]$OutputDll,

    [Parameter(Mandatory = $true)]
    [string]$MapJson,

    [int]$PaddingCodePoint = 0x200B,

    [string[]]$SkipSourceStrings = @()
)

$ErrorActionPreference = "Stop"

if (!(Test-Path -LiteralPath $SourceDll)) {
    throw "Source DLL not found: $SourceDll"
}
if (!(Test-Path -LiteralPath $MapJson)) {
    throw "Offset map not found: $MapJson"
}

$entries = Get-Content -LiteralPath $MapJson -Raw -Encoding UTF8 | ConvertFrom-Json
$bytes = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $SourceDll).Path)
$padding = [char]$PaddingCodePoint
$skip = @{}
foreach ($sourceToSkip in @($SkipSourceStrings)) {
    if (![string]::IsNullOrWhiteSpace($sourceToSkip)) {
        $skip[[string]$sourceToSkip] = $true
    }
}

function Find-AtGUniqueBytes {
    param(
        [byte[]]$Bytes,
        [byte[]]$Needle
    )

    $matches = @()
    for ($i = 0; $i -le $Bytes.Length - $Needle.Length; $i++) {
        if ($Bytes[$i] -ne $Needle[0]) {
            continue
        }

        $matched = $true
        for ($j = 1; $j -lt $Needle.Length; $j++) {
            if ($Bytes[$i + $j] -ne $Needle[$j]) {
                $matched = $false
                break
            }
        }

        if ($matched) {
            $matches += $i
            if ($matches.Count -gt 1) {
                break
            }
        }
    }

    if ($matches.Count -eq 1) {
        return [int]$matches[0]
    }

    return -1
}

foreach ($entry in @($entries)) {
    $offset = [int]$entry.Offset
    $original = [string]$entry.Original
    $replacement = [string]$entry.Translation
    if ($skip.ContainsKey($original)) {
        Write-Host "Skipping offset '$original'; covered by another patch path."
        continue
    }

    if ($offset -lt 0 -or $offset -ge $bytes.Length) {
        throw "Offset $offset is outside $SourceDll"
    }
    if ($replacement.Length -gt $original.Length) {
        throw "Replacement '$replacement' is longer than original '$original'."
    }

    $expectedBytes = [Text.Encoding]::Unicode.GetBytes($original)
    if ($offset + $expectedBytes.Length -gt $bytes.Length) {
        throw "Original '$original' at offset $offset exceeds file length."
    }

    $offsetMatches = $true
    for ($i = 0; $i -lt $expectedBytes.Length; $i++) {
        if ($bytes[$offset + $i] -ne $expectedBytes[$i]) {
            $offsetMatches = $false
            break
        }
    }

    if (!$offsetMatches) {
        $actualLength = [Math]::Min($expectedBytes.Length, $bytes.Length - $offset)
        $actual = [Text.Encoding]::Unicode.GetString($bytes, $offset, $actualLength)
        $fallbackOffset = Find-AtGUniqueBytes -Bytes $bytes -Needle $expectedBytes
        if ($fallbackOffset -lt 0) {
            throw "Offset $offset does not contain '$original'. Actual: '$actual'. No unique fallback match was found."
        }

        Write-Host "Offset $offset no longer contains '$original'. Using unique fallback offset $fallbackOffset."
        $offset = $fallbackOffset
    }

    $padded = $replacement + ($padding.ToString() * ($original.Length - $replacement.Length))
    $replacementBytes = [Text.Encoding]::Unicode.GetBytes($padded)
    [Array]::Copy($replacementBytes, 0, $bytes, $offset, $replacementBytes.Length)
    Write-Host "Patched offset $offset '$original' -> '$replacement'."
}

$outDir = Split-Path -Parent $OutputDll
if ($outDir) {
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
}

[IO.File]::WriteAllBytes((Resolve-Path -LiteralPath $outDir).Path + "\" + [IO.Path]::GetFileName($OutputDll), $bytes)
Write-Host "Built offset string patch: $OutputDll"
