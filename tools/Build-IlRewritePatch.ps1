param(
    [Parameter(Mandatory = $true)]
    [string]$SourceDll,

    [Parameter(Mandatory = $true)]
    [string]$OutputDll,

    [Parameter(Mandatory = $true)]
    [string]$MapJson,

    [string]$DotNetPath = "$PSScriptRoot\..\.tools\dotnet\dotnet.exe",
    [string]$NuGetPackages = "$PSScriptRoot\..\.tools\nuget-cache",
    [string]$ProjectPath = "$PSScriptRoot\AtG.IlRewrite\AtG.IlRewrite.csproj"
)

$ErrorActionPreference = "Stop"

function ConvertTo-AtGIlRewriteEntries {
    param([object]$Json)

    $entries = @()
    foreach ($item in @($Json)) {
        if ($null -eq $item) {
            continue
        }

        if ($null -ne $item.PSObject.Properties["Original"]) {
            $entries += $item
            continue
        }

        foreach ($property in $item.PSObject.Properties) {
            $entries += [pscustomobject]@{
                Original = [string]$property.Name
                Translation = [string]$property.Value
            }
        }
    }

    return $entries
}

function Invoke-AtGIlRewriteWithRetry {
    param(
        [string]$DotNet,
        [string]$ToolDll,
        [string]$Source,
        [string]$Output,
        [string]$Map,
        [int]$MaxAttempts = 5
    )

    $lastOutput = ""
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        $captured = New-Object System.Collections.Generic.List[string]
        $oldErrorActionPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = "Continue"
            & $DotNet $ToolDll `
                --source $Source `
                --output $Output `
                --map $Map 2>&1 | ForEach-Object {
                    $line = [string]$_
                    $captured.Add($line)
                    Write-Host $line
                }
        }
        finally {
            $ErrorActionPreference = $oldErrorActionPreference
        }

        $lastOutput = ($captured.ToArray() -join "`n")
        if ($LASTEXITCODE -eq 0) {
            return
        }

        $localizedMappedSection = -join ([char[]](0x7528, 0x6237, 0x6620, 0x5c04, 0x533a, 0x57df))
        $isMappedFileFailure = $lastOutput -match "user-mapped section" -or
            $lastOutput.Contains($localizedMappedSection)
        if ($isMappedFileFailure -and $attempt -lt $MaxAttempts) {
            $delayMs = [Math]::Min(2000, 250 * [Math]::Pow(2, $attempt - 1))
            Write-Warning ("IL rewrite output file is temporarily mapped; retrying attempt {0}/{1} after {2} ms." -f ($attempt + 1), $MaxAttempts, $delayMs)
            [GC]::Collect()
            [GC]::WaitForPendingFinalizers()
            Start-Sleep -Milliseconds $delayMs
            continue
        }

        throw "IL rewrite failed for $Source"
    }

    throw "IL rewrite failed for $Source"
}

if (!(Test-Path -LiteralPath $SourceDll -PathType Leaf)) {
    throw "Source DLL not found: $SourceDll"
}
if (!(Test-Path -LiteralPath $MapJson -PathType Leaf)) {
    throw "IL rewrite map not found: $MapJson"
}

$json = Get-Content -LiteralPath $MapJson -Raw -Encoding UTF8 | ConvertFrom-Json
$entries = @(ConvertTo-AtGIlRewriteEntries -Json $json)
if ($entries.Count -eq 0) {
    $outDir = Split-Path -Parent $OutputDll
    if ($outDir) {
        New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    }
    Copy-Item -LiteralPath $SourceDll -Destination $OutputDll -Force
    Write-Host "No IL rewrite entries found. Copied source DLL unchanged: $OutputDll"
    return
}

$resolvedDotNet = [System.IO.Path]::GetFullPath($DotNetPath)
if (!(Test-Path -LiteralPath $resolvedDotNet -PathType Leaf)) {
    $installCommand = "powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Install-DotNetToolchain.ps1"
    throw "Repo-local dotnet.exe not found: $resolvedDotNet. Install it with: $installCommand"
}
if (!(Test-Path -LiteralPath $ProjectPath -PathType Leaf)) {
    throw "IL rewrite project not found: $ProjectPath"
}

$env:NUGET_PACKAGES = [System.IO.Path]::GetFullPath($NuGetPackages)
New-Item -ItemType Directory -Force -Path $env:NUGET_PACKAGES | Out-Null

$resolvedSource = (Resolve-Path -LiteralPath $SourceDll).Path
$resolvedMap = (Resolve-Path -LiteralPath $MapJson).Path
$resolvedProject = (Resolve-Path -LiteralPath $ProjectPath).Path
$resolvedOutput = [System.IO.Path]::GetFullPath($OutputDll)
$projectDir = Split-Path -Parent $resolvedProject
$toolOutputDir = Join-Path $projectDir "bin\Debug\net8.0"
$toolDll = Join-Path $toolOutputDir "AtG.IlRewrite.dll"
$staleAppHost = Join-Path $toolOutputDir "AtG.IlRewrite.exe"
Remove-Item -LiteralPath $staleAppHost -Force -ErrorAction SilentlyContinue

& $resolvedDotNet restore $resolvedProject --locked-mode -p:NuGetAudit=false
if ($LASTEXITCODE -ne 0) {
    throw "dotnet restore failed for $resolvedProject"
}

& $resolvedDotNet build $resolvedProject `
    --no-restore `
    -p:UseAppHost=false `
    -p:NuGetAudit=false
if ($LASTEXITCODE -ne 0) {
    throw "dotnet build failed for $resolvedProject"
}
if (!(Test-Path -LiteralPath $toolDll -PathType Leaf)) {
    throw "IL rewrite tool DLL was not built: $toolDll"
}
if (Test-Path -LiteralPath $staleAppHost -PathType Leaf) {
    throw "IL rewrite tool unexpectedly produced an apphost executable: $staleAppHost"
}

Invoke-AtGIlRewriteWithRetry `
    -DotNet $resolvedDotNet `
    -ToolDll $toolDll `
    -Source $resolvedSource `
    -Output $resolvedOutput `
    -Map $resolvedMap
