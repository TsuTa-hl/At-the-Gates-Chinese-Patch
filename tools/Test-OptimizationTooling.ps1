param(
    [string]$TempRoot = "$PSScriptRoot\..\.tmp\optimization-tooling-tests"
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path -LiteralPath "$PSScriptRoot\..").Path

function Assert-AtG {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (!$Condition) {
        throw $Message
    }
}

function Get-ImageSize {
    param([string]$Path)

    Add-Type -AssemblyName System.Drawing
    $image = [System.Drawing.Image]::FromFile((Resolve-Path -LiteralPath $Path).Path)
    try {
        return [pscustomobject]@{
            Width = $image.Width
            Height = $image.Height
        }
    }
    finally {
        $image.Dispose()
    }
}

if (Test-Path -LiteralPath $TempRoot) {
    Remove-Item -LiteralPath $TempRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $TempRoot | Out-Null

$dummyDll = Join-Path $TempRoot "ProbeLdstr.dll"
Add-Type -TypeDefinition @"
public class ProbeLdstr {
    public static string Idle() { return "Settlement is Idle"; }
    public static string Tooltip() { return "Click to see what "; }
    public static string Keep() { return "Keep English"; }
    public static string RepeatA() { return "Same Text"; }
    public static string RepeatB() { return "Same Text"; }
    public static string Space() { return " "; }
}
"@ -OutputAssembly $dummyDll -OutputType Library

$catalogJson = Join-Path $TempRoot "catalog.json"
$catalogCsv = Join-Path $TempRoot "catalog.csv"
& "$PSScriptRoot\Export-DllLdstrCatalog.ps1" `
    -DllPath $dummyDll `
    -OutputJson $catalogJson `
    -OutputCsv $catalogCsv

$catalog = Get-Content -LiteralPath $catalogJson -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-AtG (@($catalog | Where-Object { $_.Value -eq "Settlement is Idle" }).Count -eq 1) "Catalog did not include the idle string."
Assert-AtG (@($catalog | Where-Object { $_.Value -eq "Click to see what " }).Count -eq 1) "Catalog did not include the tooltip string."
$idleRecord = $catalog | Where-Object { $_.Value -eq "Settlement is Idle" } | Select-Object -First 1
Assert-AtG (![string]::IsNullOrWhiteSpace([string]$idleRecord.MethodToken)) "Catalog did not include MethodToken."
Assert-AtG (![string]::IsNullOrWhiteSpace([string]$idleRecord.StringToken)) "Catalog did not include StringToken."

$patchMap = Join-Path $TempRoot "ui-il-map.json"
@(
    [pscustomobject]@{
        Original = "Settlement is Idle"
        Translation = "IdleCN"
        Safety = "SafeUI"
    }
) | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $patchMap -Encoding UTF8

$patchedDll = Join-Path $TempRoot "ProbeLdstr.patched.dll"
& "$PSScriptRoot\Build-IlStringPatch.ps1" `
    -SourceDll $dummyDll `
    -OutputDll $patchedDll `
    -MapJson $patchMap

$patchedCatalogJson = Join-Path $TempRoot "patched-catalog.json"
& "$PSScriptRoot\Export-DllLdstrCatalog.ps1" `
    -DllPath $patchedDll `
    -OutputJson $patchedCatalogJson `
    -OutputCsv (Join-Path $TempRoot "patched-catalog.csv")
$patchedCatalog = Get-Content -LiteralPath $patchedCatalogJson -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-AtG (@($patchedCatalog | Where-Object { $_.Value -eq "Settlement is Idle" }).Count -eq 0) "IL patch left the original idle string visible."
Assert-AtG (@($patchedCatalog | Where-Object { $_.Value -eq "IdleCN" }).Count -eq 1) "IL patch did not expose the translated idle string."
Assert-AtG (@($patchedCatalog | Where-Object { $_.Value -eq "Keep English" }).Count -eq 1) "IL patch changed an unrelated string."

$tooltipRecord = $catalog | Where-Object { $_.Value -eq "Click to see what " } | Select-Object -First 1
$repeatRecord = $catalog | Where-Object { $_.Value -eq "Same Text" } | Sort-Object MethodToken | Select-Object -First 1
$spaceRecord = $catalog | Where-Object { $_.Value -eq " " } | Select-Object -First 1
Assert-AtG ($null -ne $tooltipRecord) "Catalog did not include the tooltip record for rewrite testing."
Assert-AtG ($null -ne $repeatRecord) "Catalog did not include duplicate records for rewrite testing."
Assert-AtG ($null -ne $spaceRecord) "Catalog did not include the whitespace-only record for rewrite testing."

$rewriteMap = Join-Path $TempRoot "ui-il-rewrite-map.json"
$longTranslation = "中文-This replacement is much longer than the original tooltip text"
@(
    [pscustomobject]@{
        Original = "Click to see what "
        Translation = $longTranslation
        MethodToken = $tooltipRecord.MethodToken
        ILOffset = $tooltipRecord.ILOffset
        Safety = "SafeUI"
    },
    [pscustomobject]@{
        Original = "Same Text"
        Translation = "ScopedOnly"
        MethodToken = $repeatRecord.MethodToken
        ILOffset = $repeatRecord.ILOffset
        Safety = "SafeUI"
    },
    [pscustomobject]@{
        Original = " "
        Translation = "SpaceCN"
        MethodToken = $spaceRecord.MethodToken
        ILOffset = $spaceRecord.ILOffset
        Safety = "SafeUI"
    }
) | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $rewriteMap -Encoding UTF8

$rewrittenDll = Join-Path $TempRoot "ProbeLdstr.rewritten.dll"
& "$PSScriptRoot\Build-IlRewritePatch.ps1" `
    -SourceDll $dummyDll `
    -OutputDll $rewrittenDll `
    -MapJson $rewriteMap

$rewrittenCatalogJson = Join-Path $TempRoot "rewritten-catalog.json"
& "$PSScriptRoot\Export-DllLdstrCatalog.ps1" `
    -DllPath $rewrittenDll `
    -OutputJson $rewrittenCatalogJson `
    -OutputCsv (Join-Path $TempRoot "rewritten-catalog.csv")
$rewrittenCatalog = Get-Content -LiteralPath $rewrittenCatalogJson -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-AtG (@($rewrittenCatalog | Where-Object { $_.Value -eq "Click to see what " }).Count -eq 0) "IL rewrite left the original tooltip string visible."
Assert-AtG (@($rewrittenCatalog | Where-Object { $_.Value -eq $longTranslation }).Count -eq 1) "IL rewrite did not expose the long translated string."
Assert-AtG (@($rewrittenCatalog | Where-Object { $_.Value -match [char]0x200B }).Count -eq 0) "IL rewrite emitted zero-width padding characters."
Assert-AtG (@($rewrittenCatalog | Where-Object { $_.Value -eq "ScopedOnly" }).Count -eq 1) "IL rewrite did not patch the scoped duplicate string."
Assert-AtG (@($rewrittenCatalog | Where-Object { $_.Value -eq "Same Text" }).Count -eq 1) "IL rewrite did not preserve the non-target duplicate string."
Assert-AtG (@($rewrittenCatalog | Where-Object { $_.Value -eq "SpaceCN" }).Count -eq 1) "IL rewrite did not patch the whitespace-only string."
Assert-AtG (@($rewrittenCatalog | Where-Object { $_.Value -eq " " }).Count -eq 0) "IL rewrite left the whitespace-only original string visible."

$badRewriteMap = Join-Path $TempRoot "ui-il-rewrite-bad-map.json"
@(
    [pscustomobject]@{
        Original = "Wrong Original"
        Translation = "ShouldFail"
        MethodToken = $tooltipRecord.MethodToken
        ILOffset = $tooltipRecord.ILOffset
    }
) | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $badRewriteMap -Encoding UTF8
$badRewriteFailed = $false
$badRewriteErrorLog = Join-Path $TempRoot "bad-rewrite.stderr.txt"
try {
    & "$PSScriptRoot\Build-IlRewritePatch.ps1" `
        -SourceDll $dummyDll `
        -OutputDll (Join-Path $TempRoot "ProbeLdstr.bad-rewrite.dll") `
        -MapJson $badRewriteMap 2> $badRewriteErrorLog | Out-Null
}
catch {
    $badRewriteFailed = $true
}
Assert-AtG $badRewriteFailed "IL rewrite accepted an entry whose Original did not match the target ldstr."

