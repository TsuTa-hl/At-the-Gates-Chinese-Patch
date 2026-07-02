param(
    [string]$OutputDirectory = ".\.tmp\known-text-review-test"
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$outRoot = Join-Path $repoRoot $OutputDirectory
New-Item -ItemType Directory -Force -Path $outRoot | Out-Null

$csvPath = Join-Path $outRoot "known-texts.csv"

& (Join-Path $PSScriptRoot "Export-KnownTextReview.ps1") `
    -CsvOutputPath $csvPath | Out-Null

if (!(Test-Path -LiteralPath $csvPath -PathType Leaf)) {
    throw "CSV review output was not generated: $csvPath"
}

$rows = @(Import-Csv -LiteralPath $csvPath -Encoding UTF8)
if ($rows.Count -lt 1000) {
    throw "CSV review output has too few rows: $($rows.Count)"
}

$requiredColumns = @(
    "SourceFile",
    "Kind",
    "Original",
    "Translation",
    "Status",
    "LocalizationAttempted",
    "AttemptStatus",
    "FailureReason",
    "Safety",
    "Locators"
)

$columns = @($rows[0].PSObject.Properties.Name)
foreach ($column in $requiredColumns) {
    if ($columns -notcontains $column) {
        throw "CSV review output is missing required column: $column"
    }
}

$expectedLoginTranslation = ([string][char]0x767b) + ([string][char]0x5f55)
$translatedAttempt = $rows | Where-Object {
    $_.Original -eq "Log In" -and
    $_.Translation -eq $expectedLoginTranslation -and
    $_.LocalizationAttempted -eq "Yes" -and
    $_.AttemptStatus -match "Accepted|Mapped"
} | Select-Object -First 1
if ($null -eq $translatedAttempt) {
    throw "CSV does not mark accepted translated entry 'Log In' as attempted."
}

$rejectedAttempt = $rows | Where-Object {
    $_.Original -eq "Leave" -and
    $_.LocalizationAttempted -eq "Yes" -and
    $_.AttemptStatus -eq "Rejected" -and
    $_.FailureReason -match "490295" -and
    $_.Locators -match "ILOffset=1774"
} | Select-Object -First 1
if ($null -eq $rejectedAttempt) {
    throw "CSV does not include rejected 'Leave ' attempt with offset-conflict failure reason."
}

$unattempted = $rows | Where-Object {
    $_.Status -eq "UntranslatedDiscovered" -and
    $_.LocalizationAttempted -eq "No"
} | Select-Object -First 1
if ($null -eq $unattempted) {
    throw "CSV does not contain any unattempted discovered text rows."
}

$skipped = $rows | Where-Object {
    $_.LocalizationAttempted -eq "No" -and
    $_.AttemptStatus -eq "SkippedByPolicy" -and
    $_.FailureReason -match "Skipped by policy:"
} | Select-Object -First 1
if ($null -eq $skipped) {
    throw "CSV does not mark policy-skipped unattempted text with an explicit reason."
}

[pscustomobject]@{
    CsvPath = (Resolve-Path -LiteralPath $csvPath).Path
    RowCount = $rows.Count
}

Write-Host "Known text review export validation passed."
