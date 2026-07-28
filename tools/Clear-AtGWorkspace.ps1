[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "High")]
param(
    [string]$WorkspaceRoot,

    [string]$TempRoot,

    [string]$TaskId,

    [switch]$Apply,

    [switch]$KeepVisualEvidence,

    [switch]$RunsOnly
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($WorkspaceRoot)) {
    $WorkspaceRoot = Join-Path $PSScriptRoot ".."
}

function Get-AtGFullPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    return [System.IO.Path]::GetFullPath($Path).TrimEnd([char[]]@('\', '/'))
}

function Test-AtGPathInside {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Root
    )

    $resolvedPath = Get-AtGFullPath $Path
    $resolvedRoot = Get-AtGFullPath $Root
    return $resolvedPath.StartsWith($resolvedRoot + [System.IO.Path]::DirectorySeparatorChar,
        [System.StringComparison]::OrdinalIgnoreCase) -or
        $resolvedPath.Equals($resolvedRoot, [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-AtGDirectorySize {
    param([Parameter(Mandatory = $true)][string]$Path)

    $total = 0L
    if (!(Test-Path -LiteralPath $Path -PathType Container)) {
        return $total
    }

    foreach ($file in Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue) {
        $total += [int64]$file.Length
    }
    return $total
}

function Get-AtGFileSize {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (!(Test-Path -LiteralPath $Path -PathType Leaf)) {
        return 0L
    }
    return [int64](Get-Item -LiteralPath $Path -Force).Length
}

function Get-AtGRelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Root
    )

    $resolvedPath = Get-AtGFullPath $Path
    $resolvedRoot = Get-AtGFullPath $Root
    if ($resolvedPath.Equals($resolvedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        return "."
    }
    return $resolvedPath.Substring($resolvedRoot.Length).TrimStart([char[]]@('\', '/'))
}

function Get-AtGJsonSummary {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$TempRoot
    )

    $summary = [ordered]@{
        Path = Get-AtGRelativePath -Path $Path -Root $TempRoot
    }

    try {
        $value = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -eq $value) {
            return [pscustomobject]$summary
        }

        $preferredNames = @(
            "Id", "Scenario", "ScenarioId", "Title", "Status", "Result", "Outcome",
            "Save", "SaveName", "SavePath", "LoadPath", "WorldId", "WorldID",
            "CrashLogUpdated", "CrashDialogSeen", "Crash", "Error", "Failure",
            "ElapsedMilliseconds", "ElapsedSeconds", "DurationMilliseconds", "DurationSeconds",
            "Clicks", "Hovers", "Screenshots", "RunRoot", "Notes", "Conclusion"
        )
        foreach ($name in $preferredNames) {
            $property = $value.PSObject.Properties[$name]
            if ($null -eq $property) {
                continue
            }
            $text = ($property.Value | ConvertTo-Json -Compress -Depth 4)
            if ($text.Length -gt 1200) {
                $text = $text.Substring(0, 1200) + "..."
            }
            $summary[$name] = $text
        }
    }
    catch {
        $summary["ParseError"] = $_.Exception.Message
    }

    return [pscustomobject]$summary
}

function Get-AtGLogExcerpt {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$TempRoot
    )

    try {
        $lines = @(Get-Content -LiteralPath $Path -Encoding UTF8 -ErrorAction Stop |
            Where-Object { ![string]::IsNullOrWhiteSpace($_) } |
            Select-Object -Last 20)
        $excerpt = ($lines -join "`n")
        if ($excerpt.Length -gt 3000) {
            $excerpt = $excerpt.Substring($excerpt.Length - 3000)
        }
        return [pscustomobject]@{
            Path = Get-AtGRelativePath -Path $Path -Root $TempRoot
            Excerpt = $excerpt
        }
    }
    catch {
        return [pscustomobject]@{
            Path = Get-AtGRelativePath -Path $Path -Root $TempRoot
            ReadError = $_.Exception.Message
        }
    }
}

function Get-AtGActiveRoots {
    param([Parameter(Mandatory = $true)][string]$Root)

    $activeRoots = New-Object System.Collections.Generic.List[string]
    foreach ($marker in Get-ChildItem -LiteralPath $Root -Recurse -File -Filter "active-run.json" -Force -ErrorAction SilentlyContinue) {
        $activeRoots.Add((Get-AtGFullPath $marker.DirectoryName)) | Out-Null
        try {
            $data = Get-Content -LiteralPath $marker.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($property in @($data.PSObject.Properties)) {
                if ($property.Value -isnot [string]) {
                    continue
                }
                $candidate = [string]$property.Value
                if ([string]::IsNullOrWhiteSpace($candidate)) {
                    continue
                }
                if (![System.IO.Path]::IsPathRooted($candidate)) {
                    $candidate = Join-Path $marker.DirectoryName $candidate
                }
                if ((Test-Path -LiteralPath $candidate) -and (Test-AtGPathInside -Path $candidate -Root $Root)) {
                    $activeRoots.Add((Get-AtGFullPath $candidate)) | Out-Null
                }
            }
        }
        catch {
            # A malformed active marker is still a recovery marker. Preserve its parent.
        }
    }

    return @($activeRoots | Select-Object -Unique)
}

function Test-AtGProtectedPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$ActiveRoots,
        [Parameter(Mandatory = $true)][string]$HandoffRoot
    )

    if ($(Test-AtGPathInside -Path $Path -Root $HandoffRoot)) {
        return $true
    }

    foreach ($activeRoot in $ActiveRoots) {
        if ($(Test-AtGPathInside -Path $Path -Root $activeRoot) -or
            $(Test-AtGPathInside -Path $activeRoot -Root $Path)) {
            return $true
        }
    }
    return $false
}

