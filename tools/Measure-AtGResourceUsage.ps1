[CmdletBinding()]
param(
    [int]$DurationSeconds = 60,
    [int]$IntervalMilliseconds = 1000,
    [string]$OutputDirectory,
    [switch]$Once
)

$ErrorActionPreference = "Stop"

if ($DurationSeconds -lt 0) { throw "DurationSeconds cannot be negative." }
if ($IntervalMilliseconds -lt 100) { throw "IntervalMilliseconds must be at least 100." }
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $PSScriptRoot ("..\\.tmp\\resource-monitor\\" + (Get-Date -Format "yyyyMMdd-HHmmss"))
}

if (-not ("AtGResourceNative" -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class AtGResourceNative
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    public struct MEMORYSTATUSEX
    {
        public uint dwLength;
        public uint dwMemoryLoad;
        public ulong ullTotalPhys;
        public ulong ullAvailPhys;
        public ulong ullTotalPageFile;
        public ulong ullAvailPageFile;
        public ulong ullTotalVirtual;
        public ulong ullAvailVirtual;
        public ulong ullAvailExtendedVirtual;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool GlobalMemoryStatusEx(ref MEMORYSTATUSEX status);
}
'@
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$samplesPath = Join-Path $OutputDirectory "samples.jsonl"
$summaryPath = Join-Path $OutputDirectory "summary.json"
$readmePath = Join-Path $OutputDirectory "README.txt"

"Resource monitor output" | Set-Content -LiteralPath $readmePath -Encoding UTF8
@(
    "- Memory columns report both resident working set and private committed bytes.",
    "- CodexDesktop groups codex.exe and ChatGPT.exe. It does not infer ownership of unrelated helper processes.",
    "- Network bytes are operating-system interface totals. Windows PowerShell 5.1 cannot attribute them to one process without ETW/admin tooling.",
    "- This monitor writes local JSON evidence only; it does not transmit telemetry."
) | Add-Content -LiteralPath $readmePath -Encoding UTF8

function Get-SystemMemory {
    $status = New-Object AtGResourceNative+MEMORYSTATUSEX
    $status.dwLength = [Runtime.InteropServices.Marshal]::SizeOf([type]"AtGResourceNative+MEMORYSTATUSEX")
    if (-not [AtGResourceNative]::GlobalMemoryStatusEx([ref]$status)) {
        throw "GlobalMemoryStatusEx failed."
    }

    [pscustomobject]@{
        MemoryLoadPercent = [int]$status.dwMemoryLoad
        TotalPhysicalBytes = [Int64]$status.ullTotalPhys
        AvailablePhysicalBytes = [Int64]$status.ullAvailPhys
        TotalPageFileBytes = [Int64]$status.ullTotalPageFile
        AvailablePageFileBytes = [Int64]$status.ullAvailPageFile
    }
}

function Get-ProcessGroup {
    param([string]$Name, [string[]]$ProcessNames)

    $processes = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
            $ProcessNames -contains $_.ProcessName
        })
    $workingSet = [Int64]0
    $privateBytes = [Int64]0
    $virtualBytes = [Int64]0
    $handles = [Int64]0
    $ids = @()
    foreach ($process in $processes) {
        try {
            $process.Refresh()
            $workingSet += [Int64]$process.WorkingSet64
            $privateBytes += [Int64]$process.PrivateMemorySize64
            $virtualBytes += [Int64]$process.VirtualMemorySize64
            $handles += [Int64]$process.HandleCount
            $ids += $process.Id
        }
        catch {
            # A process may exit or deny a counter while the sample is collected.
        }
    }

    [pscustomobject]@{
        Name = $Name
        ProcessNames = $ProcessNames
        ProcessIds = $ids
        ProcessCount = $ids.Count
        WorkingSetBytes = $workingSet
        PrivateBytes = $privateBytes
        VirtualBytes = $virtualBytes
        HandleCount = $handles
    }
}

