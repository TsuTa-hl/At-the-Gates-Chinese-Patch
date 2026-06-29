param(
    [string]$SourceDll = "$PSScriptRoot\..\source\AtTheGatesUI.original.dll",
    [string]$OutputDll = "$PSScriptRoot\..\patch\AtTheGatesUI.dll",
    [string]$MapJson = "$PSScriptRoot\..\translations\hardcoded-strings.json",
    [int]$PaddingCodePoint = 32,
    [string[]]$SkipSourceStrings = @()
)

$ErrorActionPreference = "Stop"

if (!(Test-Path -LiteralPath $SourceDll)) {
    throw "Source DLL not found: $SourceDll"
}
if (!(Test-Path -LiteralPath $MapJson)) {
    throw "Hardcoded string map not found: $MapJson"
}

$map = Get-Content -LiteralPath $MapJson -Raw -Encoding UTF8 | ConvertFrom-Json
$bytes = [IO.File]::ReadAllBytes($SourceDll)
$encoding = [Text.Encoding]::Unicode
$paddingChar = [char]$PaddingCodePoint
$skip = @{}
foreach ($sourceToSkip in @($SkipSourceStrings)) {
    if (![string]::IsNullOrWhiteSpace($sourceToSkip)) {
        $skip[[string]$sourceToSkip] = $true
    }
}

Add-Type @"
public static class AtGHardcodedPatcher {
    private static bool IsPrintableUtf16CodeUnit(byte[] bytes, int index) {
        if (index < 0 || index >= bytes.Length - 1) {
            return false;
        }

        int code = bytes[index] + (bytes[index + 1] << 8);
        return (code >= 32 && code <= 126) || code == 9 || code == 10 || code == 13;
    }

    public static int Patch(byte[] bytes, byte[] needle, byte[] replacement) {
        int count = 0;
        for (int i = 0; i <= bytes.Length - needle.Length; i++) {
            if (bytes[i] != needle[0]) {
                continue;
            }

            bool matched = true;
            for (int j = 1; j < needle.Length; j++) {
                if (bytes[i + j] != needle[j]) {
                    matched = false;
                    break;
                }
            }

            if (!matched) {
                continue;
            }

            int before = i - 2;
            int after = i + needle.Length;
            if (IsPrintableUtf16CodeUnit(bytes, before) || IsPrintableUtf16CodeUnit(bytes, after)) {
                continue;
            }

            System.Buffer.BlockCopy(replacement, 0, bytes, i, replacement.Length);
            count++;
            i += needle.Length - 1;
        }

        return count;
    }
}
"@

foreach ($property in $map.PSObject.Properties) {
    $source = [string]$property.Name
    $target = [string]$property.Value

    if ($skip.ContainsKey($source)) {
        Write-Host "Skipping '$source'; covered by another patch path."
        continue
    }

    if ($target.Length -gt $source.Length) {
        throw "Replacement '$target' is longer than source '$source'. Use an equal-or-shorter string."
    }

    $paddingLength = $source.Length - $target.Length
    $padding = if ($paddingLength -gt 0) {
        New-Object string ($paddingChar, $paddingLength)
    }
    else {
        ""
    }
    $paddedTarget = $target + $padding
    $needle = $encoding.GetBytes($source)
    $replacement = $encoding.GetBytes($paddedTarget)
    $count = [AtGHardcodedPatcher]::Patch($bytes, $needle, $replacement)

    if ($count -eq 0) {
        throw "Source string not found in DLL: $source"
    }

    Write-Host "Patched '$source' -> '$target' ($count occurrence(s))."
}

$outDir = Split-Path -Parent $OutputDll
if ($outDir) {
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
}

[IO.File]::WriteAllBytes($OutputDll, $bytes)
Write-Host "Built hardcoded string patch: $OutputDll"
