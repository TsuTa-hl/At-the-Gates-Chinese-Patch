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

function Forbid-Text([string]$Text, [string]$Needle, [string]$Description) {
    if ($Text.Contains($Needle)) {
        throw "$Description must remain absent: $Needle"
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
$currentStatus = Get-Text "docs\agent\current-status.md"
$operations = Get-Text "docs\agent\operations.md"
$textSources = Get-Text "docs\agent\text-sources.md"
$catalogReview = Get-Text "docs\agent\text-sources\catalog-review.md"
$managedPatching = Get-Text "docs\agent\text-sources\managed-patching.md"
$translationStyle = Get-Text "docs\agent\translation-style.md"
$assessWorkflow = Get-Text "docs\agent\workflows\assess-and-fix.md"
$packageWorkflow = Get-Text "docs\agent\workflows\package-and-install.md"
$publishWorkflow = Get-Text "docs\agent\workflows\publish-release-branch.md"
$testWorkflow = Get-Text "docs\agent\workflows\test-and-loop.md"
$knowledgeWorkflow = Get-Text "docs\agent\workflows\update-knowledge.md"
$buildAndInstall = Get-Text "docs\agent\operations\build-and-install.md"
$architecture = Get-Text "docs\agent\architecture.md"

Require-Text $agents "cleanup-workspace.md" "AGENTS cleanup routing"
Require-Text $agents "knowledge-index.md" "AGENTS knowledge index routing"
Require-Text $index "operations/game-automation.md" "Knowledge index automation owner"
Require-Text $index "architecture.md" "Knowledge index architecture owner"
Require-Text $index "current-status.md" "Knowledge index current-status owner"
Require-Text $index "troubleshooting.md" "Knowledge index troubleshooting owner"
Require-Text $index "text-sources/managed-patching.md" "Knowledge index patching owner"
Require-Text $index "black-box/interfaces.md" "Knowledge index interface owner"
Require-Text $index "translations/composite-text-rules.json" "Knowledge index composition authority"
Require-Text $index "translations/concept-key-translations.json" "Knowledge index concept-key authority"
Require-Text $index "not AI workflow input" "Knowledge index review export boundary"
Require-Text $index "Generate-ReviewViews.ps1" "Knowledge index user review-view generator"
Require-Text $index "crash-risks/startup-and-content.md" "Knowledge index startup risk owner"
Require-Text $index "crash-risks/runtime-and-assets.md" "Knowledge index runtime risk owner"
Require-Text $index "crash-risks/managed-rewrites.md" "Knowledge index managed risk owner"
Require-Text $knowledgeWorkflow "not a test-results log" "Knowledge workflow scope rule"
Require-Text $currentStatus "does not record individual localization repairs" "Current-status scope boundary"
Require-Text $textSources "Never use a user review export as an IL operand." "Text source SQLite boundary"
Require-Text $textSources "Do not create a conditional topic" "Text source one-off topic boundary"
Require-Text $catalogReview "SourceFile" "Catalog exact source-file operand"
Require-Text $catalogReview "AI never generates or reads user review" "Review export usage boundary"
Require-Text $managedPatching "not AI input" "Managed patching review export boundary"
Require-Text $translationStyle "not AI input" "Translation style review export boundary"
Require-Text $translationStyle "concept-key-translations.json" "Translation style concept-key authority"
Require-Text $translationStyle "Prefer a keyed global replacement" "Translation style concept-link reuse rule"
Require-Text $translationStyle "Keep percentages and multipliers distinct" "Translation style numeric semantics"
Require-Text $assessWorkflow "do not use user review exports." "Assess workflow review export boundary"
Require-Text $knowledgeWorkflow "Do not create a topic document for a one-off" "Knowledge workflow one-off topic boundary"
Require-Text $operations "carry one timing chain" "Operations cross-phase timing handoff"
Require-Text $operations "routine test results into knowledge documents." "Operations evidence boundary"
Require-Text $packageWorkflow "-Profile Localization" "Package workflow localization profile"
Require-Text $packageWorkflow "-ChangedPath" "Package workflow changed-path handoff"
Require-Text $packageWorkflow "not as a test-results log" "Package workflow knowledge boundary"
Require-Text $packageWorkflow "documentation-only task" "Package workflow no-game documentation branch"
Require-Text $publishWorkflow '`Release` verification profile' "Publish workflow release profile"
Require-Text $buildAndInstall '`Localization` is the default profile.' "Build operation localization default"
Require-Text $buildAndInstall '`Release` is not a normal-development default.' "Build operation release boundary"
Require-Text $buildAndInstall '`ChangedPath`' "Build operation changed-path selection"
Require-Text $buildAndInstall "documentation-only static branch" "Build operation no-game documentation branch"
Require-Text $architecture '`ChangedPath`' "Architecture changed-path selection"
Require-Text $architecture '`Release` is selected only by an explicit publication request.' "Architecture release boundary"
Require-Text $architecture "no-game static branch" "Architecture no-game documentation branch"
Require-Text $testWorkflow "unless a stop condition applies" "Test workflow failure loop"
Forbid-Text $agents "Use the exact source catalogs under" "Legacy AGENTS CSV operand routing"
Forbid-Text $agents "composite-text-rules.json" "AGENTS composition detail"
Forbid-Text $agents "concept-key-translations.json" "AGENTS concept-link detail"
Forbid-Text $agents "localization-safety-registry.json" "AGENTS localization-safety detail"
Forbid-Text $agents "Every test session must update" "AGENTS test-loop detail"
Forbid-Text $agents "Store one-off" "AGENTS knowledge-maintenance detail"
Forbid-Text $agents "Carry timing" "AGENTS timing detail"
Forbid-Text $agents "Do not stop at reporting" "AGENTS failure-loop detail"
Forbid-Text $assessWorkflow "generated catalog for exact DLL operands" "Legacy assess CSV operand routing"
Forbid-Text $translationStyle "Do not use a global word replacement for concept links" "Retired concept-link global-reuse prohibition"
Forbid-Text $translationStyle "For profession production rows" "One-off profession style rule"
Forbid-Text $translationStyle "For the forage tooltip" "One-off forage style rule"
Forbid-Text $translationStyle "For Relationship Level tooltips" "One-off relationship style rule"
Forbid-Text $translationStyle "For the UBL-TVF residual group" "One-off residual style rule"
Forbid-Text $translationStyle "The profession-study completion notification" "One-off notification style rule"
Forbid-Text $textSources "-audit.md" "One-off audit topic routing"
Forbid-Text $currentStatus "manual visual verification" "Current-status manual-test detail"

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
    "docs\agent\architecture.md",
    "docs\agent\current-status.md",
    "docs\agent\troubleshooting.md",
    "docs\agent\text-sources\catalog-review.md",
    "docs\agent\text-sources\managed-patching.md",
    "docs\agent\text-sources\ui-source-map.md",
    "docs\agent\text-sources\localization-safety.md",
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

$conceptKeyMap = Join-Path $root "translations\concept-key-translations.json"
if (!(Test-Path -LiteralPath $conceptKeyMap -PathType Leaf)) {
    throw "Concept-key translation map is missing: $conceptKeyMap"
}

$conceptKeyGenerator = Join-Path $root "tools\Export-ConceptKeyTranslations.ps1"
if (!(Test-Path -LiteralPath $conceptKeyGenerator -PathType Leaf)) {
    throw "Concept-key translation map generator is missing: $conceptKeyGenerator"
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
