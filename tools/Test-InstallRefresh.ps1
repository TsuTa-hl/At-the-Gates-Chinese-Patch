param(
    [string]$TempRoot = "$PSScriptRoot\..\.tmp\install-refresh-tests"
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

function New-TextFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    $directory = Split-Path -Parent $Path
    if ($directory) {
        New-Item -ItemType Directory -Force -Path $directory | Out-Null
    }
    Set-Content -LiteralPath $Path -Encoding UTF8 -Value $Value
}

function Get-ResolvedLiteralPath {
    param([string]$Path)

    return (Resolve-Path -LiteralPath $Path).Path
}

if (Test-Path -LiteralPath $TempRoot) {
    Remove-Item -LiteralPath $TempRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $TempRoot | Out-Null

$repoRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$gameRoot = Join-Path $TempRoot "FakeGame"
$backupRoot = Join-Path $gameRoot "_ChinesePatchBackup\20000101-000000"
$manifestPath = Join-Path $gameRoot ".atg-chinese-patch.json"
$gameText = Join-Path $gameRoot "Content\Text\English.xml"
$backupText = Join-Path $backupRoot "Content\Text\English.xml"
$staleFile = Join-Path $gameRoot "Content\Obsolete\OldPatchOnly.txt"

New-TextFile -Path (Join-Path $gameRoot "At The Gates.exe") -Value "fake exe"
New-TextFile -Path $gameText -Value "old patched text"
New-TextFile -Path $backupText -Value "original text"
New-TextFile -Path $staleFile -Value "stale patch file"

$oldManifest = [pscustomobject]@{
    Name       = "At the Gates Chinese Patch"
    Installed  = "2000-01-01T00:00:00"
    GamePath   = $gameRoot
    BackupRoot = $backupRoot
    Files      = @(
        [pscustomobject]@{
            RelativePath = "Content\Text\English.xml"
            HadOriginal  = $true
        },
        [pscustomobject]@{
            RelativePath = "Content\Obsolete\OldPatchOnly.txt"
            HadOriginal  = $false
        }
    )
}
$oldManifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

& (Join-Path $repoRoot "Install-ChinesePatch.ps1") -GamePath $gameRoot -PreserveFonts

Assert-AtG (!(Test-Path -LiteralPath $staleFile)) "Install did not uninstall the stale manifest-managed file first."
Assert-AtG (Test-Path -LiteralPath $manifestPath) "Install did not create a new manifest."
Assert-AtG (Test-Path -LiteralPath $gameText) "Install did not copy patch text."

$firstManifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-AtG ((Get-ResolvedLiteralPath ([string]$firstManifest.BackupRoot)) -eq (Get-ResolvedLiteralPath $backupRoot)) "Install did not reuse the existing original backup."
Assert-AtG (@($firstManifest.Files | Where-Object { $_.RelativePath -eq "Content\Obsolete\OldPatchOnly.txt" }).Count -eq 0) "New manifest kept a stale old-patch-only file."

& (Join-Path $repoRoot "Install-ChinesePatch.ps1") -GamePath $gameRoot -PreserveFonts

$secondManifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-AtG ((Get-ResolvedLiteralPath ([string]$secondManifest.BackupRoot)) -eq (Get-ResolvedLiteralPath $backupRoot)) "Repeated install did not preserve the original backup root."
Assert-AtG (!(Test-Path -LiteralPath $staleFile)) "Repeated install restored the stale manifest-managed file."
Assert-AtG (@($secondManifest.Files).Count -gt 0) "Repeated install produced an empty manifest."

Write-Host "Install refresh regression checks passed."
