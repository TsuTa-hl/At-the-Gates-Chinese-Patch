using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace AtG.ManagedRewrite;

public sealed record RuntimeDisplayMapBuildResult(
    int ConceptKeyCount,
    int ExactCount,
    int PlainTextCount,
    int ConceptDisplayCount,
    string OutputPath);

public static class RuntimeDisplayMapBuilder
{
    private static readonly Regex ConceptLink = new(
        @"\[[^\]|]+\|([A-Z][A-Z0-9-]*)\]", RegexOptions.CultureInvariant);
    private static readonly Regex SingleConceptLink = new(
        @"^\[([^\]|]+)\|([A-Z][A-Z0-9-]*)\]$", RegexOptions.CultureInvariant);
    private static readonly Regex BareConceptKey = new(
        @"^[A-Z][A-Z0-9-]{1,}$", RegexOptions.CultureInvariant);

    public static RuntimeDisplayMapBuildResult Build(
        string commonAssemblyPath,
        string conceptsTypeFullName,
        string mapPath,
        string outputPath)
    {
        var conceptKeys = DiscoverConceptKeys(commonAssemblyPath, conceptsTypeFullName);
        if (conceptKeys.Count == 0)
            throw new InvalidDataException(
                $"No concept keys were discovered from '{conceptsTypeFullName}'.");

        var model = JsonSerializer.Deserialize<RuntimeDisplayMapModel>(
            File.ReadAllText(Path.GetFullPath(mapPath)),
            new JsonSerializerOptions { PropertyNameCaseInsensitive = true })
            ?? new RuntimeDisplayMapModel();
        var exact = model.Exact ?? [];
        var plain = model.PlainText ?? [];
        var configuredConceptDisplay = model.ConceptDisplay ?? [];
        var conceptDisplay = configuredConceptDisplay.ToList();

        ValidateUnique(exact, entry => entry.Original, "exact");
        ValidateUnique(plain, entry => entry.Original, "plain-text");
        ValidateUnique(configuredConceptDisplay,
            entry => entry.ConceptKey + "\u001F" + entry.Original, "concept-display");
        ImportConceptDisplaySources(mapPath, model.ConceptDisplaySources,
            conceptDisplay);
        ValidateUnique(conceptDisplay,
            entry => entry.ConceptKey + "\u001F" + entry.Original, "concept-display");
        foreach (var entry in exact)
        {
            ValidateRequired(entry.Original, "Exact.Original");
            ValidateRequired(entry.Translation, "Exact.Translation");
            var originalKeys = ExtractConceptKeys(entry.Original, conceptKeys);
            var translatedKeys = ExtractConceptKeys(entry.Translation, conceptKeys);
            if (!originalKeys.SequenceEqual(translatedKeys, StringComparer.Ordinal))
                throw new InvalidDataException(
                    $"Exact runtime translation changes concept keys: '{entry.Original}' -> '{entry.Translation}'.");
        }
        foreach (var entry in plain)
        {
            ValidateDisplay(entry.Original, "PlainText.Original");
            ValidateDisplay(entry.Translation, "PlainText.Translation");
        }
        foreach (var entry in conceptDisplay)
        {
            ValidateRequired(entry.ConceptKey, "ConceptDisplay.ConceptKey");
            if (!conceptKeys.Contains(entry.ConceptKey))
                throw new InvalidDataException(
                    $"Unknown concept key '{entry.ConceptKey}' in runtime display map.");
            ValidateDisplay(entry.Original, "ConceptDisplay.Original");
            ValidateDisplay(entry.Translation, "ConceptDisplay.Translation");
        }

        var lines = new List<string>(conceptKeys.Count + exact.Length + plain.Length +
            conceptDisplay.Count + 1)
        {
            "# AtG.RuntimeText display map v1",
        };
        lines.AddRange(conceptKeys.OrderBy(value => value, StringComparer.Ordinal)
            .Select(value => "K\t" + Encode(value)));
        lines.AddRange(exact.OrderBy(entry => entry.Original, StringComparer.Ordinal)
            .Select(entry => "E\t" + Encode(entry.Original) + "\t" + Encode(entry.Translation)));
        lines.AddRange(plain.OrderBy(entry => entry.Original, StringComparer.Ordinal)
            .Select(entry => "P\t" + Encode(entry.Original) + "\t" + Encode(entry.Translation)));
        lines.AddRange(conceptDisplay
            .OrderBy(entry => entry.ConceptKey, StringComparer.Ordinal)
            .ThenBy(entry => entry.Original, StringComparer.Ordinal)
            .Select(entry => "C\t" + Encode(entry.ConceptKey) + "\t" +
                Encode(entry.Original) + "\t" + Encode(entry.Translation)));

        var output = Path.GetFullPath(outputPath);
        Directory.CreateDirectory(Path.GetDirectoryName(output)!);
        File.WriteAllLines(output, lines, new UTF8Encoding(false));
        return new RuntimeDisplayMapBuildResult(conceptKeys.Count, exact.Length,
            plain.Length, conceptDisplay.Count, output);
    }

