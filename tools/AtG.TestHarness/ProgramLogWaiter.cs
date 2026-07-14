namespace AtG.TestHarness;

public static class ProgramLogWaiter
{
    public static async Task<bool> WaitForMarkerAsync(
        string logPath,
        string marker,
        TimeSpan timeout,
        TimeSpan pollInterval,
        CancellationToken cancellationToken,
        DateTime? notBeforeUtc = null)
    {
        var deadline = DateTime.UtcNow + timeout;
        while (DateTime.UtcNow < deadline)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (File.Exists(logPath) &&
                (!notBeforeUtc.HasValue || File.GetLastWriteTimeUtc(logPath) >= notBeforeUtc.Value))
            {
                try
                {
                    using var stream = new FileStream(
                        logPath, FileMode.Open, FileAccess.Read,
                        FileShare.ReadWrite | FileShare.Delete);
                    using var reader = new StreamReader(stream);
                    if ((await reader.ReadToEndAsync()).Contains(marker, StringComparison.Ordinal))
                        return true;
                }
                catch (IOException)
                {
                    // The game may rotate or replace the log between the existence check and open.
                }
            }
            await Task.Delay(pollInterval, cancellationToken);
        }
        return false;
    }
}
