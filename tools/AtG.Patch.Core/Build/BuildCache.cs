using System.Text.Json;

namespace AtG.Patch.Core.Build;

public sealed class BuildCache
{
    private readonly string _path;
    private readonly Dictionary<string, CacheEntry> _entries;
    private readonly object _gate = new();

    public BuildCache(string path)
    {
        _path = Path.GetFullPath(path);
        _entries = Load(_path);
    }

    public bool IsCurrent(string stage, string inputHash, IEnumerable<string> outputs)
    {
        var expected = outputs.Select(Path.GetFullPath).OrderBy(x => x, StringComparer.OrdinalIgnoreCase).ToArray();
        lock (_gate)
        {
            if (!_entries.TryGetValue(stage, out var entry) ||
                !StringComparer.Ordinal.Equals(entry.InputHash, inputHash))
                return false;

            return entry.Outputs.SequenceEqual(expected, StringComparer.OrdinalIgnoreCase) &&
                   expected.All(File.Exists);
        }
    }

    public void Record(string stage, string inputHash, IEnumerable<string> outputs)
    {
        var normalizedOutputs = outputs.Select(Path.GetFullPath)
            .OrderBy(x => x, StringComparer.OrdinalIgnoreCase)
            .ToArray();

        lock (_gate)
        {
            _entries[stage] = new CacheEntry
            {
                InputHash = inputHash,
                Outputs = normalizedOutputs,
                RecordedAtUtc = DateTime.UtcNow,
            };

            Directory.CreateDirectory(Path.GetDirectoryName(_path)!);
            var temporaryPath = _path + ".tmp";
            File.WriteAllText(temporaryPath, JsonSerializer.Serialize(_entries, new JsonSerializerOptions
            {
                WriteIndented = true,
            }));
            File.Move(temporaryPath, _path, overwrite: true);
        }
    }

    private static Dictionary<string, CacheEntry> Load(string path)
    {
        if (!File.Exists(path))
            return new Dictionary<string, CacheEntry>(StringComparer.OrdinalIgnoreCase);

        return JsonSerializer.Deserialize<Dictionary<string, CacheEntry>>(File.ReadAllText(path))
               ?? new Dictionary<string, CacheEntry>(StringComparer.OrdinalIgnoreCase);
    }

    private sealed class CacheEntry
    {
        public string InputHash { get; set; } = string.Empty;
        public string[] Outputs { get; set; } = [];
        public DateTime RecordedAtUtc { get; set; }
    }
}