function Get-NetworkTotals {
    $received = [Int64]0
    $sent = [Int64]0
    $adapters = @()
    foreach ($adapter in [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
        if ($adapter.OperationalStatus -ne [System.Net.NetworkInformation.OperationalStatus]::Up -or
            $adapter.NetworkInterfaceType -eq [System.Net.NetworkInformation.NetworkInterfaceType]::Loopback) {
            continue
        }
        try {
            $statistics = $adapter.GetIPv4Statistics()
            $received += [Int64]$statistics.BytesReceived
            $sent += [Int64]$statistics.BytesSent
            $adapters += [pscustomobject]@{
                Name = $adapter.Name
                Type = $adapter.NetworkInterfaceType.ToString()
                BytesReceived = [Int64]$statistics.BytesReceived
                BytesSent = [Int64]$statistics.BytesSent
            }
        }
        catch {
            # Virtual and disconnected adapters can reject IPv4 counters.
        }
    }

    [pscustomobject]@{
        BytesReceived = $received
        BytesSent = $sent
        Adapters = $adapters
    }
}

function Write-Sample {
    $memory = Get-SystemMemory
    $network = Get-NetworkTotals
    $sample = [pscustomobject]@{
        TimestampUtc = [DateTime]::UtcNow.ToString("o")
        SystemMemory = $memory
        ProcessGroups = @(
            (Get-ProcessGroup -Name "CodexDesktop" -ProcessNames @("codex", "ChatGPT")),
            (Get-ProcessGroup -Name "AtTheGates" -ProcessNames @("At The Gates")),
            (Get-ProcessGroup -Name "BuildTools" -ProcessNames @("dotnet", "powershell"))
        )
        Network = $network
    }
    ($sample | ConvertTo-Json -Depth 8 -Compress) | Add-Content -LiteralPath $samplesPath -Encoding UTF8
    return $sample
}

$startedAt = [DateTime]::UtcNow
$samples = @()
do {
    $samples += Write-Sample
    if ($Once) { break }
    if (([DateTime]::UtcNow - $startedAt).TotalSeconds -ge $DurationSeconds) { break }
    Start-Sleep -Milliseconds $IntervalMilliseconds
} while ($true)

$first = $samples[0]
$last = $samples[$samples.Count - 1]
$groupSummary = @()
foreach ($groupName in @("CodexDesktop", "AtTheGates", "BuildTools")) {
    $series = @($samples | ForEach-Object {
            $_.ProcessGroups | Where-Object { $_.Name -eq $groupName }
        })
    $groupSummary += [pscustomobject]@{
        Name = $groupName
        PeakWorkingSetBytes = [Int64](($series | Measure-Object -Property WorkingSetBytes -Maximum).Maximum)
        PeakPrivateBytes = [Int64](($series | Measure-Object -Property PrivateBytes -Maximum).Maximum)
        PeakVirtualBytes = [Int64](($series | Measure-Object -Property VirtualBytes -Maximum).Maximum)
        PeakProcessCount = [Int32](($series | Measure-Object -Property ProcessCount -Maximum).Maximum)
    }
}

$summary = [pscustomobject]@{
    StartedAtUtc = $startedAt.ToString("o")
    FinishedAtUtc = [DateTime]::UtcNow.ToString("o")
    DurationSeconds = [math]::Round(([DateTime]::UtcNow - $startedAt).TotalSeconds, 3)
    SampleCount = $samples.Count
    OutputDirectory = (Resolve-Path -LiteralPath $OutputDirectory).Path
    ProcessGroups = $groupSummary
    SystemMemory = [pscustomobject]@{
        TotalPhysicalBytes = $first.SystemMemory.TotalPhysicalBytes
        MinimumAvailablePhysicalBytes = [Int64](($samples | ForEach-Object { $_.SystemMemory.AvailablePhysicalBytes } | Measure-Object -Minimum).Minimum)
        PeakMemoryLoadPercent = [Int32](($samples | ForEach-Object { $_.SystemMemory.MemoryLoadPercent } | Measure-Object -Maximum).Maximum)
    }
    Network = [pscustomobject]@{
        ReceivedBytes = [Int64]($last.Network.BytesReceived - $first.Network.BytesReceived)
        SentBytes = [Int64]($last.Network.BytesSent - $first.Network.BytesSent)
        TotalBytes = [Int64](($last.Network.BytesReceived - $first.Network.BytesReceived) + ($last.Network.BytesSent - $first.Network.BytesSent))
        Attribution = "System network-interface total; not per-process attribution."
    }
}

$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
$summary | ConvertTo-Json -Depth 8
