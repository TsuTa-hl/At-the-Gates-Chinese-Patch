$ErrorActionPreference = "Stop"

function New-AtGTimingSummary {
    [pscustomobject]@{
        StartedAt = [DateTime]::UtcNow
        Stages = @()
    }
}

function Measure-AtGStage {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Summary,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        & $ScriptBlock
    }
    finally {
        $stopwatch.Stop()
        $Summary.Stages += [pscustomobject]@{
            Name = $Name
            DurationMs = [int64]$stopwatch.ElapsedMilliseconds
            Duration = $stopwatch.Elapsed
        }
    }
}

function Get-AtGTimingReport {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Summary
    )

    $totalMs = 0L
    foreach ($stage in @($Summary.Stages)) {
        $totalMs += [int64]$stage.DurationMs
    }

    foreach ($stage in @($Summary.Stages)) {
        $percent = if ($totalMs -gt 0) {
            [Math]::Round(([double]$stage.DurationMs * 100.0 / [double]$totalMs), 1)
        }
        else {
            0
        }

        [pscustomobject]@{
            Stage = $stage.Name
            DurationMs = [int64]$stage.DurationMs
            Duration = $stage.Duration
            Percent = $percent
        }
    }
}