$rewriterOutputDir = Join-Path $repoRoot "tools\AtG.IlRewrite\bin\Debug\net8.0"
$rewriterDll = Join-Path $rewriterOutputDir "AtG.IlRewrite.dll"
$rewriterAppHost = Join-Path $rewriterOutputDir "AtG.IlRewrite.exe"
Assert-AtG (Test-Path -LiteralPath $rewriterDll -PathType Leaf) "IL rewrite DLL was not built: $rewriterDll"
Assert-AtG (!(Test-Path -LiteralPath $rewriterAppHost -PathType Leaf)) "IL rewrite build must not leave an apphost executable. Use repo-local dotnet to run AtG.IlRewrite.dll instead: $rewriterAppHost"

. "$PSScriptRoot\AtGTiming.ps1"
$summary = New-AtGTimingSummary
Measure-AtGStage -Summary $summary -Name "probe" -ScriptBlock { Start-Sleep -Milliseconds 20 } | Out-Null
Assert-AtG ($summary.Stages.Count -eq 1) "Timing summary did not record a stage."
Assert-AtG ($summary.Stages[0].DurationMs -gt 0) "Timing stage duration was not positive."
Assert-AtG (@(Get-AtGTimingReport -Summary $summary).Count -eq 1) "Timing report did not contain one row."

$sourceImage = Join-Path $TempRoot "source.png"
Add-Type -AssemblyName System.Drawing
$bitmap = New-Object System.Drawing.Bitmap 400, 240
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.Clear([System.Drawing.Color]::Black)
$brush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::Red)
$graphics.FillRectangle($brush, 10, 20, 120, 60)
$brush.Dispose()
$graphics.Dispose()
$bitmap.Save($sourceImage, [System.Drawing.Imaging.ImageFormat]::Png)
$bitmap.Dispose()

$cropImage = Join-Path $TempRoot "crop.png"
& "$PSScriptRoot\Crop-AtGImage.ps1" `
    -SourcePath $sourceImage `
    -OutputPath $cropImage `
    -X 10 `
    -Y 20 `
    -Width 120 `
    -Height 60
$cropSize = Get-ImageSize -Path $cropImage
Assert-AtG ($cropSize.Width -eq 120 -and $cropSize.Height -eq 60) "Cropped image dimensions were wrong."

$contactSheet = Join-Path $TempRoot "contact.png"
& "$PSScriptRoot\New-AtGContactSheet.ps1" `
    -ImagePath @($sourceImage, $cropImage) `
    -OutputPath $contactSheet `
    -Columns 2 `
    -CellWidth 200 `
    -CellHeight 140
$contactSize = Get-ImageSize -Path $contactSheet
Assert-AtG ($contactSize.Width -eq 400 -and $contactSize.Height -eq 140) "Contact sheet dimensions were wrong."

Write-Host "Optimization tooling tests passed."
