[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string[]]$TracePath,
    [string]$ExpectedMode,
    [int]$SkipFrames = 0,
    [int]$MinimumFrames = 1,
    [switch]$RequireNoFallback,
    [switch]$RequireNoRasterOrUpload,
    [switch]$EnforceBudgetedThresholds,
    [double]$MaximumMainThreadP95Ms = 2.0,
    [double]$MaximumSingleUploadMs = 4.0,
    [int]$MaximumAtlasPages = 8,
    [int]$MaximumPendingRequests = 4096,
    [int]$MaximumReadyGlyphs = 256,
    [string]$LegacySummaryPath,
    [string]$OutputPath
)

$ErrorActionPreference = "Stop"

if ($SkipFrames -lt 0) { throw "SkipFrames cannot be negative." }
if ($MinimumFrames -lt 1) { throw "MinimumFrames must be at least one." }
if ($MaximumMainThreadP95Ms -lt 0) { throw "MaximumMainThreadP95Ms cannot be negative." }
if ($MaximumSingleUploadMs -lt 0) { throw "MaximumSingleUploadMs cannot be negative." }

function Get-AtGPercentile {
    param(
        [double[]]$Values,
        [double]$Percentile
    )
    if ($Values.Count -eq 0) { return 0.0 }
    $sorted = @($Values | Sort-Object)
    $rank = [Math]::Ceiling($Percentile * $sorted.Count)
    $index = [Math]::Max(0, [Math]::Min($sorted.Count - 1, $rank - 1))
    return [double]$sorted[$index]
}

function Get-AtGMaximum {
    param([double[]]$Values)
    if ($Values.Count -eq 0) { return 0.0 }
    return [double](($Values | Measure-Object -Maximum).Maximum)
}

function Get-AtGSum {
    param(
        [object[]]$Frames,
        [string]$Property
    )
    return [Int64](($Frames | Measure-Object -Property $Property -Sum).Sum)
}

$requiredProperties = @(
    "mode",
    "mainThreadMs",
    "uploadMs",
    "maxUploadMs",
    "rasterMs",
    "uploads",
    "rasterized",
    "requests",
    "lookups",
    "hits",
    "misses",
    "fallbacks",
    "warmSkips",
    "budgetStops",
    "pageCreations",
    "deviceResets",
    "maxPending",
    "maxReady",
    "atlasPages"
)

$frames = [Collections.Generic.List[object]]::new()
$resolvedPaths = [Collections.Generic.List[string]]::new()
foreach ($path in $TracePath) {
    $resolved = (Resolve-Path -LiteralPath $path).Path
    $resolvedPaths.Add($resolved)
    $fileFrames = [Collections.Generic.List[object]]::new()
    $lineNumber = 0
    foreach ($line in [IO.File]::ReadLines($resolved, [Text.Encoding]::UTF8)) {
        $lineNumber++
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $frame = $line | ConvertFrom-Json }
        catch {
            throw "Invalid runtime performance JSON in '$resolved' at line ${lineNumber}: $($_.Exception.Message)"
        }
        $properties = @($frame.PSObject.Properties.Name)
        foreach ($required in $requiredProperties) {
            if ($required -notin $properties) {
                throw "Runtime performance entry '$resolved' line $lineNumber is missing '$required'."
            }
        }
        $fileFrames.Add($frame)
    }
    foreach ($frame in @($fileFrames | Select-Object -Skip $SkipFrames)) {
        $frames.Add($frame)
    }
}

if ($frames.Count -lt $MinimumFrames) {
    throw "Runtime performance trace has $($frames.Count) analyzed frames; expected at least $MinimumFrames."
}