function Add-AtGCandidate {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Candidates,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Kind,
        [Parameter(Mandatory = $true)][string]$TempRoot,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$ActiveRoots,
        [Parameter(Mandatory = $true)][string]$HandoffRoot,
        [switch]$KeepVisualEvidence
    )

    if (!(Test-AtGPathInside -Path $Path -Root $TempRoot)) {
        throw "Refusing to classify a path outside the temporary root: $Path"
    }
    if (Test-AtGProtectedPath -Path $Path -ActiveRoots $ActiveRoots -HandoffRoot $HandoffRoot) {
        return
    }

    $item = Get-Item -LiteralPath $Path -Force
    if ($KeepVisualEvidence) {
        if (!$item.PSIsContainer -and $item.Extension -match "^\.(png|jpe?g|bmp|gif)$") {
            return
        }
        if ($item.PSIsContainer) {
            $visualFile = Get-ChildItem -LiteralPath $item.FullName -Recurse -File -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.Extension -match "^\.(png|jpe?g|bmp|gif)$" } |
                Select-Object -First 1
            if ($null -ne $visualFile) {
                return
            }
        }
    }
    $bytes = if ($item.PSIsContainer) {
        Get-AtGDirectorySize -Path $item.FullName
    }
    else {
        Get-AtGFileSize -Path $item.FullName
    }
    $Candidates.Add([pscustomobject]@{
        Path = $item.FullName
        RelativePath = Get-AtGRelativePath -Path $item.FullName -Root $TempRoot
        Kind = $Kind
        IsDirectory = [bool]$item.PSIsContainer
        LastWriteTimeUtc = $item.LastWriteTimeUtc.ToString("o")
        Bytes = $bytes
    }) | Out-Null
}

$resolvedWorkspace = Get-AtGFullPath $WorkspaceRoot
if (!(Test-Path -LiteralPath $resolvedWorkspace -PathType Container)) {
    throw "Workspace root does not exist: $resolvedWorkspace"
}

if ([string]::IsNullOrWhiteSpace($TempRoot)) {
    $TempRoot = Join-Path $resolvedWorkspace ".tmp"
}
$resolvedTempRoot = Get-AtGFullPath $TempRoot
$workspaceTempRoot = Get-AtGFullPath (Join-Path $resolvedWorkspace ".tmp")
if (!(Test-AtGPathInside -Path $resolvedTempRoot -Root $workspaceTempRoot)) {
    throw "Refusing to clean outside the workspace .tmp directory: $resolvedTempRoot"
}
if (!(Test-Path -LiteralPath $resolvedTempRoot -PathType Container)) {
    [pscustomobject]@{
        SchemaVersion = 1
        TempRoot = $resolvedTempRoot
        CandidateCount = 0
        CandidateBytes = 0
        Message = "Temporary root does not exist."
    } | ConvertTo-Json -Depth 8
    return
}

