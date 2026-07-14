$ErrorActionPreference = "Stop"

function Test-AtGTransientFileWriteFailure {
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    $exception = $ErrorRecord.Exception
    while ($null -ne $exception) {
        $win32Code = $exception.HResult -band 0xffff
        if ($win32Code -in @(32, 33, 1224)) {
            return $true
        }
        $exception = $exception.InnerException
    }

    $message = [string]$ErrorRecord
    return $message -match "user-mapped section|being used by another process|sharing violation|mapped.*open|映射|另一进程"
}

function Copy-AtGFileIfChanged {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Source,

        [Parameter(Mandatory = $true)]
        [string]$Destination,

        [ValidateRange(1, 30)]
        [int]$MaxAttempts = 10,

        [ValidateRange(1, 5000)]
        [int]$InitialDelayMilliseconds = 100
    )

    $resolvedSource = [System.IO.Path]::GetFullPath($Source)
    $resolvedDestination = [System.IO.Path]::GetFullPath($Destination)
    if (!(Test-Path -LiteralPath $resolvedSource -PathType Leaf)) {
        throw "Source file not found: $resolvedSource"
    }

    if (Test-Path -LiteralPath $resolvedDestination -PathType Leaf) {
        $sourceInfo = Get-Item -LiteralPath $resolvedSource
        $destinationInfo = Get-Item -LiteralPath $resolvedDestination
        if ($sourceInfo.Length -eq $destinationInfo.Length) {
            $sourceHash = (Get-FileHash -LiteralPath $resolvedSource -Algorithm SHA256).Hash
            $destinationHash = (Get-FileHash -LiteralPath $resolvedDestination -Algorithm SHA256).Hash
            if ($sourceHash -eq $destinationHash) {
                return $false
            }
        }
    }

    $destinationDirectory = Split-Path -Parent $resolvedDestination
    New-Item -ItemType Directory -Force -Path $destinationDirectory | Out-Null
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            Copy-Item -LiteralPath $resolvedSource -Destination $resolvedDestination -Force
            return $true
        }
        catch {
            if ($attempt -ge $MaxAttempts -or !(Test-AtGTransientFileWriteFailure -ErrorRecord $_)) {
                throw
            }

            $delayMilliseconds = [Math]::Min(
                800,
                $InitialDelayMilliseconds * [Math]::Pow(2, $attempt - 1))
            Write-Warning ("Destination is temporarily mapped; retrying copy attempt {0}/{1} after {2} ms: {3}" -f `
                ($attempt + 1), $MaxAttempts, [int]$delayMilliseconds, $resolvedDestination)
            [GC]::Collect()
            [GC]::WaitForPendingFinalizers()
            Start-Sleep -Milliseconds ([int]$delayMilliseconds)
        }
    }

    throw "Failed to copy file after $MaxAttempts attempts: $resolvedDestination"
}