$modes = @($frames | ForEach-Object { [string]$_.mode } | Sort-Object -Unique)
if ($modes.Count -ne 1) {
    throw "Runtime performance trace mixes glyph modes: $([string]::Join(', ', $modes))."
}
$mode = [string]$modes[0]
if (![string]::IsNullOrWhiteSpace($ExpectedMode) -and
    ![string]::Equals($mode, $ExpectedMode, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Runtime performance mode is '$mode'; expected '$ExpectedMode'."
}

$activeFrames = @($frames | Where-Object {
        [double]$_.mainThreadMs -gt 0 -or
        [int]$_.lookups -gt 0 -or
        [int]$_.requests -gt 0 -or
        [int]$_.uploads -gt 0
    })
if ($activeFrames.Count -eq 0) { $activeFrames = @($frames) }

$mainThreadValues = [double[]]@($activeFrames | ForEach-Object { [double]$_.mainThreadMs })
$uploadValues = [double[]]@($activeFrames | ForEach-Object { [double]$_.uploadMs })
$singleUploadValues = [double[]]@($frames | ForEach-Object { [double]$_.maxUploadMs })
$lookups = Get-AtGSum -Frames $frames -Property "lookups"
$hits = Get-AtGSum -Frames $frames -Property "hits"
$hitRate = if ($lookups -eq 0) { 0.0 } else { $hits / [double]$lookups }
$atlasMaximum = [int](($frames | Measure-Object -Property atlasPages -Maximum).Maximum)
$pendingMaximum = [int](($frames | Measure-Object -Property maxPending -Maximum).Maximum)
$readyMaximum = [int](($frames | Measure-Object -Property maxReady -Maximum).Maximum)

$summary = [pscustomobject]@{
    Mode = $mode
    TracePaths = @($resolvedPaths)
    FrameCount = $frames.Count
    ActiveFrameCount = $activeFrames.Count
    SkippedFramesPerTrace = $SkipFrames
    MainThreadMs = [pscustomobject]@{
        P50 = [Math]::Round((Get-AtGPercentile -Values $mainThreadValues -Percentile 0.50), 3)
        P95 = [Math]::Round((Get-AtGPercentile -Values $mainThreadValues -Percentile 0.95), 3)
        P99 = [Math]::Round((Get-AtGPercentile -Values $mainThreadValues -Percentile 0.99), 3)
        Maximum = [Math]::Round((Get-AtGMaximum -Values $mainThreadValues), 3)
    }
    UploadMs = [pscustomobject]@{
        P95 = [Math]::Round((Get-AtGPercentile -Values $uploadValues -Percentile 0.95), 3)
        MaximumPerFrame = [Math]::Round((Get-AtGMaximum -Values $uploadValues), 3)
        MaximumSingleOperation = [Math]::Round((Get-AtGMaximum -Values $singleUploadValues), 3)
    }
    Totals = [pscustomobject]@{
        Uploads = Get-AtGSum -Frames $frames -Property "uploads"
        Rasterized = Get-AtGSum -Frames $frames -Property "rasterized"
        Requests = Get-AtGSum -Frames $frames -Property "requests"
        Lookups = $lookups
        Hits = $hits
        Misses = Get-AtGSum -Frames $frames -Property "misses"
        Fallbacks = Get-AtGSum -Frames $frames -Property "fallbacks"
        WarmSkips = Get-AtGSum -Frames $frames -Property "warmSkips"
        BudgetStops = Get-AtGSum -Frames $frames -Property "budgetStops"
        PageCreations = Get-AtGSum -Frames $frames -Property "pageCreations"
        DeviceResets = Get-AtGSum -Frames $frames -Property "deviceResets"
    }
    HitRate = [Math]::Round($hitRate, 6)
    Maximums = [pscustomobject]@{
        AtlasPages = $atlasMaximum
        PendingRequests = $pendingMaximum
        ReadyGlyphs = $readyMaximum
    }
    Thresholds = [pscustomobject]@{
        EnforceBudgetedThresholds = [bool]$EnforceBudgetedThresholds
        MaximumMainThreadP95Ms = $MaximumMainThreadP95Ms
        MaximumSingleUploadMs = $MaximumSingleUploadMs
        MaximumAtlasPages = $MaximumAtlasPages
        MaximumPendingRequests = $MaximumPendingRequests
        MaximumReadyGlyphs = $MaximumReadyGlyphs
    }
}

$violations = [Collections.Generic.List[string]]::new()
if ($atlasMaximum -gt $MaximumAtlasPages) {
    $violations.Add("Atlas pages $atlasMaximum exceed $MaximumAtlasPages.")
}
if ($pendingMaximum -gt $MaximumPendingRequests) {
    $violations.Add("Pending requests $pendingMaximum exceed $MaximumPendingRequests.")
}
if ($readyMaximum -gt $MaximumReadyGlyphs) {
    $violations.Add("Ready glyphs $readyMaximum exceed $MaximumReadyGlyphs.")
}
if ($RequireNoFallback -and $summary.Totals.Fallbacks -ne 0) {
    $violations.Add("Observed $($summary.Totals.Fallbacks) fallback draws.")
}
if ($RequireNoRasterOrUpload -and
    ($summary.Totals.Rasterized -ne 0 -or $summary.Totals.Uploads -ne 0)) {
    $violations.Add(
        "Hot replay performed $($summary.Totals.Rasterized) rasterizations and $($summary.Totals.Uploads) uploads.")
}
if ($EnforceBudgetedThresholds) {
    if ($summary.MainThreadMs.P95 -gt $MaximumMainThreadP95Ms) {
        $violations.Add(
            "Main-thread font P95 $($summary.MainThreadMs.P95) ms exceeds $MaximumMainThreadP95Ms ms.")
    }
    if ($summary.UploadMs.MaximumSingleOperation -gt $MaximumSingleUploadMs) {
        $violations.Add(
            "Single upload peak $($summary.UploadMs.MaximumSingleOperation) ms exceeds $MaximumSingleUploadMs ms.")
    }
}

if (![string]::IsNullOrWhiteSpace($LegacySummaryPath)) {
    $resolvedLegacy = (Resolve-Path -LiteralPath $LegacySummaryPath).Path
    $legacy = Get-Content -LiteralPath $resolvedLegacy -Raw -Encoding UTF8 | ConvertFrom-Json
    $legacyMaximum = [double]$legacy.MainThreadMs.Maximum
    if ($legacyMaximum -gt 4.0 -and
        $summary.MainThreadMs.Maximum -gt ($legacyMaximum * 0.5)) {
        $violations.Add(
            "Budgeted peak $($summary.MainThreadMs.Maximum) ms is not at least 50% below LegacySync peak $legacyMaximum ms.")
    }
}

$summary | Add-Member -NotePropertyName Violations -NotePropertyValue @($violations)

if (![string]::IsNullOrWhiteSpace($OutputPath)) {
    $resolvedOutput = [IO.Path]::GetFullPath($OutputPath)
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($resolvedOutput)) | Out-Null
    $summary | ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath $resolvedOutput -Encoding UTF8
}

if ($violations.Count -gt 0) {
    throw "Runtime glyph performance verification failed: $([string]::Join(' ', $violations))"
}

$summary
