using System.Text.Json;

namespace AtG.TestHarness;

public sealed record RenderedTextObservation(
    string Event,
    string Text,
    float? X,
    float? Y,
    float? Width,
    float? Height);

public interface IRenderTextProbe
{
    long Bookmark();
    IReadOnlyList<RenderedTextObservation> ReadSince(long bookmark);
}

public sealed class JsonlRenderTextProbe : IRenderTextProbe
{
    private readonly string _path;

    public JsonlRenderTextProbe(string path) => _path = Path.GetFullPath(path);

    public long Bookmark() => File.Exists(_path) ? new FileInfo(_path).Length : 0;

    public IReadOnlyList<RenderedTextObservation> ReadSince(long bookmark)
    {
        if (!File.Exists(_path)) return [];
        var result = new List<RenderedTextObservation>();
        using var stream = new FileStream(
            _path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
        stream.Position = bookmark >= 0 && bookmark <= stream.Length ? bookmark : 0;
        using var reader = new StreamReader(stream);
        string? line;
        while ((line = reader.ReadLine()) is not null)
        {
            try
            {
                using var document = JsonDocument.Parse(line);
                var root = document.RootElement;
                if (root.TryGetProperty("text", out var text))
                    result.Add(new RenderedTextObservation(
                        ReadString(root, "event"),
                        text.GetString() ?? string.Empty,
                        ReadSingle(root, "x"),
                        ReadSingle(root, "y"),
                        ReadSingle(root, "width"),
                        ReadSingle(root, "height")));
            }
            catch (JsonException)
            {
                // Ignore a partial final line while the game is still appending.
            }
        }
        return result;
    }

    private static string ReadString(JsonElement root, string name) =>
        root.TryGetProperty(name, out var value) ? value.GetString() ?? string.Empty : string.Empty;

    private static float? ReadSingle(JsonElement root, string name) =>
        root.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.Number
            ? value.GetSingle()
            : null;
}

public static class RenderedTextFilter
{
    public static IReadOnlyList<RenderedTextObservation> InRegion(
        IEnumerable<RenderedTextObservation> observations,
        CropRegion? referenceRegion,
        int referenceWidth,
        int referenceHeight,
        int clientWidth,
        int clientHeight)
    {
        var draws = observations.Where(observation =>
            observation.Event.StartsWith("draw", StringComparison.OrdinalIgnoreCase));
        if (referenceRegion is null) return draws.ToArray();

        var left = referenceRegion.X * clientWidth / (float)referenceWidth;
        var top = referenceRegion.Y * clientHeight / (float)referenceHeight;
        var right = (referenceRegion.X + referenceRegion.Width) * clientWidth / (float)referenceWidth;
        var bottom = (referenceRegion.Y + referenceRegion.Height) * clientHeight / (float)referenceHeight;
        return draws.Where(observation =>
        {
            if (!observation.X.HasValue || !observation.Y.HasValue) return true;
            var width = Math.Max(1f, observation.Width ?? 1f);
            var height = Math.Max(1f, observation.Height ?? 1f);
            return observation.X.Value < right && observation.X.Value + width > left &&
                   observation.Y.Value < bottom && observation.Y.Value + height > top;
        }).ToArray();
    }
}
