param(
    [string]$WarmsetPath = "$PSScriptRoot\..\translations\runtime-glyph-warmset.tsv",
    [int]$MinimumPairCount = 0
)

$ErrorActionPreference = "Stop"
$resolved = (Resolve-Path -LiteralPath $WarmsetPath).Path
$lines = [IO.File]::ReadAllLines($resolved, [Text.Encoding]::UTF8)
if ($lines.Count -eq 0 -or $lines[0] -ne "# AtG.RuntimeGlyphWarmset v1") {
    throw "Runtime glyph warmset must start with the v1 header."
}

$pairCount = 0
$previousSortKey = $null
foreach ($line in $lines | Select-Object -Skip 1) {
    if ([string]::IsNullOrWhiteSpace($line)) { throw "Warmset cannot contain blank records." }
    $fields = $line.Split("`t")
    if ($fields.Count -ne 7 -or $fields[0] -ne "W") {
        throw "Invalid warmset record: $line"
    }
    $priority = 0
    if (![int]::TryParse($fields[1], [ref]$priority) -or $priority -lt 0 -or $priority -gt 2) {
        throw "Invalid warmset priority: $($fields[1])"
    }
    $fontName = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($fields[2]))
    $characters = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($fields[5]))
    if ([string]::IsNullOrEmpty($fontName) -or [string]::IsNullOrEmpty($characters)) {
        throw "Warmset records require a font and at least one character."
    }
    $codes = @($characters.ToCharArray() | ForEach-Object { [int]$_ })
    $sortedCodes = @($codes | Sort-Object)
    if (($codes | Sort-Object -Unique).Count -ne $codes.Count -or
        [string]::Join(",", $sortedCodes) -cne [string]::Join(",", $codes)) {
        throw "Warmset characters must be sorted and unique: $fontName"
    }
    foreach ($code in $codes) {
        if (!(($code -ge 0x2E80 -and $code -le 0x9FFF) -or
              ($code -ge 0xF900 -and $code -le 0xFAFF) -or
              ($code -ge 0xFE10 -and $code -le 0xFE6F) -or
              ($code -ge 0xFF00 -and $code -le 0xFFEF))) {
            throw "Warmset contains a non-dynamic character U+$($code.ToString('X4'))."
        }
    }
    $sortKey = "{0}|{1}|{2}|{3}" -f $fields[1], $fontName, $fields[3], $fields[4]
    if ($null -ne $previousSortKey -and
        [StringComparer]::Ordinal.Compare($previousSortKey, $sortKey) -gt 0) {
        throw "Warmset records are not deterministically sorted."
    }
    $previousSortKey = $sortKey
    $pairCount += $characters.Length
}

if ($pairCount -lt $MinimumPairCount) {
    throw "Warmset has $pairCount font/glyph pairs; expected at least $MinimumPairCount."
}

Write-Host "Runtime glyph warmset passed: $pairCount font/glyph pairs."
