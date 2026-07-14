using System.Diagnostics;

namespace AtG.TestHarness;

public sealed record ProcessMemoryCounters(
    long WorkingSetBytes,
    long PrivateBytes,
    long VirtualBytes,
    long PagedBytes,
    int HandleCount);

public sealed record ProcessMemorySample(
    DateTime TimestampUtc,
    string Label,
    long WorkingSetBytes,
    long PrivateBytes,
    long VirtualBytes,
    long PagedBytes,
    int HandleCount,
    string? Error = null);

public interface IProcessMemoryProbe
{
    ProcessMemoryCounters Capture();
}

public sealed class SystemProcessMemoryProbe(Process process) : IProcessMemoryProbe
{
    public ProcessMemoryCounters Capture()
    {
        process.Refresh();
        if (process.HasExited)
            throw new InvalidOperationException("The game process has exited.");
        return new ProcessMemoryCounters(
            process.WorkingSet64,
            process.PrivateMemorySize64,
            process.VirtualMemorySize64,
            process.PagedMemorySize64,
            process.HandleCount);
    }
}