    private static void ImportConceptDisplaySources(string mapPath,
        string[]? sourcePaths, List<RuntimeConceptDisplayEntry> destination)
    {
        if (sourcePaths is null || sourcePaths.Length == 0) return;
        var mapDirectory = Path.GetDirectoryName(Path.GetFullPath(mapPath))!;
        var known = destination.ToDictionary(
            entry => entry.ConceptKey + "\u001F" + entry.Original,
            entry => entry.Translation, StringComparer.Ordinal);
        foreach (var configuredPath in sourcePaths)
        {
            ValidateRequired(configuredPath, "ConceptDisplaySources entry");
            var sourcePath = Path.IsPathRooted(configuredPath)
                ? Path.GetFullPath(configuredPath)
                : Path.GetFullPath(Path.Combine(mapDirectory, configuredPath));
            using var document = JsonDocument.Parse(File.ReadAllText(sourcePath),
                new JsonDocumentOptions
                {
                    AllowTrailingCommas = true,
                    CommentHandling = JsonCommentHandling.Skip,
                });
            if (document.RootElement.ValueKind != JsonValueKind.Object)
                throw new InvalidDataException(
                    $"Concept display source must be a JSON object: {sourcePath}");
            foreach (var property in document.RootElement.EnumerateObject())
            {
                if (property.Value.ValueKind != JsonValueKind.String) continue;
                var originalMatch = SingleConceptLink.Match(property.Name);
                var translation = property.Value.GetString() ?? "";
                var translationMatch = SingleConceptLink.Match(translation);
                if (!originalMatch.Success || !translationMatch.Success) continue;
                var conceptKey = originalMatch.Groups[2].Value;
                var translatedKey = translationMatch.Groups[2].Value;
                if (!StringComparer.Ordinal.Equals(conceptKey, translatedKey))
                    throw new InvalidDataException(
                        $"Imported concept display changes key '{conceptKey}' to '{translatedKey}' in {sourcePath}.");
                var entry = new RuntimeConceptDisplayEntry
                {
                    ConceptKey = conceptKey,
                    Original = originalMatch.Groups[1].Value,
                    Translation = translationMatch.Groups[1].Value,
                };
                var identity = entry.ConceptKey + "\u001F" + entry.Original;
                if (known.TryGetValue(identity, out var existing))
                {
                    if (!StringComparer.Ordinal.Equals(existing, entry.Translation))
                        throw new InvalidDataException(
                            $"Conflicting imported concept display '{entry.Original}|{entry.ConceptKey}'.");
                    continue;
                }
                known.Add(identity, entry.Translation);
                destination.Add(entry);
            }
        }
    }

    private static HashSet<string> DiscoverConceptKeys(string assemblyPath,
        string conceptsTypeFullName)
    {
        var result = new HashSet<string>(StringComparer.Ordinal);
        foreach (var entry in LdstrCatalog.Read(Path.GetFullPath(assemblyPath)).Where(entry =>
                     StringComparer.Ordinal.Equals(entry.TypeFullName, conceptsTypeFullName) &&
                     entry.MethodName == ".cctor"))
        {
            foreach (Match match in ConceptLink.Matches(entry.Value))
                result.Add(match.Groups[1].Value);
            if (BareConceptKey.IsMatch(entry.Value)) result.Add(entry.Value);
        }
        return result;
    }

    private static string[] ExtractConceptKeys(string value, HashSet<string> validKeys)
    {
        var keys = new List<string>();
        foreach (Match match in ConceptLink.Matches(value))
        {
            var key = match.Groups[1].Value;
            if (!validKeys.Contains(key))
                throw new InvalidDataException($"Runtime display text contains invalid concept key '{key}'.");
            keys.Add(key);
        }
        return keys.ToArray();
    }

    private static void ValidateUnique<T>(IEnumerable<T> entries,
        Func<T, string> keySelector, string description)
    {
        var duplicates = entries.GroupBy(keySelector, StringComparer.Ordinal)
            .Where(group => group.Count() > 1).Select(group => group.Key).ToArray();
        if (duplicates.Length > 0)
            throw new InvalidDataException(
                $"Duplicate {description} runtime display entries: {string.Join(", ", duplicates)}");
    }

    private static void ValidateRequired(string value, string description)
    {
        if (string.IsNullOrEmpty(value))
            throw new InvalidDataException(description + " is required.");
    }

    private static void ValidateDisplay(string value, string description)
    {
        ValidateRequired(value, description);
        if (value.IndexOfAny(['[', ']', '|']) >= 0)
            throw new InvalidDataException(description + " must not contain rich-text markup.");
    }

    private static string Encode(string value) =>
        Convert.ToBase64String(Encoding.UTF8.GetBytes(value));

    private sealed class RuntimeDisplayMapModel
    {
        public RuntimeDisplayEntry[]? Exact { get; set; }
        public RuntimeDisplayEntry[]? PlainText { get; set; }
        public RuntimeConceptDisplayEntry[]? ConceptDisplay { get; set; }
        public string[]? ConceptDisplaySources { get; set; }
    }

    private class RuntimeDisplayEntry
    {
        public string Original { get; set; } = "";
        public string Translation { get; set; } = "";
    }

    private sealed class RuntimeConceptDisplayEntry : RuntimeDisplayEntry
    {
        public string ConceptKey { get; set; } = "";
    }
}
