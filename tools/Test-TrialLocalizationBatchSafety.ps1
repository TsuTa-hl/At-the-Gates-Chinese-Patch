param(
    [string]$OutputDirectory = ".tmp\trial-batch-safety-test"
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$outputRoot = Join-Path $repoRoot $OutputDirectory
New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null

function Write-JsonArray {
    param(
        [string]$Path,
        [object[]]$Items
    )

    $json = $Items | ConvertTo-Json -Depth 8
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, "$json`n", $utf8NoBom)
}

function Assert-BatchFails {
    param(
        [string]$Name,
        [object[]]$Items,
        [string]$Pattern
    )

    $path = Join-Path $outputRoot "$Name.json"
    Write-JsonArray -Path $path -Items $Items

    $failed = $false
    $message = ""
    try {
        & "$PSScriptRoot\Invoke-AtGTrialLocalizationBatch.ps1" -BatchJson $path -PlanOnly | Out-Null
    }
    catch {
        $failed = $true
        $message = $_.Exception.Message
    }

    if (!$failed) {
        throw "Expected trial batch '$Name' to fail safety validation."
    }

    if ($message -notmatch $Pattern) {
        throw "Trial batch '$Name' failed with unexpected message: $message"
    }
}

function Assert-BatchPasses {
    param(
        [string]$Name,
        [object[]]$Items
    )

    $path = Join-Path $outputRoot "$Name.json"
    Write-JsonArray -Path $path -Items $Items
    & "$PSScriptRoot\Invoke-AtGTrialLocalizationBatch.ps1" -BatchJson $path -PlanOnly | Out-Null
}

$unsafeConvertTags = @(
    [pscustomobject]@{
        Assembly = "Common"
        Original = "[UnsafeTag]"
        Translation = "[UnsafeTranslatedTag]"
        MethodToken = "0x06000220"
        ILOffset = 999999
        TypeFullName = "AtTheGatesCommon.ns_Text.Text"
        MethodName = "ConvertTags"
        Safety = "TrialFastFailSparkRecheck"
        EvidenceScenario = "test-unsafe-convert-tags"
    }
)

$replacementChar = [string][char]0xfffd
$mojibake = @(
    [pscustomobject]@{
        Assembly = "UI"
        Original = "Delete Old"
        Translation = ("bad" + $replacementChar + "text")
        MethodToken = "0x0600ffff"
        ILOffset = 123456
        TypeFullName = "Dummy.Type"
        MethodName = "DummyMethod"
        Safety = "TrialFastFail"
        EvidenceScenario = "test-mojibake"
    }
)

$safe = @(
    [pscustomobject]@{
        Assembly = "UI"
        Original = "Delete Old"
        Translation = "Delete stale saves"
        MethodToken = "0x0600ffff"
        ILOffset = 123456
        TypeFullName = "Dummy.Type"
        MethodName = "DummyMethod"
        Safety = "TrialFastFail"
        EvidenceScenario = "test-safe"
    }
)

Assert-BatchFails -Name "unsafe-convert-tags" -Items $unsafeConvertTags -Pattern "ConvertTags|parser"
Assert-BatchFails -Name "mojibake" -Items $mojibake -Pattern "replacement|mojibake|乱码"
Assert-BatchPasses -Name "safe" -Items $safe

Write-Host "Trial localization batch safety checks passed."
