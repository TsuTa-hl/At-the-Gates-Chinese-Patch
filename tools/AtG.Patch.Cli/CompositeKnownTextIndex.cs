using AtG.Catalog;
using AtG.ManagedRewrite;
using System.Text.RegularExpressions;

/// <summary>
/// Resolves the stable source locators stored on composite literal parts against
/// the replaceable SQLite occurrence catalog. A relationship is emitted only
/// when source file, locator, and the referenced text/key agree.
/// </summary>
internal sealed class CompositeKnownTextIndex
{
    private readonly Dictionary<string, IReadOnlyList<CompositeKnownTextLink>> linksByEntryPoint;
    private readonly Dictionary<long, IReadOnlyList<CompositeKnownTextLink>> linksByOccurrenceId;
    private readonly Dictionary<string, IReadOnlyList<CompositeKnownTextUnresolvedReference>>
        unresolvedByEntryPoint;
    private readonly HashSet<string> unresolvedPartKeys;

    private CompositeKnownTextIndex(IReadOnlyList<CompositeKnownTextLink> links,
        IReadOnlyList<CompositeKnownTextUnresolvedReference> unresolved)
    {
        Links = links;
        Unresolved = unresolved;
        linksByEntryPoint = links.GroupBy(link => link.EntryPointId, StringComparer.Ordinal)
            .ToDictionary(group => group.Key, group => (IReadOnlyList<CompositeKnownTextLink>)group
                .OrderBy(link => link.PartPosition)
                .ThenBy(link => link.SourceOccurrenceId)
                .ToArray(), StringComparer.Ordinal);
        linksByOccurrenceId = links.GroupBy(link => link.SourceOccurrenceId)
            .ToDictionary(group => group.Key, group => (IReadOnlyList<CompositeKnownTextLink>)group
                .OrderBy(link => link.EntryPointId, StringComparer.Ordinal)
                .ThenBy(link => link.PartPosition)
                .ToArray());
        unresolvedByEntryPoint = unresolved.GroupBy(item => item.EntryPointId, StringComparer.Ordinal)
            .ToDictionary(group => group.Key,
                group => (IReadOnlyList<CompositeKnownTextUnresolvedReference>)group
                    .OrderBy(item => item.PartPosition)
                    .ToArray(), StringComparer.Ordinal);
        unresolvedPartKeys = unresolved.Select(item => PartKey(item.EntryPointId, item.PartPosition))
            .ToHashSet(StringComparer.Ordinal);
    }

    public IReadOnlyList<CompositeKnownTextLink> Links { get; }
    public IReadOnlyList<CompositeKnownTextUnresolvedReference> Unresolved { get; }

    public IReadOnlyList<CompositeKnownTextLink> GetEntryLinks(string entryPointId) =>
        linksByEntryPoint.TryGetValue(entryPointId, out var links) ? links : [];

    public IReadOnlyList<CompositeKnownTextLink> GetOccurrenceLinks(long sourceOccurrenceId) =>
        linksByOccurrenceId.TryGetValue(sourceOccurrenceId, out var links) ? links : [];

    public IReadOnlyList<CompositeKnownTextUnresolvedReference> GetEntryUnresolved(string entryPointId) =>
        unresolvedByEntryPoint.TryGetValue(entryPointId, out var unresolved) ? unresolved : [];

    public IReadOnlyList<CompositeKnownTextReferenceExclusion> GetEntryExclusions(
        CompositeTextEntry entry) => entry.Parts.Where(part =>
            StringComparer.Ordinal.Equals(part.Kind, "Literal") &&
            !string.IsNullOrWhiteSpace(part.KnownTextReferenceExclusionReason))
        .Select(part => new CompositeKnownTextReferenceExclusion(part.Position, part.Value,
            part.KnownTextReferenceExclusionReason!))
        .OrderBy(item => item.PartPosition)
        .ToArray();

    public string GetEntryStatus(CompositeTextEntry entry)
    {
        var indexed = entry.Parts.Count(part => part.KnownTextReference is not null);
        var exclusionCount = GetEntryExclusions(entry).Count;
        if (indexed == 0)
            return exclusionCount == 0 ? "NoKnownTextReference" : "NoKnownTextSource";
        var resolved = entry.Parts.Count(part => part.KnownTextReference is not null &&
            GetEntryLinks(entry.EntryPointId).Any(link => link.PartPosition == part.Position));
        if (resolved == indexed)
            return exclusionCount == 0 ? "Resolved" : "PartialNoKnownTextSource";
        if (resolved == 0) return "Unresolved";
        return "Partial";
    }

    public int GetEntryLocatorCount(CompositeTextEntry entry) =>
        entry.Parts.Count(part => part.KnownTextReference is not null);