if ([string]::IsNullOrWhiteSpace($TaskId)) {
    $TaskId = (Get-Date).ToUniversalTime().ToString("yyyyMMdd-HHmmss") + "-cleanup"
}
if ($TaskId -notmatch "^[A-Za-z0-9._-]+$") {
    throw "TaskId may only contain letters, numbers, dot, underscore, and hyphen."
}

$handoffRoot = Join-Path $resolvedTempRoot "cleanup-handoffs"
$handoffDirectory = Join-Path $handoffRoot $TaskId
$handoffPath = Join-Path $handoffDirectory "cleanup-handoff.json"
$activeRoots = @(Get-AtGActiveRoots -Root $resolvedTempRoot)
$candidates = New-Object System.Collections.Generic.List[object]

$knownDirectoryNames = @(
    "runs", "trial-localization", "trial-game-archive", "cached-validation-tests",
    "catalog-rereview", "file-ops-test", "font-compare", "font-references",
    "known-text-review-catalog-green", "known-text-review-catalog-red",
    "known-text-review-test", "composite-knowntext-index-smoke",
    "composite-static-review", "composite-text-catalog-test", "localization-todolist-test",
    "review-views", "optimization-tooling-tests", "resource-monitor",
    "resource-monitor-test", "spark-review-20260704", "trial-batch-safety-test"
)

foreach ($child in Get-ChildItem -LiteralPath $resolvedTempRoot -Force) {
    if ($child.Name -eq "cleanup-handoffs") {
        continue
    }
    if ($child.PSIsContainer) {
        $isKnown = $knownDirectoryNames -contains $child.Name -or
            $child.Name -match "^(spark-review-|resource-monitor-|known-text-review-|trial-|font-)"
        if (!$isKnown) {
            continue
        }
        if ($RunsOnly -and $child.Name -ne "runs") {
            continue
        }
        if ($child.Name -in @("runs", "trial-localization", "trial-game-archive")) {
            foreach ($subdirectory in Get-ChildItem -LiteralPath $child.FullName -Directory -Force -ErrorAction SilentlyContinue) {
                Add-AtGCandidate -Candidates $candidates -Path $subdirectory.FullName -Kind $child.Name `
                    -TempRoot $resolvedTempRoot -ActiveRoots $activeRoots -HandoffRoot $handoffRoot `
                    -KeepVisualEvidence:$KeepVisualEvidence
            }
            foreach ($file in Get-ChildItem -LiteralPath $child.FullName -File -Force -ErrorAction SilentlyContinue) {
                if ($file.Name -eq "active-run.json") {
                    continue
                }
                Add-AtGCandidate -Candidates $candidates -Path $file.FullName -Kind $child.Name `
                    -TempRoot $resolvedTempRoot -ActiveRoots $activeRoots -HandoffRoot $handoffRoot `
                    -KeepVisualEvidence:$KeepVisualEvidence
            }
        }
        else {
            Add-AtGCandidate -Candidates $candidates -Path $child.FullName -Kind "tool-output" `
                -TempRoot $resolvedTempRoot -ActiveRoots $activeRoots -HandoffRoot $handoffRoot `
                -KeepVisualEvidence:$KeepVisualEvidence
        }
    }
    elseif (!$RunsOnly -and $child.Name -notin @("active-run.json", ".keep")) {
        Add-AtGCandidate -Candidates $candidates -Path $child.FullName -Kind "scratch-file" `
            -TempRoot $resolvedTempRoot -ActiveRoots $activeRoots -HandoffRoot $handoffRoot `
            -KeepVisualEvidence:$KeepVisualEvidence
    }
}

