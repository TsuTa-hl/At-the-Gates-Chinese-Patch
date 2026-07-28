$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot

function Get-Text([string]$RelativePath) {
    $path = Join-Path $root $RelativePath
    if (!(Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required documentation file is missing: $RelativePath"
    }
    return Get-Content -LiteralPath $path -Raw -Encoding UTF8
}

function Require-Text([string]$Text, [string]$Needle, [string]$Description) {
    if (-not $Text.Contains($Needle)) {
        throw "$Description is missing: $Needle"
    }
}

function Test-LocalMarkdownLinks([string]$DocumentationRoot) {
    $files = Get-ChildItem -LiteralPath $DocumentationRoot -Recurse -File -Filter "*.md"
    foreach ($file in $files) {
        $content = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
        $matches = [regex]::Matches($content, '\[[^\]]+\]\(([^)#]+)(?:#[^)]+)?\)')
        foreach ($match in $matches) {
            $target = $match.Groups[1].Value.Trim()
            if ([string]::IsNullOrWhiteSpace($target) -or
                $target -match '^[a-z][a-z0-9+.-]*:' -or
                $target.StartsWith('#')) {
                continue
            }

            $candidate = Join-Path $file.DirectoryName $target
            if (!(Test-Path -LiteralPath $candidate)) {
                throw "Broken local Markdown link in $($file.FullName): $target"
            }
        }
    }
}

$agents = Get-Text "AGENTS.md"
$index = Get-Text "docs\agent\knowledge-index.md"
$testWorkflow = Get-Text "docs\agent\workflows\test-and-loop.md"
$knowledgeWorkflow = Get-Text "docs\agent\workflows\update-knowledge.md"

Require-Text $agents "cleanup-workspace.md" "AGENTS cleanup routing"
Require-Text $agents "knowledge-index.md" "AGENTS knowledge index routing"
Require-Text $agents "Every test session must update" "AGENTS test-update rule"
Require-Text $index "operations/game-automation.md" "Knowledge index automation owner"
Require-Text $index "text-sources/managed-patching.md" "Knowledge index patching owner"
Require-Text $index "black-box/interfaces.md" "Knowledge index interface owner"
Require-Text $index "translations/composite-text-rules.json" "Knowledge index composition authority"
Require-Text $index "Generate-ReviewViews.ps1" "Knowledge index transient review-view generator"
Require-Text $index "crash-risks/startup-and-content.md" "Knowledge index startup risk owner"
Require-Text $index "crash-risks/runtime-and-assets.md" "Knowledge index runtime risk owner"
Require-Text $index "crash-risks/managed-rewrites.md" "Knowledge index managed risk owner"
Require-Text $knowledgeWorkflow "not a pre-test phase" "Knowledge workflow timing rule"

foreach ($workflow in @(
    "docs\agent\workflows\cleanup-workspace.md",
    "docs\agent\workflows\assess-and-fix.md",
    "docs\agent\workflows\package-and-install.md",
    "docs\agent\workflows\test-and-loop.md",
    "docs\agent\workflows\update-knowledge.md"
)) {
    Require-Text (Get-Text $workflow) "knowledge-index.md" "Workflow knowledge index routing in $workflow"
}

$updateIndex = $testWorkflow.IndexOf('Run `update-knowledge.md`')
$failedIndex = $testWorkflow.IndexOf('If the conclusion is `Failed`')
if ($updateIndex -lt 0 -or $failedIndex -lt 0 -or $updateIndex -gt $failedIndex) {
    throw "Test workflow must update knowledge before returning a failed result to assess/fix."
}

$shortDocuments = @{
    "AGENTS.md" = 90
    "docs\agent\operations.md" = 90
    "docs\agent\text-sources.md" = 90
    "docs\agent\black-box-tests.md" = 90
    "docs\agent\crash-risks.md" = 90
    "docs\review\project-inventory.md" = 120
}
foreach ($document in $shortDocuments.Keys) {
    $lineCount = (Get-Content -LiteralPath (Join-Path $root $document) -Encoding UTF8).Count
    if ($lineCount -gt $shortDocuments[$document]) {
        throw "$document is no longer a short routing or inventory document ($lineCount lines)."
    }
}

$requiredPaths = @(
    "docs\agent\operations\build-and-install.md",
    "docs\agent\operations\game-automation.md",
    "docs\agent\operations\diagnostics.md",
    "docs\agent\text-sources\catalog-review.md",
    "docs\agent\text-sources\managed-patching.md",
    "docs\agent\text-sources\ui-source-map.md",
    "docs\agent\text-sources\trial-localization.md",
    "docs\agent\black-box\interfaces.md",
    "docs\agent\crash-risks\startup-and-content.md",
    "docs\agent\crash-risks\runtime-and-assets.md",
    "docs\agent\crash-risks\managed-rewrites.md"
)
foreach ($path in $requiredPaths) {
    if (!(Test-Path -LiteralPath (Join-Path $root $path))) {
        throw "Knowledge index target is missing: $path"
    }
}

$reviewViewGenerator = Join-Path $root "docs\review\Generate-ReviewViews.ps1"
if (!(Test-Path -LiteralPath $reviewViewGenerator -PathType Leaf)) {
    throw "Temporary review-view generator is missing: $reviewViewGenerator"
}

$removedGeneratedViews = @(
    "docs\review\known-texts.csv",
    "docs\review\known-texts.md",
    "docs\review\composite-text-localization.csv",
    "docs\review\localization-todolist.csv",
    "docs\review\localization-todolist.md",
    "docs\agent\composite-text-localization.md",
    "docs\agent\composite-text"
)
foreach ($relativePath in $removedGeneratedViews) {
    $path = Join-Path $root $relativePath
    if (Test-Path -LiteralPath $path) {
        throw "Persistent generated review view must remain deleted: $path"
    }
}

$deletedCandidate = Join-Path $root "docs\review\known-texts-5.5-hanization-candidates.md"
if (Test-Path -LiteralPath $deletedCandidate) {
    throw "Deprecated candidate document must remain deleted: $deletedCandidate"
}

$docsRoot = Join-Path $root "docs"
$staleReferences = Get-ChildItem -LiteralPath $docsRoot -Recurse -File |
    Select-String -SimpleMatch "spark-delegation.md" -ErrorAction SilentlyContinue
if ($staleReferences) {
    throw "Deleted spark delegation document is still referenced: $($staleReferences[0].Path)"
}

$screenshotReferences = Get-ChildItem -LiteralPath $docsRoot -Recurse -File |
    Select-String -Pattern '(?i)\.tmp[\\/](runs|evidence)[\\/].*\.(png|jpe?g)' -ErrorAction SilentlyContinue
if ($screenshotReferences) {
    throw "Documentation must retain historical screenshot evidence through text handoffs, not run/evidence image paths: $($screenshotReferences[0].Path)"
}

Test-LocalMarkdownLinks (Join-Path $root "docs\agent")

Write-Host "Documentation routing test passed."
