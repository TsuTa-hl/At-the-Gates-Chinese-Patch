using System.Text.Json;

namespace AtG.ManagedRewrite;

public static class RewriteMap
{
    public static IReadOnlyList<StringRewriteSpec> Load(string path)
    {
        var options = new JsonSerializerOptions
        {
            PropertyNameCaseInsensitive = true,
            ReadCommentHandling = JsonCommentHandling.Skip,
            AllowTrailingCommas = true,
        };
        var json = File.ReadAllText(path);
        using var document = JsonDocument.Parse(json, new JsonDocumentOptions
        {
            CommentHandling = JsonCommentHandling.Skip,
            AllowTrailingCommas = true,
        });

        var specs = document.RootElement.ValueKind switch
        {
            JsonValueKind.Array => JsonSerializer.Deserialize<List<StringRewriteSpec>>(json, options) ?? [],
            JsonValueKind.Object => [JsonSerializer.Deserialize<StringRewriteSpec>(json, options)
                                     ?? throw new InvalidDataException("Rewrite map entry is empty.")],
            _ => throw new InvalidDataException("Rewrite map must contain an object or array."),
        };

        foreach (var spec in specs)
        {
            if (string.IsNullOrWhiteSpace(spec.MethodToken) || spec.Original is null || spec.Translation is null)
                throw new InvalidDataException("Rewrite entries require MethodToken, Original, and Translation.");
        }
        return specs;
    }
}
