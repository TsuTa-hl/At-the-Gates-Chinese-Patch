$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$operationsPath = Join-Path $root "docs\agent\operations.md"
$operations = Get-Content -LiteralPath $operationsPath -Raw -Encoding UTF8
$automationPath = Join-Path $root "docs\agent\operations\game-automation.md"
$automation = Get-Content -LiteralPath $automationPath -Raw -Encoding UTF8

$requiredOperationalRules = @(
    "Windows PowerShell 5.1 Desktop remains the supported public and development",
    "apostrophe inside a single-quoted PowerShell string",
    "Launch the game with its working directory set",
    "All coordinates are relative to the game window, not the virtual desktop"
)

foreach ($rule in $requiredOperationalRules) {
    if (-not $operations.Contains($rule)) {
        throw "Canonical operations rule is missing: $rule"
    }
}

if (-not $automation.Contains("A merely visible window is")) {
    throw "Game automation topic is missing the window-ready rule."
}

$knowledgeIndex = Get-Content -LiteralPath (Join-Path $root "docs\agent\knowledge-index.md") -Raw -Encoding UTF8
if (-not $knowledgeIndex.Contains("operations/game-automation.md")) {
    throw "Knowledge index does not route game automation to its dedicated topic."
}

$staleSparkReference = Get-ChildItem -LiteralPath (Join-Path $root "docs\agent") -Recurse -File |
    Select-String -SimpleMatch "spark-delegation.md" -ErrorAction SilentlyContinue
if ($staleSparkReference) {
    throw "Deleted spark-delegation.md is still referenced: $($staleSparkReference[0].Path)"
}

Write-Host "Operational knowledge ownership test passed."
