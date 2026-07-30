param(
    [string]$TempRoot = "$PSScriptRoot\..\.tmp\uninstall-chinese-patch-tests"
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
$saveDirectory = Join-Path $gameRoot "Saved Games"

New-TextFile -Path (Join-Path $gameRoot "At The Gates.exe") -Value "fake exe"
New-TextFile -Path $gameText -Value "patched text"
New-TextFile -Path $backupText -Value "original text"

$chinese = [string][char]0x6E38 + [char]0x620F
$firstSave = "World $chinese.AtGSave"
$secondSave = "World " + [string][char]0x5F00 + [char]0x59CB + ".AtGSave"
$onlyChineseSave = $chinese + ".AtGSave"
$asciiCollision = "World .AtGSave"
New-TextFile -Path (Join-Path $saveDirectory $firstSave) -Value "save one"
New-TextFile -Path (Join-Path $saveDirectory $secondSave) -Value "save two"
New-TextFile -Path (Join-Path $saveDirectory $onlyChineseSave) -Value "save three"
New-TextFile -Path (Join-Path $saveDirectory $asciiCollision) -Value "existing ascii save"

$manifest = [pscustomobject]@{
    Name       = "At the Gates Chinese Patch"
    Installed  = "2000-01-01T00:00:00"
    GamePath   = $gameRoot
    BackupRoot = $backupRoot
    Files      = @(
        [pscustomobject]@{
            RelativePath = "Content\Text\English.xml"
            HadOriginal  = $true
        }
    )
}
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

& (Join-Path $repoRoot "Uninstall-ChinesePatch.ps1") -GamePath $gameRoot -NoSaveNameNotice

Assert-AtG (!(Test-Path -LiteralPath $manifestPath)) "Uninstall did not remove the manifest."
Assert-AtG ((Get-Content -LiteralPath $gameText -Raw -Encoding UTF8).Trim() -eq "original text") "Uninstall did not restore the original file."
Assert-AtG (Test-Path -LiteralPath (Join-Path $saveDirectory "World -2.AtGSave")) "The first colliding Chinese save name was not renamed with an ASCII suffix."
Assert-AtG (Test-Path -LiteralPath (Join-Path $saveDirectory "World -3.AtGSave")) "The second colliding Chinese save name was not renamed with an ASCII suffix."
Assert-AtG (Test-Path -LiteralPath (Join-Path $saveDirectory "SavedGame.AtGSave")) "A fully unsupported save name did not receive a safe fallback name."
Assert-AtG ((Get-Content -LiteralPath (Join-Path $saveDirectory $asciiCollision) -Raw -Encoding UTF8).Trim() -eq "existing ascii save") "An existing ASCII save was overwritten while resolving a renamed collision."
Assert-AtG (@(Get-ChildItem -LiteralPath $saveDirectory -File -Filter "*.AtGSave" | Where-Object { $_.Name -match "[^\u0020-\u007E]" }).Count -eq 0) "Uninstall left unsupported characters in a save file name."

$uninstallSource = Get-Content -LiteralPath (Join-Path $repoRoot "Uninstall-ChinesePatch.ps1") -Raw -Encoding UTF8
$noticeSource = Get-Content -LiteralPath (Join-Path $repoRoot "tools\AtGSaveNameCompatibility.ps1") -Raw -Encoding UTF8
Assert-AtG ($uninstallSource -match "SkipSaveNameCompatibility") "Uninstall does not expose an explicit refresh bypass."
Assert-AtG ($noticeSource -match "MessageBox\]::Show") "Uninstall does not include the post-action informational popup."

Write-Host "Uninstall Chinese patch save-name compatibility checks passed."
