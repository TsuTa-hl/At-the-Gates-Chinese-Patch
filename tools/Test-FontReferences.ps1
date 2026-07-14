param(
    [string]$PatchRoot = "$PSScriptRoot\..\patch",
    [string]$TempRoot = "$PSScriptRoot\..\.tmp\font-references"
)

$ErrorActionPreference = "Stop"

function Assert-AtG {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (!$Condition) {
        throw $Message
    }
}

$expectedSegoeFonts = @(
    "SegoeUI_UltraTiny",
    "SegoeUI_9",
    "SegoeUI_9_Bold",
    "SegoeUI_11",
    "SegoeUI_11_Bold",
    "SegoeUI_13",
    "SegoeUI_13_Bold",
    "SegoeUI_15",
    "SegoeUI_15_Bold",
    "SegoeUI_16",
    "SegoeUI_16_Bold",
    "SegoeUI_18",
    "SegoeUI_18_Bold",
    "SegoeUI_22_Bold",
    "SegoeUI_36_Bold"
)

$allowedOriginalOnlyFonts = @(
    "Leelawalee_10",
    "LucidaConsole_10_AtG"
)

if (Test-Path -LiteralPath $TempRoot) {
    Remove-Item -LiteralPath $TempRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $TempRoot | Out-Null

$assemblies = @(
    @{ Name = "ui"; Path = Join-Path $PatchRoot "AtTheGatesUI.dll" },
    @{ Name = "common"; Path = Join-Path $PatchRoot "AtTheGatesCommon.dll" },
    @{ Name = "game"; Path = Join-Path $PatchRoot "At The Gates.exe" },
    @{ Name = "elftools"; Path = Join-Path $PatchRoot "ElfTools.dll" }
)

$referencedFonts = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
$unexpectedReferences = New-Object System.Collections.Generic.List[string]

foreach ($assembly in $assemblies) {
    Assert-AtG (Test-Path -LiteralPath $assembly.Path -PathType Leaf) "Patched assembly not found: $($assembly.Path)"

    $jsonPath = Join-Path $TempRoot "$($assembly.Name)-catalog.json"
    $csvPath = Join-Path $TempRoot "$($assembly.Name)-catalog.csv"
    & "$PSScriptRoot\Export-DllLdstrCatalog.ps1" `
        -DllPath $assembly.Path `
        -OutputJson $jsonPath `
        -OutputCsv $csvPath | Out-Null

    $catalog = Get-Content -LiteralPath $jsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($record in @($catalog | Where-Object { $_.Value -like "Images/Interface/Components/Fonts/*" })) {
        $fontName = [System.IO.Path]::GetFileName([string]$record.Value)
        [void]$referencedFonts.Add($fontName)

        $isExpectedSegoe = $expectedSegoeFonts -contains $fontName
        $isAllowedOriginal = $allowedOriginalOnlyFonts -contains $fontName
        if (!$isExpectedSegoe -and !$isAllowedOriginal) {
            $unexpectedReferences.Add(("{0}: {1}.{2} {3} references unexpected font {4}" -f `
                $assembly.Name,
                $record.TypeFullName,
                $record.MethodName,
                $record.ILOffset,
                $fontName)) | Out-Null
        }
    }
}

foreach ($fontName in $expectedSegoeFonts) {
    Assert-AtG ($referencedFonts.Contains($fontName)) "Expected Segoe UI runtime font is not referenced by patched assemblies: $fontName"
}

if ($unexpectedReferences.Count -gt 0) {
    $unexpectedReferences | ForEach-Object { Write-Error $_ }
    throw "Font reference validation failed with $($unexpectedReferences.Count) unexpected font reference(s)."
}

[pscustomobject]@{
    ReferencedFonts = @($referencedFonts | Sort-Object)
    ExpectedSegoeFontCount = $expectedSegoeFonts.Count
    AllowedOriginalOnlyFontCount = $allowedOriginalOnlyFonts.Count
}

Write-Host "Font reference validation passed."
