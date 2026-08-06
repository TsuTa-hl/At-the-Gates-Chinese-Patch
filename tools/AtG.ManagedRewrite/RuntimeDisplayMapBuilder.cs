using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace AtG.ManagedRewrite;

public sealed record RuntimeDisplayMapBuildResult(
    int ConceptKeyCount,
    int ExactCount,
    int PlainTextCount,
    int PlainTextFragmentCount,
    int RichTextFragmentCount,
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
    private static readonly Regex RuntimeTemplateArgument = new(
        @"\{arg:\d+\}", RegexOptions.CultureInvariant);
    private static readonly Regex RuntimeTemplateAnchor = new(
        @"[A-Za-z0-9]{4,}", RegexOptions.CultureInvariant);

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
        var exact = (model.Exact ?? []).ToList();
        var plain = model.PlainText ?? [];
        var plainFragments = (model.PlainTextFragments ?? []).ToList();
        var richTextFragments = (model.RichTextFragments ?? []).ToList();
        var templates = (model.Templates ?? []).ToList();
        var configuredConceptDisplay = model.ConceptDisplay ?? [];
        var conceptDisplay = configuredConceptDisplay.ToList();

        ImportCompositeExactSources(mapPath, model.CompositeExactSources, exact);
        ImportCompositeFragmentSources(mapPath, model.CompositeFragmentSources,
            plainFragments);
        ImportCompositeTemplateSources(mapPath, model.CompositeTemplateSources, templates);
        ValidateUnique(exact, entry => entry.Original, "exact");
        ValidateUnique(plain, entry => entry.Original, "plain-text");
        ValidateUnique(plainFragments, entry => entry.Original, "plain-text-fragment");
        ValidateUnique(richTextFragments, entry => entry.Original, "rich-text-fragment");
        ValidateUnique(templates, entry => entry.Original, "template");
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
        foreach (var entry in plainFragments)
        {
            ValidateDisplay(entry.Original, "PlainTextFragments.Original");
            ValidateFragmentTranslation(entry.Translation, "PlainTextFragments.Translation");
        }
        foreach (var entry in richTextFragments)
        {
            ValidateRequired(entry.Original, "RichTextFragments.Original");
            ValidateRequired(entry.Translation, "RichTextFragments.Translation");
            var originalKeys = ExtractConceptKeys(entry.Original, conceptKeys);
            var translatedKeys = ExtractConceptKeys(entry.Translation, conceptKeys);
            if (!originalKeys.SequenceEqual(translatedKeys, StringComparer.Ordinal))
                throw new InvalidDataException(
                    $"Rich-text fragment changes concept keys: '{entry.Original}' -> '{entry.Translation}'.");
        }
        foreach (var entry in templates)
        {
            ValidateRequired(entry.Original, "Template.Original");
            ValidateRequired(entry.Translation, "Template.Translation");
            if (!IsRuntimeSafeTemplate(entry.Original))
                throw new InvalidDataException(
                    $"Template.Original is not specific enough for the runtime display boundary: '{entry.Original}'.");
            ValidateTemplateArguments(entry.Original, entry.Translation);
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

        var lines = new List<string>(conceptKeys.Count + exact.Count + plain.Length +
            plainFragments.Count + richTextFragments.Count + templates.Count +
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
        lines.AddRange(plainFragments.OrderByDescending(entry => entry.Original.Length)
            .ThenBy(entry => entry.Original, StringComparer.Ordinal)
            .Select(entry => "F\t" + Encode(entry.Original) + "\t" + Encode(entry.Translation)));
        lines.AddRange(richTextFragments.OrderByDescending(entry => entry.Original.Length)
            .ThenBy(entry => entry.Original, StringComparer.Ordinal)
            .Select(entry => "R\t" + Encode(entry.Original) + "\t" + Encode(entry.Translation)));
        lines.AddRange(templates.OrderByDescending(entry => entry.Original.Length)
            .ThenBy(entry => entry.Original, StringComparer.Ordinal)
            .Select(entry => "T\t" + Encode(entry.Original) + "\t" + Encode(entry.Translation)));
        lines.AddRange(conceptDisplay
            .OrderBy(entry => entry.ConceptKey, StringComparer.Ordinal)
            .ThenBy(entry => entry.Original, StringComparer.Ordinal)
            .Select(entry => "C\t" + Encode(entry.ConceptKey) + "\t" +
                Encode(entry.Original) + "\t" + Encode(entry.Translation)));

        var output = Path.GetFullPath(outputPath);
        Directory.CreateDirectory(Path.GetDirectoryName(output)!);
        // Keep generated patch data byte-stable across Windows and CI hosts.
        File.WriteAllText(output, string.Join("\n", lines) + "\n", new UTF8Encoding(false));
        return new RuntimeDisplayMapBuildResult(conceptKeys.Count, exact.Count,
            plain.Length, plainFragments.Count, richTextFragments.Count,
            conceptDisplay.Count, output);
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

    private static void ImportCompositeExactSources(string mapPath,
        string[]? sourcePaths, List<RuntimeDisplayEntry> destination)
    {
        if (sourcePaths is null || sourcePaths.Length == 0) return;
        var mapDirectory = Path.GetDirectoryName(Path.GetFullPath(mapPath))!;
        var known = destination.ToDictionary(entry => entry.Original,
            entry => entry.Translation, StringComparer.Ordinal);
        foreach (var configuredPath in sourcePaths)
        {
            ValidateRequired(configuredPath, "CompositeExactSources entry");
            var sourcePath = Path.IsPathRooted(configuredPath)
                ? Path.GetFullPath(configuredPath)
                : Path.GetFullPath(Path.Combine(mapDirectory, configuredPath));
            var document = JsonSerializer.Deserialize<CompositeCatalogDocument>(
                File.ReadAllText(sourcePath),
                new JsonSerializerOptions { PropertyNameCaseInsensitive = true })
                ?? throw new InvalidDataException(
                    $"Composite exact source is empty: {sourcePath}");
            foreach (var composite in document.Entries)
            {
                if (composite.Stale || composite.LocalizedFormat is null ||
                    composite.Source.Kind != "Managed" ||
                    !StringComparer.Ordinal.Equals(composite.Classification, "DisplayComposite") ||
                    !StringComparer.Ordinal.Equals(composite.RuleId, "runtime-display-exact"))
                    continue;

                var entry = new RuntimeDisplayEntry
                {
                    Original = composite.OriginalFormat,
                    Translation = composite.LocalizedFormat,
                };
                ValidateRequired(entry.Original, "Composite exact OriginalFormat");
                ValidateRequired(entry.Translation, "Composite exact LocalizedFormat");
                if (known.TryGetValue(entry.Original, out var existing))
                {
                    if (!StringComparer.Ordinal.Equals(existing, entry.Translation))
                        throw new InvalidDataException(
                            $"Conflicting composite exact display text '{entry.Original}'.");
                    continue;
                }
                known.Add(entry.Original, entry.Translation);
                destination.Add(entry);
            }
        }
    }

    private static void ImportCompositeFragmentSources(string mapPath,
        string[]? sourcePaths, List<RuntimeDisplayEntry> destination)
    {
        if (sourcePaths is null || sourcePaths.Length == 0) return;
        var mapDirectory = Path.GetDirectoryName(Path.GetFullPath(mapPath))!;
        var known = destination.GroupBy(entry => entry.Original, StringComparer.Ordinal)
            .ToDictionary(group => group.Key, group => group.First().Translation,
                StringComparer.Ordinal);

        foreach (var configuredPath in sourcePaths)
        {
            ValidateRequired(configuredPath, "CompositeFragmentSources entry");
            var sourcePath = Path.IsPathRooted(configuredPath)
                ? Path.GetFullPath(configuredPath)
                : Path.GetFullPath(Path.Combine(mapDirectory, configuredPath));
            var document = JsonSerializer.Deserialize<CompositeCatalogDocument>(
                File.ReadAllText(sourcePath),
                new JsonSerializerOptions { PropertyNameCaseInsensitive = true })
                ?? throw new InvalidDataException(
                    $"Composite fragment source is empty: {sourcePath}");

            var rewriteTranslations = document.Entries
                .Where(entry => !entry.Stale &&
                    StringComparer.Ordinal.Equals(entry.Source.Kind, "ManagedRewriteMap") &&
                    entry.LocalizedFormat is not null)
                .GroupBy(entry => entry.OriginalFormat, StringComparer.Ordinal)
                .ToDictionary(
                    group => group.Key,
                    group => group.Select(entry => entry.LocalizedFormat!)
                        .Distinct(StringComparer.Ordinal).ToArray(),
                    StringComparer.Ordinal);

            var referencedLiterals = document.Entries
                .Where(entry => !entry.Stale &&
                    StringComparer.Ordinal.Equals(entry.Source.Kind, "Managed") &&
                    entry.Parts.Count > 1)
                .SelectMany(entry => entry.Parts)
                .Where(part => StringComparer.Ordinal.Equals(part.Kind, "Literal") &&
                    IsRuntimeSafeFragment(part.Value))
                .Select(part => part.Value)
                .Distinct(StringComparer.Ordinal);

            foreach (var original in referencedLiterals)
            {
                if (!rewriteTranslations.TryGetValue(original, out var translations) ||
                    translations.Length != 1 || string.IsNullOrEmpty(translations[0]))
                    continue;
                if (known.ContainsKey(original)) continue;
                known.Add(original, translations[0]);
                destination.Add(new RuntimeDisplayEntry
                {
                    Original = original,
                    Translation = translations[0],
                });
            }
        }
    }

    private static void ImportCompositeTemplateSources(string mapPath,
        string[]? sourcePaths, List<RuntimeDisplayEntry> destination)
    {
        if (sourcePaths is null || sourcePaths.Length == 0) return;
        var mapDirectory = Path.GetDirectoryName(Path.GetFullPath(mapPath))!;
        var known = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var configuredPath in sourcePaths)
        {
            ValidateRequired(configuredPath, "CompositeTemplateSources entry");
            var sourcePath = Path.IsPathRooted(configuredPath)
                ? Path.GetFullPath(configuredPath)
                : Path.GetFullPath(Path.Combine(mapDirectory, configuredPath));
            var document = JsonSerializer.Deserialize<CompositeCatalogDocument>(
                File.ReadAllText(sourcePath),
                new JsonSerializerOptions { PropertyNameCaseInsensitive = true })
                ?? throw new InvalidDataException(
                    $"Composite template source is empty: {sourcePath}");
            foreach (var composite in document.Entries.Where(entry =>
                         !entry.Stale && entry.LocalizedFormat is not null &&
                         StringComparer.Ordinal.Equals(entry.Source.Kind, "Managed") &&
                         StringComparer.Ordinal.Equals(entry.RuleId, "runtime-display-template")))
            {
                // Templates run against every text value at draw time. A template whose
                // only literals are whitespace or punctuation (for example
                // "{arg:0} {arg:2}") matches ordinary UI text and can rewrite all of its
                // separators. Emit only templates with a stable, specific source anchor.
                if (!IsRuntimeSafeTemplate(composite.OriginalFormat)) continue;
                if (known.TryGetValue(composite.OriginalFormat, out var existing))
                {
                    if (!StringComparer.Ordinal.Equals(existing, composite.LocalizedFormat))
                        throw new InvalidDataException(
                            $"Conflicting composite display template '{composite.OriginalFormat}'.");
                    continue;
                }
                known.Add(composite.OriginalFormat, composite.LocalizedFormat!);
                destination.Add(new RuntimeDisplayEntry
                {
                    Original = composite.OriginalFormat,
                    Translation = composite.LocalizedFormat!,
                });
            }
        }
    }

    private static bool IsRuntimeSafeFragment(string value)
    {
        if (string.IsNullOrWhiteSpace(value) ||
            value.IndexOfAny(['[', ']', '|']) >= 0)
            return false;
        // Fragments run over every final display value. A determiner,
        // preposition, or other short token (for example "The " or "in ")
        // is only meaningful in the source method that produced it and must
        // not leak into names or unrelated UI. Keep the same stable-anchor
        // threshold used for runtime templates.
        return RuntimeTemplateAnchor.IsMatch(value);
    }

    private static bool IsRuntimeSafeTemplate(string value)
    {
        if (string.IsNullOrEmpty(value) || !RuntimeTemplateArgument.IsMatch(value))
            return false;
        var literalText = RuntimeTemplateArgument.Replace(value, "");
        return RuntimeTemplateAnchor.IsMatch(literalText);
    }

    private static void ValidateTemplateArguments(string original, string translation)
    {
        var originalArguments = RuntimeTemplateArgument.Matches(original)
            .Select(match => match.Value)
            .OrderBy(value => value, StringComparer.Ordinal)
            .ToArray();
        var translationArguments = RuntimeTemplateArgument.Matches(translation)
            .Select(match => match.Value)
            .OrderBy(value => value, StringComparer.Ordinal)
            .ToArray();
        if (!originalArguments.SequenceEqual(translationArguments, StringComparer.Ordinal))
            throw new InvalidDataException(
                $"Runtime display template must preserve every argument: '{original}' -> '{translation}'.");
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

    private static void ValidateFragmentTranslation(string value, string description)
    {
        if (value is null)
            throw new InvalidDataException(description + " is required.");
        if (value.IndexOfAny(['[', ']', '|']) >= 0)
            throw new InvalidDataException(description + " must not contain rich-text markup.");
    }

    private static string Encode(string value) =>
        Convert.ToBase64String(Encoding.UTF8.GetBytes(value));

    private sealed class RuntimeDisplayMapModel
    {
        public RuntimeDisplayEntry[]? Exact { get; set; }
        public RuntimeDisplayEntry[]? PlainText { get; set; }
        public RuntimeDisplayEntry[]? PlainTextFragments { get; set; }
        public RuntimeDisplayEntry[]? RichTextFragments { get; set; }
        public RuntimeDisplayEntry[]? Templates { get; set; }
        public RuntimeConceptDisplayEntry[]? ConceptDisplay { get; set; }
        public string[]? ConceptDisplaySources { get; set; }
        public string[]? CompositeExactSources { get; set; }
        public string[]? CompositeFragmentSources { get; set; }
        public string[]? CompositeTemplateSources { get; set; }
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
