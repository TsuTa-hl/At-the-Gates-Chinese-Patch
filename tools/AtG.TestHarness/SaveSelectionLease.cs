namespace AtG.TestHarness;

public sealed class SaveSelectionLease : IDisposable
{
    private readonly string _path;
    private readonly DateTime _originalLastWriteUtc;
    private bool _disposed;

    private SaveSelectionLease(string path, DateTime originalLastWriteUtc)
    {
        _path = path;
        _originalLastWriteUtc = originalLastWriteUtc;
    }

    public static SaveSelectionLease Promote(string saveDirectory, string saveName)
    {
        if (!string.Equals(Path.GetFileName(saveName), saveName, StringComparison.Ordinal))
            throw new ArgumentException("Save name must not contain a path.", nameof(saveName));
        var path = Path.Combine(Path.GetFullPath(saveDirectory), saveName);
        if (!File.Exists(path))
            throw new FileNotFoundException("Fixed save not found.", path);

        var original = File.GetLastWriteTimeUtc(path);
        var newestOther = Directory.EnumerateFiles(saveDirectory, "*.AtGSave")
            .Where(candidate => !candidate.Equals(path, StringComparison.OrdinalIgnoreCase))
            .Select(File.GetLastWriteTimeUtc)
            .DefaultIfEmpty(DateTime.MinValue)
            .Max();
        var promoted = DateTime.UtcNow;
        if (promoted <= newestOther) promoted = newestOther.AddSeconds(1);
        File.SetLastWriteTimeUtc(path, promoted);
        return new SaveSelectionLease(path, original);
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        if (File.Exists(_path)) File.SetLastWriteTimeUtc(_path, _originalLastWriteUtc);
    }
}
