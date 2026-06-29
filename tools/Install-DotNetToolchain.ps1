param(
    [string]$InstallDir = "$PSScriptRoot\..\.tools\dotnet",
    [string]$Channel = "8.0",
    [string]$InstallScriptPath = "$PSScriptRoot\..\.tools\dotnet-install.ps1"
)

$ErrorActionPreference = "Stop"

$resolvedInstallDir = [System.IO.Path]::GetFullPath($InstallDir)
$resolvedScriptPath = [System.IO.Path]::GetFullPath($InstallScriptPath)
$scriptDir = Split-Path -Parent $resolvedScriptPath
New-Item -ItemType Directory -Force -Path $resolvedInstallDir | Out-Null
New-Item -ItemType Directory -Force -Path $scriptDir | Out-Null

if (!(Test-Path -LiteralPath $resolvedScriptPath -PathType Leaf)) {
    Write-Host "Downloading dotnet-install.ps1..."
    Invoke-WebRequest `
        -Uri "https://dot.net/v1/dotnet-install.ps1" `
        -OutFile $resolvedScriptPath `
        -UseBasicParsing
}

& $resolvedScriptPath `
    -Channel $Channel `
    -InstallDir $resolvedInstallDir `
    -NoPath

$dotnet = Join-Path $resolvedInstallDir "dotnet.exe"
if (!(Test-Path -LiteralPath $dotnet -PathType Leaf)) {
    throw "dotnet.exe was not installed at $dotnet"
}

Write-Host "Installed repo-local .NET SDK: $dotnet"
& $dotnet --info
