function Get-AtGFileContentHash {
    param(
        [string[]]$Paths,
        [string]$Version = "v1"
    )

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $versionBytes = [System.Text.Encoding]::UTF8.GetBytes($Version)
        $sha.TransformBlock($versionBytes, 0, $versionBytes.Length, $null, 0) | Out-Null
        foreach ($path in @($Paths | Where-Object { $_ } | Sort-Object -Unique)) {
            $resolved = [System.IO.Path]::GetFullPath($path)
            $pathBytes = [System.Text.Encoding]::UTF8.GetBytes($resolved)
            $sha.TransformBlock($pathBytes, 0, $pathBytes.Length, $null, 0) | Out-Null
            if (Test-Path -LiteralPath $resolved -PathType Leaf) {
                $contentBytes = [System.IO.File]::ReadAllBytes($resolved)
                $sha.TransformBlock($contentBytes, 0, $contentBytes.Length, $null, 0) | Out-Null
            }
            else {
                $missing = [System.Text.Encoding]::ASCII.GetBytes("<missing>")
                $sha.TransformBlock($missing, 0, $missing.Length, $null, 0) | Out-Null
            }
        }
        $sha.TransformFinalBlock([byte[]]::new(0), 0, 0) | Out-Null
        return ([BitConverter]::ToString($sha.Hash)).Replace("-", "").ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Invoke-AtGCachedValidation {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string[]]$InputPaths,
        [Parameter(Mandatory = $true)][string]$StampPath,
        [Parameter(Mandatory = $true)][scriptblock]$ScriptBlock,
        [string]$Version = "v1"
    )

    $inputHash = Get-AtGFileContentHash -Paths $InputPaths -Version $Version
    $storedHash = if (Test-Path -LiteralPath $StampPath -PathType Leaf) {
        (Get-Content -LiteralPath $StampPath -Raw).Trim()
    }
    else { "" }
    if ($storedHash -eq $inputHash) {
        Write-Host "Skipping $Name; validation cache hit."
        return $true
    }

    $null = & $ScriptBlock
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $StampPath) | Out-Null
    Set-Content -LiteralPath $StampPath -Value $inputHash -Encoding ASCII
    return $false
}

function Invoke-AtGCachedStage {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string[]]$InputPaths,
        [Parameter(Mandatory = $true)][string[]]$OutputPaths,
        [Parameter(Mandatory = $true)][string]$StampPath,
        [Parameter(Mandatory = $true)][scriptblock]$ScriptBlock,
        [string]$Version = "v1"
    )

    $inputHash = Get-AtGFileContentHash -Paths $InputPaths -Version $Version
    $cached = $null
    if (Test-Path -LiteralPath $StampPath -PathType Leaf) {
        try { $cached = Get-Content -LiteralPath $StampPath -Raw -Encoding UTF8 | ConvertFrom-Json }
        catch { $cached = $null }
    }
    $cacheHit = $null -ne $cached -and [string]$cached.InputHash -eq $inputHash
    if ($cacheHit) {
        $cachedOutputs = @($cached.Outputs)
        foreach ($outputPath in $OutputPaths) {
            $resolvedOutput = [System.IO.Path]::GetFullPath($outputPath)
            $record = $cachedOutputs | Where-Object {
                [string]$_.Path -eq $resolvedOutput
            } | Select-Object -First 1
            if ($null -eq $record -or !(Test-Path -LiteralPath $resolvedOutput -PathType Leaf)) {
                $cacheHit = $false
                break
            }
            $actualHash = Get-AtGFileContentHash -Paths @($resolvedOutput) -Version "output-v1"
            if ($actualHash -ne [string]$record.Hash) {
                $cacheHit = $false
                break
            }
        }
    }
    if ($cacheHit) {
        Write-Host "Skipping $Name; verified build cache hit."
        return $true
    }

    $null = & $ScriptBlock
    $outputRecords = foreach ($outputPath in $OutputPaths) {
        $resolvedOutput = [System.IO.Path]::GetFullPath($outputPath)
        if (!(Test-Path -LiteralPath $resolvedOutput -PathType Leaf)) {
            throw "Cached stage '$Name' did not produce expected output: $resolvedOutput"
        }
        [ordered]@{
            Path = $resolvedOutput
            Hash = Get-AtGFileContentHash -Paths @($resolvedOutput) -Version "output-v1"
        }
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $StampPath) | Out-Null
    [ordered]@{
        Version = $Version
        InputHash = $inputHash
        Outputs = @($outputRecords)
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $StampPath -Encoding UTF8
    return $false
}
