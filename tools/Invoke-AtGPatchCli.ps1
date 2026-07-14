param(
    [ValidateSet("rewrite", "runtime-rewrite", "runtime-map", "load-lifecycle", "catalog")]
    [string]$Command = "rewrite",
    [ValidateSet("MergedFonts", "DynamicCjk")]
    [string]$RendererMode = "DynamicCjk",
    [string]$RepoRoot = "$PSScriptRoot\..",
    [string]$SummaryPath = "$PSScriptRoot\..\.cache\managed-rewrite-summary.json",
    [string]$DotNetPath = "$PSScriptRoot\..\.tools\dotnet\dotnet.exe",
    [string]$NuGetPackages = "$PSScriptRoot\..\.tools\nuget-cache",
    [string[]]$CommandArguments = @(),
    [ValidateSet("stats", "search")]
    [string]$CatalogAction = "stats",
    [string]$CatalogDatabasePath = "$PSScriptRoot\..\.cache\atg-catalog.sqlite",
    [string]$CatalogText = "",
    [string]$CatalogSource = "",
    [ValidateRange(1, 500)]
    [int]$CatalogLimit = 25
)

$ErrorActionPreference = "Stop"

function Get-AtGContentHash {
    param([string[]]$Paths)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        foreach ($path in $Paths | Sort-Object) {
            if (!(Test-Path -LiteralPath $path -PathType Leaf)) {
                continue
            }
            $nameBytes = [System.Text.Encoding]::UTF8.GetBytes([System.IO.Path]::GetFullPath($path))
            $sha.TransformBlock($nameBytes, 0, $nameBytes.Length, $null, 0) | Out-Null
            $contentBytes = [System.IO.File]::ReadAllBytes($path)
            $sha.TransformBlock($contentBytes, 0, $contentBytes.Length, $null, 0) | Out-Null
        }
        $sha.TransformFinalBlock([byte[]]::new(0), 0, 0) | Out-Null
        return ([System.BitConverter]::ToString($sha.Hash)).Replace("-", "").ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

$resolvedRoot = [System.IO.Path]::GetFullPath($RepoRoot)
$resolvedDotNet = [System.IO.Path]::GetFullPath($DotNetPath)
if (!(Test-Path -LiteralPath $resolvedDotNet -PathType Leaf)) {
    throw "Repo-local dotnet.exe not found: $resolvedDotNet"
}

$project = Join-Path $resolvedRoot "tools\AtG.Patch.Cli\AtG.Patch.Cli.csproj"
$toolDll = Join-Path $resolvedRoot "tools\AtG.Patch.Cli\bin\Release\net8.0\AtG.Patch.Cli.dll"
$toolInputs = @(
    Get-ChildItem -LiteralPath (Join-Path $resolvedRoot "tools\AtG.Patch.Core") -File -Recurse -Include *.cs,*.csproj,packages.lock.json
    Get-ChildItem -LiteralPath (Join-Path $resolvedRoot "tools\AtG.ManagedRewrite") -File -Recurse -Include *.cs,*.csproj,packages.lock.json
    Get-ChildItem -LiteralPath (Join-Path $resolvedRoot "tools\AtG.Catalog") -File -Recurse -Include *.cs,*.csproj,packages.lock.json
    Get-ChildItem -LiteralPath (Join-Path $resolvedRoot "tools\AtG.Patch.Cli") -File -Recurse -Include *.cs,*.csproj,packages.lock.json
) | Where-Object { $_.FullName -notmatch "[\\/](bin|obj)[\\/]" }

$env:NUGET_PACKAGES = [System.IO.Path]::GetFullPath($NuGetPackages)
$env:DOTNET_CLI_HOME = Join-Path $resolvedRoot ".tools\dotnet-home"
New-Item -ItemType Directory -Force -Path $env:NUGET_PACKAGES, $env:DOTNET_CLI_HOME | Out-Null

$restoreInputs = @($toolInputs | Where-Object { $_.Name -match "\.csproj$|packages\.lock\.json$" } | ForEach-Object FullName)
$restoreHash = Get-AtGContentHash -Paths $restoreInputs
$restoreStamp = Join-Path $resolvedRoot ".cache\toolchain\cli-restore.sha256"
$storedRestoreHash = if (Test-Path -LiteralPath $restoreStamp) { (Get-Content -LiteralPath $restoreStamp -Raw).Trim() } else { "" }
$projectAssetsPath = Join-Path $resolvedRoot "tools\AtG.Patch.Cli\obj\project.assets.json"
$assetsUseRepoCache = $false
if (Test-Path -LiteralPath $projectAssetsPath -PathType Leaf) {
    try {
        $projectAssets = Get-Content -LiteralPath $projectAssetsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $resolvedPackageRoot = [System.IO.Path]::GetFullPath($env:NUGET_PACKAGES).TrimEnd('\')
        $assetPackageRoots = @($projectAssets.packageFolders.PSObject.Properties.Name | ForEach-Object {
            [System.IO.Path]::GetFullPath($_).TrimEnd('\')
        })
        $assetsUseRepoCache = $assetPackageRoots -contains $resolvedPackageRoot
    }
    catch {
        $assetsUseRepoCache = $false
    }
}
if ($storedRestoreHash -ne $restoreHash -or !$assetsUseRepoCache) {
    & $resolvedDotNet restore $project --ignore-failed-sources -p:NuGetAudit=false
    if ($LASTEXITCODE -ne 0) { throw "AtG.Patch.Cli restore failed with exit code $LASTEXITCODE." }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $restoreStamp) | Out-Null
    Set-Content -LiteralPath $restoreStamp -Value $restoreHash -Encoding ASCII
}

$buildInputs = @($toolInputs | ForEach-Object FullName)
$buildHash = Get-AtGContentHash -Paths $buildInputs
$buildStamp = Join-Path $resolvedRoot ".cache\toolchain\cli-build.sha256"
$storedBuildHash = if (Test-Path -LiteralPath $buildStamp) {
    (Get-Content -LiteralPath $buildStamp -Raw).Trim()
} else { "" }
$toolOutputDirectory = Split-Path -Parent $toolDll
$expectedToolOutputs = @(
    $toolDll,
    (Join-Path $toolOutputDirectory "AtG.Patch.Core.dll"),
    (Join-Path $toolOutputDirectory "AtG.ManagedRewrite.dll"),
    (Join-Path $toolOutputDirectory "AtG.Catalog.dll")
)
$needsBuild = $storedBuildHash -ne $buildHash -or
    @($expectedToolOutputs | Where-Object { !(Test-Path -LiteralPath $_ -PathType Leaf) }).Count -gt 0
if ($needsBuild) {
    & $resolvedDotNet build $project -c Release --no-restore -p:UseAppHost=false -p:NuGetAudit=false
    if ($LASTEXITCODE -ne 0) { throw "AtG.Patch.Cli build failed with exit code $LASTEXITCODE." }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $buildStamp) | Out-Null
    Set-Content -LiteralPath $buildStamp -Value $buildHash -Encoding ASCII
}

$toolArguments = if ($Command -eq "catalog") {
    $catalogArguments = @($CommandArguments)
    if ($catalogArguments.Count -eq 0) {
        $catalogArguments = @($CatalogAction, "--database", ([System.IO.Path]::GetFullPath($CatalogDatabasePath)))
        if ($CatalogAction -eq "search") {
            if ([string]::IsNullOrWhiteSpace($CatalogText)) {
                throw "-CatalogText is required when -CatalogAction is search."
            }
            $catalogArguments += @("--text", $CatalogText, "--limit", [string]$CatalogLimit)
            if (-not [string]::IsNullOrWhiteSpace($CatalogSource)) {
                $catalogArguments += @("--source", $CatalogSource)
            }
        }
    }
    @($toolDll, "catalog") + $catalogArguments
}
else {
    @(
        $toolDll,
        $Command,
        "--repo", $resolvedRoot,
        "--summary", ([System.IO.Path]::GetFullPath($SummaryPath))
    )
}
if ($Command -eq "load-lifecycle") {
    $toolArguments += @("--renderer-mode", $RendererMode)
}

& $resolvedDotNet @toolArguments
if ($LASTEXITCODE -ne 0) {
    throw "AtG.Patch.Cli $Command failed with exit code $LASTEXITCODE."
}