    public bool IsPartUnresolved(string entryPointId, int partPosition) =>
        unresolvedPartKeys.Contains(PartKey(entryPointId, partPosition));

    public static CompositeKnownTextIndex Build(IEnumerable<CompositeTextEntry> entries,
        IEnumerable<SourceOccurrence> occurrences)
    {
        var managedOccurrences = new Dictionary<string, List<SourceOccurrence>>(
            StringComparer.OrdinalIgnoreCase);
        var xmlOccurrences = new Dictionary<string, List<SourceOccurrence>>(
            StringComparer.OrdinalIgnoreCase);
        var textKeyOccurrences = new Dictionary<string, List<SourceOccurrence>>(
            StringComparer.OrdinalIgnoreCase);
        var configOccurrences = new Dictionary<string, List<SourceOccurrence>>(
            StringComparer.OrdinalIgnoreCase);
        var runtimeMapOccurrences = new Dictionary<string, List<SourceOccurrence>>(
            StringComparer.OrdinalIgnoreCase);
        foreach (var occurrence in occurrences)
        {
            var locators = ParseLocators(occurrence.Locators);
            if (TryGetManagedLocator(locators, out var methodToken, out var ilOffset))
            {
                Add(managedOccurrences, ManagedKey(occurrence.SourceFile, methodToken, ilOffset), occurrence);
            }
            if (locators.TryGetValue("XPath", out var xpath) && !string.IsNullOrWhiteSpace(xpath))
            {
                Add(xmlOccurrences, XmlKey(occurrence.SourceFile, xpath), occurrence);
            }
            if (TryGetConfigLocator(locators, out var configId, out var configXPath,
                    out var configIndex))
            {
                Add(configOccurrences, ConfigKey(occurrence.SourceFile, configId, configXPath,
                    configIndex), occurrence);
            }
            if (TryGetRuntimeMapLocator(locators, out var runtimeMapSection,
                    out var runtimeMapOriginal, out var runtimeMapConceptKey))
            {
                Add(runtimeMapOccurrences, RuntimeMapKey(occurrence.SourceFile,
                    runtimeMapSection, runtimeMapOriginal, runtimeMapConceptKey), occurrence);
            }
            var textKey = (occurrence.Locators ?? "").Trim();
            if (textKey.Length > 0 && textKey.IndexOf('=') < 0)
                Add(textKeyOccurrences, TextKeyKey(occurrence.SourceFile, textKey), occurrence);
        }

        var links = new List<CompositeKnownTextLink>();
        var unresolved = new List<CompositeKnownTextUnresolvedReference>();
        foreach (var entry in entries)
        {
            foreach (var part in entry.Parts.Where(part =>
                         StringComparer.Ordinal.Equals(part.Kind, "Literal") &&
                         part.KnownTextReference is not null))
            {
                var reference = part.KnownTextReference!;
                var candidates = FindCandidates(reference, managedOccurrences, xmlOccurrences,
                    textKeyOccurrences, configOccurrences, runtimeMapOccurrences,
                    out var locatorKind, out var missingLocatorReason);
                if (candidates is null)
                {
                    unresolved.Add(new CompositeKnownTextUnresolvedReference(entry.EntryPointId,
                        part.Position, part.Value, missingLocatorReason));
                    continue;
                }

                var matched = string.IsNullOrWhiteSpace(reference.TextKey)
                    ? candidates.Where(occurrence => LiteralEquals(occurrence.Original,
                            reference.Original)).OrderBy(occurrence => occurrence.Id).ToArray()
                    : candidates.OrderBy(occurrence => occurrence.Id).ToArray();
                if (matched.Length == 0)
                {
                    unresolved.Add(new CompositeKnownTextUnresolvedReference(entry.EntryPointId,
                        part.Position, part.Value, candidates.Count == 0
                            ? "KnownTextOccurrenceMissing"
                            : "KnownTextOriginalMismatch"));
                    continue;
                }

                foreach (var occurrence in matched)
                {
                    links.Add(new CompositeKnownTextLink(entry.EntryPointId, part.Position, part.Value,
                        locatorKind, TextMatch(occurrence.Original, reference), occurrence.Id,
                        occurrence.SemanticGroupId, occurrence.SourceFile, occurrence.Original,
                        occurrence.Translation, occurrence.Status, occurrence.ReviewState,
                        occurrence.Safety, occurrence.Locators));
                }
            }
        }
        return new CompositeKnownTextIndex(links, unresolved);
    }