$jsonSummaries = New-Object System.Collections.Generic.List[object]
$logExcerpts = New-Object System.Collections.Generic.List[object]
$visualEvidenceCount = 0
foreach ($candidate in $candidates) {
    $files = if ($candidate.IsDirectory) {
        @(Get-ChildItem -LiteralPath $candidate.Path -Recurse -File -Force -ErrorAction SilentlyContinue)
    }
    else {
        @((Get-Item -LiteralPath $candidate.Path -Force))
    }
    foreach ($file in $files) {
        if ($file.Extension -match "^\.(png|jpe?g|bmp|gif)$") {
            $visualEvidenceCount++
            continue
        }
        if ($file.Extension -eq ".json" -and $file.Name -match "(run-summary|finding|result|accepted|rejected|active-run)") {
            $jsonSummaries.Add((Get-AtGJsonSummary -Path $file.FullName -TempRoot $resolvedTempRoot)) | Out-Null
            continue
        }
        if ($file.Extension -eq ".log" -or $file.Name -match "(crash|smoke|build).*(log|txt)$") {
            $logExcerpts.Add((Get-AtGLogExcerpt -Path $file.FullName -TempRoot $resolvedTempRoot)) | Out-Null
        }
    }
}

$candidateBytes = [int64](($candidates | Measure-Object -Property Bytes -Sum).Sum)
$handoff = [ordered]@{
    SchemaVersion = 1
    GeneratedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
    TaskId = $TaskId
    TempRoot = $resolvedTempRoot
    Scope = if ($RunsOnly) { "RunsOnly" } else { "TaskStart" }
    ApplyRequested = [bool]$Apply
    KeepVisualEvidence = [bool]$KeepVisualEvidence
    CandidateCount = $candidates.Count
    CandidateBytes = $candidateBytes
    CandidateMiB = [Math]::Round($candidateBytes / 1MB, 2)
    ActiveRecoveryRoots = @($activeRoots | ForEach-Object { Get-AtGRelativePath -Path $_ -Root $resolvedTempRoot })
    VisualEvidenceCount = $visualEvidenceCount
    Candidates = @($candidates | Sort-Object Bytes -Descending)
    JsonSummaries = @($jsonSummaries | Select-Object -First 160)
    LogExcerpts = @($logExcerpts | Select-Object -First 40)
}

$canApply = $Apply -and -not $WhatIfPreference
$removedEmptyDirectories = New-Object System.Collections.Generic.List[string]
if ($canApply) {
    New-Item -ItemType Directory -Force -Path $handoffDirectory | Out-Null
    $handoff | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $handoffPath -Encoding UTF8
    foreach ($candidate in @($candidates | Sort-Object { $_.Path.Length } -Descending)) {
        if (!(Test-AtGPathInside -Path $candidate.Path -Root $resolvedTempRoot)) {
            throw "Refusing to remove a path outside the temporary root: $($candidate.Path)"
        }
        # Removal is already guarded by the explicit -Apply flag and -WhatIf above.
        Remove-Item -LiteralPath $candidate.Path -Recurse -Force
    }

    foreach ($directoryName in $knownDirectoryNames) {
        $directoryPath = Join-Path $resolvedTempRoot $directoryName
        if (!(Test-Path -LiteralPath $directoryPath -PathType Container)) {
            continue
        }
        if (Test-AtGProtectedPath -Path $directoryPath -ActiveRoots $activeRoots -HandoffRoot $handoffRoot) {
            continue
        }
        $remainingChildren = @(Get-ChildItem -LiteralPath $directoryPath -Force -ErrorAction SilentlyContinue)
        if ($remainingChildren.Count -eq 0) {
            Remove-Item -LiteralPath $directoryPath -Force
            $removedEmptyDirectories.Add((Get-AtGRelativePath -Path $directoryPath -Root $resolvedTempRoot)) | Out-Null
        }
    }
}

$result = [ordered]@{}
foreach ($property in $handoff.GetEnumerator()) {
    $result[$property.Key] = $property.Value
}
$result["Deleted"] = [bool]$canApply
$result["HandoffPath"] = if ($canApply) { Get-AtGRelativePath -Path $handoffPath -Root $resolvedTempRoot } else { $null }
$result["RemovedEmptyDirectories"] = @($removedEmptyDirectories)
[pscustomobject]$result | ConvertTo-Json -Depth 12
