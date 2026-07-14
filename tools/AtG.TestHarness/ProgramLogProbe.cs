namespace AtG.TestHarness;

public interface IProgramLogProbe
{
    long Bookmark();
    Task<bool> WaitForMarkerAfterAsync(
        long bookmark,
        string marker,
        TimeSpan timeout,
        CancellationToken cancellationToken);
}

public sealed class FileProgramLogProbe : IProgramLogProbe
{
    private readonly string _path;
    private readonly TimeSpan _pollInterval;

    public FileProgramLogProbe(string path, TimeSpan? pollInterval = null)
    {
        _path = Path.GetFullPath(path);
        _pollInterval = pollInterval ?? TimeSpan.FromMilliseconds(100);
    }

    public long Bookmark()
    {
        try
        {
            return File.Exists(_path) ? new FileInfo(_path).Length : 0;
        }
        catch (IOException)
        {
            return 0;
        }
    }

    public async Task<bool> WaitForMarkerAfterAsync(
        long bookmark,
        string marker,
        TimeSpan timeout,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(marker))
            throw new ArgumentException("A program-log marker is required.", nameof(marker));

        var deadline = DateTime.UtcNow + timeout;
        while (DateTime.UtcNow < deadline)
        {
            cancellationToken.ThrowIfCancellationRequested();
            try
            {
                if (File.Exists(_path))
                {
                    using var stream = new FileStream(
                        _path, FileMode.Open, FileAccess.Read,
                        FileShare.ReadWrite | FileShare.Delete);
                    stream.Seek(Math.Min(Math.Max(bookmark, 0), stream.Length), SeekOrigin.Begin);
                    using var reader = new StreamReader(stream);
                    if ((await reader.ReadToEndAsync()).Contains(marker, StringComparison.Ordinal))
                        return true;
                }
            }
            catch (IOException)
            {
                // The game may rotate or replace the log while loading a save.
            }
            await Task.Delay(_pollInterval, cancellationToken);
        }
        return false;
    }
}