    private static IReadOnlyList<SourceOccurrence>? FindCandidates(CompositeKnownTextReference reference,
        IReadOnlyDictionary<string, List<SourceOccurrence>> managedOccurrences,
        IReadOnlyDictionary<string, List<SourceOccurrence>> xmlOccurrences,
        IReadOnlyDictionary<string, List<SourceOccurrence>> textKeyOccurrences,
        IReadOnlyDictionary<string, List<SourceOccurrence>> configOccurrences,
        IReadOnlyDictionary<string, List<SourceOccurrence>> runtimeMapOccurrences, out string locatorKind,
        out string missingLocatorReason)
    {
        locatorKind = "";
        missingLocatorReason = "NoStableKnownTextLocator";
        if (!string.IsNullOrWhiteSpace(reference.TextKey))
        {
            locatorKind = "TextKeyExactLocator";
            textKeyOccurrences.TryGetValue(TextKeyKey(reference.SourceFile, reference.TextKey),
                out var matches);
            return matches ?? [];
        }
        if (!string.IsNullOrWhiteSpace(reference.RuntimeMapSection) ||
            !string.IsNullOrWhiteSpace(reference.RuntimeMapOriginal) ||
            !string.IsNullOrWhiteSpace(reference.RuntimeMapConceptKey))
        {
            locatorKind = "RuntimeMapExactLocator";
            if (string.IsNullOrWhiteSpace(reference.RuntimeMapSection) ||
                string.IsNullOrWhiteSpace(reference.RuntimeMapOriginal))
            {
                missingLocatorReason = "IncompleteRuntimeMapLocator";
                return null;
            }
            runtimeMapOccurrences.TryGetValue(RuntimeMapKey(reference.SourceFile,
                reference.RuntimeMapSection, reference.RuntimeMapOriginal,
                reference.RuntimeMapConceptKey), out var matches);
            return matches ?? [];
        }
        if (!string.IsNullOrWhiteSpace(reference.MethodToken) && reference.ILOffset is not null)
        {
            locatorKind = "ManagedExactLocator";
            managedOccurrences.TryGetValue(ManagedKey(reference.SourceFile, reference.MethodToken,
                reference.ILOffset.Value), out var matches);
            return matches ?? [];
        }
        if (!string.IsNullOrWhiteSpace(reference.ConfigId) &&
            !string.IsNullOrWhiteSpace(reference.ConfigXPath))
        {
            locatorKind = "ConfigIdXPathIndexLocator";
            configOccurrences.TryGetValue(ConfigKey(reference.SourceFile, reference.ConfigId,
                reference.ConfigXPath, ConfigIndexText(reference.ConfigIndex)), out var matches);
            return matches ?? [];
        }
        if (!string.IsNullOrWhiteSpace(reference.XPath))
        {
            locatorKind = "XmlExactLocator";
            xmlOccurrences.TryGetValue(XmlKey(reference.SourceFile, reference.XPath), out var matches);
            return matches ?? [];
        }
        return null;
    }

    private static void Add(Dictionary<string, List<SourceOccurrence>> index, string key,
        SourceOccurrence occurrence)
    {
        if (!index.TryGetValue(key, out var bucket))
        {
            bucket = [];
            index[key] = bucket;
        }
        bucket.Add(occurrence);
    }

    private static bool TryGetManagedLocator(IReadOnlyDictionary<string, string> locators,
        out string methodToken, out int ilOffset)
    {
        methodToken = "";
        ilOffset = 0;
        if (!locators.TryGetValue("MethodToken", out var locatedToken) ||
            string.IsNullOrWhiteSpace(locatedToken) ||
            !locators.TryGetValue("ILOffset", out var offsetText) ||
            !int.TryParse(offsetText, out ilOffset))
            return false;
        methodToken = locatedToken;
        return true;
    }

    private static bool TryGetConfigLocator(IReadOnlyDictionary<string, string> locators,
        out string id, out string xpath, out string index)
    {
        id = "";
        xpath = "";
        index = "";
        if (!locators.TryGetValue("ID", out var locatedId) ||
            string.IsNullOrWhiteSpace(locatedId) ||
            !locators.TryGetValue("XPath", out var locatedXPath) ||
            string.IsNullOrWhiteSpace(locatedXPath))
            return false;
        id = locatedId;
        xpath = locatedXPath;
        if (locators.TryGetValue("Index", out var locatedIndex)) index = locatedIndex;
        return true;
    }

    private static bool TryGetRuntimeMapLocator(IReadOnlyDictionary<string, string> locators,
        out string section, out string original, out string conceptKey)
    {
        section = "";
        original = "";
        conceptKey = "";
        if (!locators.TryGetValue("RuntimeMapSection", out var locatedSection) ||
            string.IsNullOrWhiteSpace(locatedSection) ||
            !locators.TryGetValue("RuntimeMapOriginal", out var locatedOriginal) ||
            string.IsNullOrWhiteSpace(locatedOriginal))
            return false;
        section = locatedSection;
        original = locatedOriginal;
        if (locators.TryGetValue("RuntimeMapConceptKey", out var locatedConceptKey))
            conceptKey = locatedConceptKey;
        return true;
    }

