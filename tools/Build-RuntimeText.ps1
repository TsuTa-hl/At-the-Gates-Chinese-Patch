param(
    [string]$RepoRoot = "$PSScriptRoot\..",
    [string]$PatchRoot = "$PSScriptRoot\..\patch",
    [string]$DotNetPath = "$PSScriptRoot\..\.tools\dotnet\dotnet.exe",
    [string]$NuGetPackages = "$PSScriptRoot\..\.tools\nuget-cache"
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\AtGFileOps.ps1"
$root = [System.IO.Path]::GetFullPath($RepoRoot)
$dotnet = [System.IO.Path]::GetFullPath($DotNetPath)
$project = Join-Path $root "tools\AtG.RuntimeText\AtG.RuntimeText.csproj"
$runtimeDll = Join-Path $root "tools\AtG.RuntimeText\bin\Release\net40\AtG.RuntimeText.dll"
$lockFile = Join-Path $root "tools\AtG.RuntimeText\packages.lock.json"
if (!(Test-Path -LiteralPath $dotnet -PathType Leaf)) { throw "Repo-local dotnet.exe not found: $dotnet" }

$env:NUGET_PACKAGES = [System.IO.Path]::GetFullPath($NuGetPackages)
$env:DOTNET_CLI_HOME = Join-Path $root ".tools\dotnet-home"
New-Item -ItemType Directory -Force -Path $env:NUGET_PACKAGES, $env:DOTNET_CLI_HOME | Out-Null

$restoreStamp = Join-Path $root ".cache\toolchain\runtime-text-restore.sha256"
$lockHash = if (Test-Path -LiteralPath $lockFile) { (Get-FileHash -LiteralPath $lockFile -Algorithm SHA256).Hash } else { "missing" }
$storedHash = if (Test-Path -LiteralPath $restoreStamp) { (Get-Content -LiteralPath $restoreStamp -Raw).Trim() } else { "" }
if ($storedHash -ne $lockHash) {
    & $dotnet restore $project --locked-mode -p:NuGetAudit=false
    if ($LASTEXITCODE -ne 0) { throw "AtG.RuntimeText restore failed with exit code $LASTEXITCODE." }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $restoreStamp) | Out-Null
    Set-Content -LiteralPath $restoreStamp -Value $lockHash -Encoding ASCII
}

$sourceFiles = Get-ChildItem -LiteralPath (Split-Path -Parent $project) -File -Include *.cs,*.csproj,packages.lock.json
$needsBuild = !(Test-Path -LiteralPath $runtimeDll -PathType Leaf)
if (!$needsBuild) {
    $builtAt = (Get-Item -LiteralPath $runtimeDll).LastWriteTimeUtc
    $needsBuild = @($sourceFiles | Where-Object { $_.LastWriteTimeUtc -gt $builtAt }).Count -gt 0
}
if ($needsBuild) {
    & $dotnet build $project -c Release --no-restore -p:UseAppHost=false -p:NuGetAudit=false
    if ($LASTEXITCODE -ne 0) { throw "AtG.RuntimeText build failed with exit code $LASTEXITCODE." }
}

& "$PSScriptRoot\Invoke-AtGPatchCli.ps1" -Command runtime-rewrite -RepoRoot $root
& "$PSScriptRoot\Invoke-AtGPatchCli.ps1" -Command runtime-map -RepoRoot $root

$resolvedPatch = [System.IO.Path]::GetFullPath($PatchRoot)
Copy-AtGFileIfChanged -Source $runtimeDll -Destination (Join-Path $resolvedPatch "AtG.RuntimeText.dll") | Out-Null
$fontDestination = Join-Path $resolvedPatch "Content\Fonts"
New-Item -ItemType Directory -Force -Path $fontDestination | Out-Null
Copy-AtGFileIfChanged -Source (Join-Path $root "assets\fonts\NotoSansSC-Regular.otf") -Destination (Join-Path $fontDestination "NotoSansSC-Regular.otf") | Out-Null
Copy-AtGFileIfChanged -Source (Join-Path $root "assets\fonts\NotoSansSC-Bold.otf") -Destination (Join-Path $fontDestination "NotoSansSC-Bold.otf") | Out-Null
Copy-AtGFileIfChanged -Source (Join-Path $root "assets\fonts\OFL.txt") -Destination (Join-Path $fontDestination "OFL.txt") | Out-Null
