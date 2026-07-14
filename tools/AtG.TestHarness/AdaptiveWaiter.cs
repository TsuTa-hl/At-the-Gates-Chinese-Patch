namespace AtG.TestHarness;

public interface IWaitClock
{
    long ElapsedMilliseconds { get; }
    Task DelayAsync(int milliseconds, CancellationToken cancellationToken);
}

public sealed class StopwatchWaitClock : IWaitClock
{
    private readonly System.Diagnostics.Stopwatch _stopwatch = System.Diagnostics.Stopwatch.StartNew();
    public long ElapsedMilliseconds => _stopwatch.ElapsedMilliseconds;
    public Task DelayAsync(int milliseconds, CancellationToken cancellationToken) =>
        Task.Delay(milliseconds, cancellationToken);
}

public sealed record StableWaitResult(
    string Fingerprint,
    int PollCount,
    long ElapsedMilliseconds,
    bool TimedOut,
    bool ChangedFromBaseline);

public static class AdaptiveWaiter
{
    public static async Task<StableWaitResult> WaitForStableAsync(
        Func<CancellationToken, Task<string>> readFingerprint,
        int maximumWaitMs = 3000,
        int pollIntervalMs = 100,
        int requiredStableFrames = 2,
        string? baselineFingerprint = null,
        bool requireChangeFromBaseline = false,
        IWaitClock? clock = null,
        CancellationToken cancellationToken = default)
    {
        if (maximumWaitMs <= 0 || pollIntervalMs <= 0 || requiredStableFrames < 2)
            throw new ArgumentOutOfRangeException(nameof(maximumWaitMs));

        clock ??= new StopwatchWaitClock();
        string? previous = null;
        var stableFrames = 0;
        var polls = 0;
        var changedFromBaseline = !requireChangeFromBaseline || baselineFingerprint is null;
        while (clock.ElapsedMilliseconds <= maximumWaitMs)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var current = await readFingerprint(cancellationToken);
            polls++;
            if (!changedFromBaseline)
            {
                if (StringComparer.Ordinal.Equals(current, baselineFingerprint))
                {
                    previous = current;
                    stableFrames = 0;
                    await clock.DelayAsync(pollIntervalMs, cancellationToken);
                    continue;
                }
                changedFromBaseline = true;
                previous = null;
            }
            stableFrames = StringComparer.Ordinal.Equals(previous, current) ? stableFrames + 1 : 1;
            previous = current;
            if (stableFrames >= requiredStableFrames)
                return new StableWaitResult(
                    current, polls, clock.ElapsedMilliseconds, false, changedFromBaseline);
            await clock.DelayAsync(pollIntervalMs, cancellationToken);
        }

        return new StableWaitResult(
            previous ?? string.Empty, polls, clock.ElapsedMilliseconds, true, changedFromBaseline);
    }
}