    private static Dictionary<string, string> ParseLocators(string? locators)
    {
        var result = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var segment in (locators ?? "").Split(';'))
        {
            var separator = segment.IndexOf('=');
            if (separator <= 0) continue;
            var key = segment[..separator].Trim();
            if (key.Length == 0) continue;
            result[key] = segment[(separator + 1)..].Trim();
        }
        return result;
    }

    private static string ManagedKey(string sourceFile, string methodToken, int ilOffset) =>
        NormalizeSourceFile(sourceFile) + "\u001f" + NormalizeMethodToken(methodToken) + "\u001f" + ilOffset;

    private static string XmlKey(string sourceFile, string xpath) =>
        NormalizeSourceFile(sourceFile) + "\u001f" + xpath.Trim();

    private static string TextKeyKey(string sourceFile, string textKey) =>
        NormalizeSourceFile(sourceFile) + "\u001f" + textKey.Trim();

    private static string ConfigKey(string sourceFile, string id, string xpath, string index) =>
        NormalizeSourceFile(sourceFile) + "\u001f" + id.Trim() + "\u001f" + xpath.Trim() +
        "\u001f" + index.Trim();

    private static string RuntimeMapKey(string sourceFile, string section, string original,
        string? conceptKey) => NormalizeSourceFile(sourceFile) + "\u001f" +
        NormalizeReviewLine(section) + "\u001f" + NormalizeReviewLine(original) + "\u001f" +
        NormalizeReviewLine(conceptKey ?? "");

    private static string ConfigIndexText(int? index) => index?.ToString(
        System.Globalization.CultureInfo.InvariantCulture) ?? "";

    private static string NormalizeSourceFile(string value)
    {
        var normalized = (value ?? "").Replace('\\', '/').Trim();
        while (normalized.StartsWith("./", StringComparison.Ordinal)) normalized = normalized[2..];
        return normalized;
    }

    private static string NormalizeMethodToken(string value) => (value ?? "").Trim().ToUpperInvariant();

    private static string TextMatch(string occurrence, CompositeKnownTextReference reference)
    {
        if (!string.IsNullOrWhiteSpace(reference.TextKey)) return "TextKey";
        if (StringComparer.Ordinal.Equals(occurrence, reference.Original)) return "Exact";
        if (StringComparer.Ordinal.Equals(NormalizeLiteral(occurrence),
                NormalizeLiteral(reference.Original)))
            return "NormalizedBoundaryWhitespace";
        return "ReviewLineNormalized";
    }

    private static bool LiteralEquals(string left, string right) =>
        StringComparer.Ordinal.Equals(NormalizeLiteral(left), NormalizeLiteral(right)) ||
        StringComparer.Ordinal.Equals(NormalizeReviewLine(left), NormalizeReviewLine(right));

    private static string NormalizeLiteral(string value) => (value ?? "")
        .Replace("\r\n", "\n", StringComparison.Ordinal)
        .Replace("\r", "\n", StringComparison.Ordinal)
        .Trim();

    // Mirrors Export-KnownTextReview.ps1's ConvertTo-ReviewLine. This is only
    // used after an exact durable locator has selected the source occurrence.
    private static string NormalizeReviewLine(string value) => Regex.Replace((value ?? "")
            .Replace("\r\n", "\\n", StringComparison.Ordinal)
            .Replace("\n", "\\n", StringComparison.Ordinal)
            .Replace("\r", "\\n", StringComparison.Ordinal)
            .Replace("\t", " ", StringComparison.Ordinal)
            .Trim(), " {2,}", " ", RegexOptions.CultureInvariant);

    private static string PartKey(string entryPointId, int partPosition) =>
        entryPointId + "\u001f" + partPosition;
}

internal sealed record CompositeKnownTextLink(
    string EntryPointId,
    int PartPosition,
    string PartValue,
    string LocatorKind,
    string TextMatch,
    long SourceOccurrenceId,
    long SemanticGroupId,
    string SourceFile,
    string Original,
    string Translation,
    string Status,
    string ReviewState,
    string Safety,
    string Locators);

internal sealed record CompositeKnownTextUnresolvedReference(
    string EntryPointId,
    int PartPosition,
    string PartValue,
    string Reason);

internal sealed record CompositeKnownTextReferenceExclusion(
    int PartPosition,
    string PartValue,
    string Reason);
