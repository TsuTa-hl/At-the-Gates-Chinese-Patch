param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-AtGSourceCapture {
    param([bool]$Condition, [string]$Message)

    if (!$Condition) {
        throw $Message
    }
}

$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$testRoot = Join-Path $projectRoot '.tmp\initialize-source-test'
$gameRoot = Join-Path $testRoot 'game'
$sourceRoot = Join-Path $testRoot 'source'

if (Test-Path -LiteralPath $testRoot) {
    Remove-Item -LiteralPath $testRoot -Recurse -Force
}

try {
    New-Item -ItemType Directory -Force -Path @(
        (Join-Path $gameRoot 'Content\Text'),
        (Join-Path $gameRoot 'Content\Config\Primary'),
        (Join-Path $gameRoot 'Content\Images\Interface\ScreenSpecific\ClanCard')
    ) | Out-Null

    [IO.File]::WriteAllText((Join-Path $gameRoot 'At The Gates.exe'), 'game', [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $gameRoot 'AtTheGatesUI.dll'), 'ui', [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $gameRoot 'AtTheGatesCommon.dll'), 'common', [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $gameRoot 'ElfTools.dll'), 'elftools', [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $gameRoot 'Content\Text\English.xml'), '<english />', [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $gameRoot 'Content\Config\Primary\ClanTraits.xml'), '<items />', [Text.UTF8Encoding]::new($false))

    & (Join-Path $projectRoot 'tools\Initialize-AtGSource.ps1') -GamePath $gameRoot -SourceRoot $sourceRoot -Refresh

    $renamedConfig = Join-Path $sourceRoot 'Content\Config\Primary\ClanTraits.original.xml'
    Assert-AtGSourceCapture (Test-Path -LiteralPath $renamedConfig -PathType Leaf) 'Config source XML must be captured with the .original.xml suffix.'
    Assert-AtGSourceCapture (!(Test-Path -LiteralPath (Join-Path $sourceRoot 'Content\Config\Primary\ClanTraits.xml'))) 'Raw config XML must not be left beside the original-suffixed build input.'
    Assert-AtGSourceCapture (Test-Path -LiteralPath (Join-Path $sourceRoot 'English.original.xml') -PathType Leaf) 'English source snapshot is missing.'
    $manifest = Get-Content -LiteralPath (Join-Path $sourceRoot '.atg-source-manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-AtGSourceCapture (@($manifest.Files.RelativePath) -contains 'Content\Config\Primary\ClanTraits.original.xml') 'Source manifest must record the renamed config input.'

    [IO.File]::WriteAllText((Join-Path $gameRoot '.atg-chinese-patch.json'), '{}', [Text.UTF8Encoding]::new($false))
    $rejected = $false
    try {
        & (Join-Path $projectRoot 'tools\Initialize-AtGSource.ps1') -GamePath $gameRoot -SourceRoot $sourceRoot -Refresh
    }
    catch {
        $rejected = $_.Exception.Message -match 'active Chinese patch manifest'
    }
    Assert-AtGSourceCapture $rejected 'Source capture must reject an active patch manifest.'
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}

Write-Host 'Steam source capture test passed.'
