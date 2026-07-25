using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;
using System.Xml.Linq;
using dnlib.DotNet;
using dnlib.DotNet.Emit;

namespace AtG.ManagedRewrite;

public sealed class CompositeCatalogDocument
{
    public int SchemaVersion { get; set; } = 3;
    public string GeneratedAtUtc { get; set; } = "";
    public string RepositoryRoot { get; set; } = "";
    public List<CompositeTextEntry> Entries { get; set; } = [];
    public List<CompositeLocalizationRule> Rules { get; set; } = [];
}

public sealed class CompositeTextEntry
{
    public string EntryPointId { get; set; } = "";
    public CompositeTextSource Source { get; set; } = new();
    public string OriginalFormat { get; set; } = "";
    public string? LocalizedFormat { get; set; }
    public string Classification { get; set; } = "Unreviewed";
    public string Status { get; set; } = "Unreviewed";
    public string? RuleId { get; set; }
    public string AuditStatus { get; set; } = "Unreviewed";
    public string RuleScope { get; set; } = "None";
    public string Confidence { get; set; } = "Partial";
    public List<CompositeTextPart> Parts { get; set; } = [];
    public List<string> StructuralFlags { get; set; } = [];
    public string? Notes { get; set; }
    public bool Stale { get; set; }
}

public sealed class CompositeTextSource
{
    public string Kind { get; set; } = "";
    public string RelativePath { get; set; } = "";
    public string? TypeFullName { get; set; }
    public string? MethodName { get; set; }
    public string? MethodToken { get; set; }
    public int? ILOffset { get; set; }
    public string? XPath { get; set; }
    public string? CallKind { get; set; }
}

public sealed class CompositeTextPart
{
    public int Position { get; set; }
    public string Kind { get; set; } = "";
    public string Value { get; set; } = "";
}

public sealed class CompositeLocalizationRule
{
    public string RuleId { get; set; } = "";
    public string Kind { get; set; } = "";
    public string Status { get; set; } = "Active";
    public string EntryPointId { get; set; } = "";
    public string Description { get; set; } = "";
    public string Source { get; set; } = "";
}

public sealed class CompositeEntrySpecificRuleDocument
{
    public int SchemaVersion { get; set; } = 1;
    public List<CompositeEntrySpecificRule> Entries { get; set; } = [];
}

public sealed class CompositeEntrySpecificRule
{
    public string EntryPointId { get; set; } = "";
    public string LocalizedFormat { get; set; } = "";
    public string? Notes { get; set; }
}

public sealed record CompositeCatalogResult(
    int EntryCount,
    int RuleCount,
    int ManagedEntryCount,
    int XmlEntryCount,
    int RuntimeMapEntryCount,
    string RulesPath);

public static class CompositeTextCatalog
{
    private static readonly Regex RichTextLink = new(
        @"\[[^\]|]+\|([A-Z][A-Z0-9-]*)\]", RegexOptions.CultureInvariant);
    private static readonly Regex Placeholder = new(
        @"\{(?:arg:)?\d+\}", RegexOptions.CultureInvariant);
    private static readonly Regex BracketToken = new(
        @"\[[^\]]+\]", RegexOptions.CultureInvariant);
    private static readonly Regex PipeDelimitedAlias = new(
        @"^\|[^|]+\|[^|]+\|$", RegexOptions.CultureInvariant);
    private static readonly HashSet<string> NonConceptDisplayKeys = new(StringComparer.Ordinal)
    {
        "RESPECT",
        "RELATIONS",
    };
    private static readonly IReadOnlyDictionary<string, string> LegacyBareConceptAliases =
        new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["Ennoble"] = "NOBLE",
        };

    public static CompositeCatalogResult Build(string repositoryRoot, string? rulesPath = null)
    {
        var root = Path.GetFullPath(repositoryRoot);
        rulesPath ??= Path.Combine(root, "translations", "composite-text-rules.json");
        rulesPath = Path.GetFullPath(rulesPath);

        var existing = LoadExisting(rulesPath);
        var entries = new List<CompositeTextEntry>();
        entries.AddRange(ScanManagedAssemblies(root));
        entries.AddRange(ScanXmlFiles(root));
        entries.AddRange(ReadRuntimeMapEntries(root));
        entries.AddRange(ReadManagedRewriteMapEntries(root));

        var merged = Merge(entries, existing);
        ApplyEntrySpecificRules(merged, Path.Combine(root, "translations",
            "composite-entry-specific-rules.json"));
        ApplyStaticAudit(merged);
        var rules = BuildRules(merged, existing?.Rules);
        Validate(merged, rules);

        var document = new CompositeCatalogDocument
        {
            GeneratedAtUtc = DateTime.UtcNow.ToString("o"),
            RepositoryRoot = ".",
            Entries = merged.OrderBy(entry => entry.EntryPointId, StringComparer.Ordinal).ToList(),
            Rules = rules.OrderBy(rule => rule.RuleId, StringComparer.Ordinal).ToList(),
        };
        Directory.CreateDirectory(Path.GetDirectoryName(rulesPath)!);
        File.WriteAllText(rulesPath, JsonSerializer.Serialize(document, JsonOptions));

        return new CompositeCatalogResult(
            document.Entries.Count,
            document.Rules.Count,
            document.Entries.Count(entry => entry.Source.Kind == "Managed"),
            document.Entries.Count(entry => entry.Source.Kind == "Xml"),
            document.Entries.Count(entry => entry.Source.Kind == "RuntimeMap"),
            rulesPath);
    }

    public static IReadOnlyList<CompositeTextEntry> ScanManagedAssemblies(string repositoryRoot)
    {
        var root = Path.GetFullPath(repositoryRoot);
        var source = Path.Combine(root, "source");
        var assemblies = new[]
        {
            "AtTheGatesUI.original.dll",
            "AtTheGatesCommon.original.dll",
            "AtTheGatesGame.original.exe",
            "ElfTools.original.dll",
        }.Select(name => Path.Combine(source, name))
            .Where(File.Exists)
            .ToArray();
        var result = new List<CompositeTextEntry>();
        foreach (var assemblyPath in assemblies)
        {
            using var module = ModuleDefMD.Load(assemblyPath);
            var relative = RelativePath(root, assemblyPath);
            foreach (var type in module.GetTypes())
            foreach (var method in type.Methods)
            {
                var instructions = method.Body?.Instructions;
                if (instructions is null) continue;
                for (var index = 0; index < instructions.Count; index++)
                {
                    var instruction = instructions[index];
                    if ((instruction.OpCode != OpCodes.Call && instruction.OpCode != OpCodes.Callvirt) ||
                        instruction.Operand is not IMethod target ||
                        !TryGetCompositeCallKind(target, out var callKind))
                        continue;

                    var parts = ExtractParts(instructions, index, target, callKind);
                    var original = BuildOriginalFormat(parts, callKind);
                    var token = method.MDToken.Raw.ToString("X8");
                    var entryId = $"managed:{relative}:{token}:IL_{instruction.Offset:X4}";
                    result.Add(NewEntry(entryId, new CompositeTextSource
                    {
                        Kind = "Managed",
                        RelativePath = relative,
                        TypeFullName = type.FullName,
                        MethodName = method.Name,
                        MethodToken = "0x" + token,
                        ILOffset = checked((int)instruction.Offset),
                        CallKind = callKind,
                    }, original, parts, Classify(original, callKind),
                        EstimateConfidence(parts, callKind)));
                }
            }
        }
        return result;
    }

    public static IReadOnlyList<CompositeTextEntry> ScanXmlFiles(string repositoryRoot)
    {
        var root = Path.GetFullPath(repositoryRoot);
        var sourceRoot = Path.Combine(root, "source");
        if (!Directory.Exists(sourceRoot)) return [];
        var result = new List<CompositeTextEntry>();
        foreach (var sourcePath in Directory.EnumerateFiles(sourceRoot, "*.original.xml",
                     SearchOption.AllDirectories).OrderBy(path => path, StringComparer.OrdinalIgnoreCase))
        {
            var relative = RelativePath(root, sourcePath);
            var patchPath = GetPatchXmlPath(root, sourcePath);
            var patchValues = File.Exists(patchPath)
                ? ReadXmlValues(patchPath).ToDictionary(value => value.XPath, StringComparer.Ordinal)
                : new Dictionary<string, XmlValue>(StringComparer.Ordinal);
            foreach (var value in ReadXmlValues(sourcePath))
            {
                if (!LooksComposite(value.Value)) continue;
                var entryId = "xml:" + relative + ":" + ShortHash(value.XPath);
                var parts = new List<CompositeTextPart>
                {
                    new() { Position = 0, Kind = "Literal", Value = value.Value },
                };
                var entry = NewEntry(entryId, new CompositeTextSource
                {
                    Kind = "Xml",
                    RelativePath = relative,
                    XPath = value.XPath,
                    CallKind = "XmlTemplate",
                }, value.Value, parts, Classify(value.Value, "XmlTemplate"), "Exact");
                if (patchValues.TryGetValue(value.XPath, out var localized) &&
                    !StringComparer.Ordinal.Equals(value.Value, localized.Value))
                {
                    entry.LocalizedFormat = localized.Value;
                    entry.Status = "ExistingRule";
                    entry.RuleId = "xml-existing-translation";
                    entry.Notes = "Generated from the matching patch XML node.";
                }
                result.Add(entry);
            }
        }
        return result;
    }

    public static void Validate(IEnumerable<CompositeTextEntry> entries,
        IEnumerable<CompositeLocalizationRule> rules)
    {
        var entryList = entries.ToList();
        var duplicate = entryList.GroupBy(entry => entry.EntryPointId, StringComparer.Ordinal)
            .FirstOrDefault(group => group.Count() > 1);
        if (duplicate is not null)
            throw new InvalidDataException($"Duplicate composite entry point '{duplicate.Key}'.");
        var ruleIds = new HashSet<string>(rules.Select(rule => rule.RuleId), StringComparer.Ordinal);
        var errors = new List<string>();
        foreach (var entry in entryList)
        {
            if (!string.IsNullOrWhiteSpace(entry.RuleId) && !ruleIds.Contains(entry.RuleId))
            {
                errors.Add($"Composite entry '{entry.EntryPointId}' references unknown RuleId '{entry.RuleId}'.");
                continue;
            }
            if (entry.LocalizedFormat is not null)
            {
                try
                {
                    ValidateStructure(entry.OriginalFormat, entry.LocalizedFormat, entry.EntryPointId);
                }
                catch (InvalidDataException exception)
                {
                    errors.Add(exception.Message);
                }
            }
        }
        if (errors.Count > 0)
        {
            var limit = 40;
            var message = string.Join(Environment.NewLine, errors.Take(limit));
            if (errors.Count > limit)
                message += Environment.NewLine + $"... and {errors.Count - limit} more composite validation errors.";
            throw new InvalidDataException(message);
        }
    }

    private static List<CompositeTextEntry> Merge(IEnumerable<CompositeTextEntry> discovered,
        CompositeCatalogDocument? existing)
    {
        var oldEntries = (existing?.Entries ?? []).ToDictionary(entry => entry.EntryPointId,
            StringComparer.Ordinal);
        var merged = new List<CompositeTextEntry>();
        foreach (var entry in discovered.GroupBy(item => item.EntryPointId, StringComparer.Ordinal)
                     .Select(group => group.First()))
        {
            if (oldEntries.TryGetValue(entry.EntryPointId, out var old))
            {
                if (old.LocalizedFormat is not null) entry.LocalizedFormat = old.LocalizedFormat;
                if (!string.IsNullOrWhiteSpace(old.RuleId)) entry.RuleId = old.RuleId;
                if (!string.IsNullOrWhiteSpace(old.Notes)) entry.Notes = old.Notes;
                if (!string.IsNullOrWhiteSpace(old.Status) &&
                    !StringComparer.Ordinal.Equals(old.Status, "Unreviewed"))
                    entry.Status = old.Status;
                entry.Stale = false;
            }
            merged.Add(entry);
        }
        foreach (var old in oldEntries.Values.Where(old =>
                     !merged.Any(entry => StringComparer.Ordinal.Equals(entry.EntryPointId, old.EntryPointId))))
        {
            old.Status = "Stale";
            old.Stale = true;
            old.Notes = AppendNote(old.Notes,
                "Source was not rediscovered during the latest composite catalog scan.");
            merged.Add(old);
        }
        return merged;
    }

    private static void ApplyStaticAudit(IReadOnlyList<CompositeTextEntry> entries)
    {
        var rewriteTranslations = entries
            .Where(entry => !entry.Stale &&
                StringComparer.Ordinal.Equals(entry.Source.Kind, "ManagedRewriteMap") &&
                entry.LocalizedFormat is not null)
            .GroupBy(entry => entry.OriginalFormat, StringComparer.Ordinal)
            .ToDictionary(
                group => group.Key,
                group => group.Select(entry => entry.LocalizedFormat!)
                    .Distinct(StringComparer.Ordinal).ToArray(),
                StringComparer.Ordinal);

        foreach (var entry in entries)
        {
            if (entry.Stale)
            {
                entry.AuditStatus = "Stale";
                entry.RuleScope = "None";
                continue;
            }
            if (!string.IsNullOrWhiteSpace(entry.RuleId) || entry.LocalizedFormat is not null)
            {
                entry.AuditStatus = "Localized";
                entry.RuleScope = GetRuleScope(entry.RuleId, entry.Source.Kind);
                continue;
            }
            if (!StringComparer.Ordinal.Equals(entry.Source.Kind, "Managed"))
            {
                entry.AuditStatus = "NotManagedComposition";
                entry.RuleScope = "None";
                continue;
            }
            if (entry.Parts.Count <= 1)
            {
                entry.AuditStatus = "NotConcatenation";
                entry.RuleScope = "None";
                continue;
            }

            var localizableParts = entry.Parts
                .Where(part => StringComparer.Ordinal.Equals(part.Kind, "Literal") &&
                    IsRuntimeSafeFragment(part.Value))
                .ToArray();
            if (localizableParts.Length == 0)
            {
                entry.AuditStatus = "ReviewedStructural";
                entry.RuleScope = "None";
                entry.Notes = AppendNote(entry.Notes,
                    "Static audit: entry contains only structural, tag, identifier, or non-English parts.");
                continue;
            }

            var translations = new Dictionary<string, string>(StringComparer.Ordinal);
            foreach (var part in localizableParts)
            {
                if (!rewriteTranslations.TryGetValue(part.Value, out var candidates) ||
                    candidates.Length != 1)
                    continue;
                translations[part.Value] = candidates[0];
            }
            if (translations.Count == localizableParts.Select(part => part.Value)
                .Distinct(StringComparer.Ordinal).Count())
            {
                entry.LocalizedFormat = LocalizeLiteralParts(entry, translations);
                entry.Status = "ExistingRule";
                entry.RuleId = "runtime-display-fragment";
                entry.AuditStatus = "Localized";
                entry.RuleScope = "UniformFragment";
                entry.Notes = AppendNote(entry.Notes,
                    "Static audit: every localizable literal has one shared Chinese translation across all mapped callers; final-display fragment rule applies it.");
                continue;
            }

            if (TryApplyEntrySpecificRewrite(entry, entries, out var localized, out var ruleId))
            {
                entry.LocalizedFormat = localized;
                entry.Status = "ExistingRule";
                entry.RuleId = ruleId;
                entry.AuditStatus = "Localized";
                entry.RuleScope = "EntrySpecific";
                entry.Notes = AppendNote(entry.Notes,
                    "Static audit: conflicting fragment grammar is covered by the nearest exact entry-specific IL rewrite.");
                continue;
            }

            entry.AuditStatus = "ReviewedNoSafeRule";
            entry.RuleScope = "None";
            entry.Notes = AppendNote(entry.Notes,
                "Static audit: no uniform display-safe translation or exact entry-specific rewrite was proven; retained without a localization rule.");
        }
    }

    private static void ApplyEntrySpecificRules(IReadOnlyList<CompositeTextEntry> entries,
        string rulesPath)
    {
        if (!File.Exists(rulesPath)) return;
        var document = JsonSerializer.Deserialize<CompositeEntrySpecificRuleDocument>(
            File.ReadAllText(rulesPath),
            new JsonSerializerOptions { PropertyNameCaseInsensitive = true })
            ?? throw new InvalidDataException($"Entry-specific rule document is empty: {rulesPath}");
        var duplicates = document.Entries.GroupBy(rule => rule.EntryPointId,
                StringComparer.Ordinal).FirstOrDefault(group => group.Count() > 1);
        if (duplicates is not null)
            throw new InvalidDataException(
                $"Duplicate entry-specific rule for '{duplicates.Key}'.");
        var entryById = entries.ToDictionary(entry => entry.EntryPointId,
            StringComparer.Ordinal);
        foreach (var rule in document.Entries)
        {
            if (string.IsNullOrWhiteSpace(rule.EntryPointId) ||
                string.IsNullOrWhiteSpace(rule.LocalizedFormat))
                throw new InvalidDataException(
                    "Entry-specific rules require EntryPointId and LocalizedFormat.");
            if (!entryById.TryGetValue(rule.EntryPointId, out var entry))
                throw new InvalidDataException(
                    $"Entry-specific rule references unknown entry '{rule.EntryPointId}'.");
            if (!StringComparer.Ordinal.Equals(entry.Source.Kind, "Managed"))
                throw new InvalidDataException(
                    $"Entry-specific rule '{rule.EntryPointId}' must target a managed composition.");
            entry.LocalizedFormat = rule.LocalizedFormat;
            entry.Status = "ExistingRule";
            entry.RuleId = "runtime-display-template";
            entry.AuditStatus = "Localized";
            entry.RuleScope = "EntrySpecific";
            entry.Notes = AppendNote(entry.Notes,
                rule.Notes ?? "Static entry-specific display template.");
        }
    }

    private static bool TryApplyEntrySpecificRewrite(CompositeTextEntry entry,
        IReadOnlyList<CompositeTextEntry> entries, out string localized, out string ruleId)
    {
        localized = "";
        ruleId = "";
        var partTranslations = new Dictionary<string, string>(StringComparer.Ordinal);
        var ruleIds = new HashSet<string>(StringComparer.Ordinal);
        foreach (var part in entry.Parts.Where(part =>
                     StringComparer.Ordinal.Equals(part.Kind, "Literal") &&
                     IsRuntimeSafeFragment(part.Value)))
        {
            var candidate = entries
                .Where(map => !map.Stale &&
                    StringComparer.Ordinal.Equals(map.Source.Kind, "ManagedRewriteMap") &&
                    RewriteMapTargetsAssembly(map.Source.RelativePath, entry.Source.RelativePath) &&
                    StringComparer.Ordinal.Equals(map.Source.MethodToken, entry.Source.MethodToken) &&
                    StringComparer.Ordinal.Equals(map.OriginalFormat, part.Value) &&
                    map.LocalizedFormat is not null &&
                    map.Source.ILOffset is not null && entry.Source.ILOffset is not null &&
                    map.Source.ILOffset <= entry.Source.ILOffset)
                .OrderByDescending(map => map.Source.ILOffset)
                .FirstOrDefault();
            if (candidate is null || entry.Source.ILOffset - candidate.Source.ILOffset > 128 ||
                string.IsNullOrWhiteSpace(candidate.RuleId))
                return false;
            partTranslations[part.Value] = candidate.LocalizedFormat!;
            ruleIds.Add(candidate.RuleId);
        }
        if (partTranslations.Count == 0 || ruleIds.Count != 1) return false;
        localized = LocalizeLiteralParts(entry, partTranslations);
        ruleId = ruleIds.Single();
        return true;
    }

    private static bool RewriteMapTargetsAssembly(string mapPath, string sourcePath)
    {
        if (sourcePath.Contains("AtTheGatesCommon", StringComparison.OrdinalIgnoreCase))
            return mapPath.Contains("hardcoded-common", StringComparison.OrdinalIgnoreCase);
        if (sourcePath.Contains("AtTheGatesUI", StringComparison.OrdinalIgnoreCase))
            return mapPath.Contains("hardcoded-ui", StringComparison.OrdinalIgnoreCase);
        if (sourcePath.Contains("AtTheGatesGame", StringComparison.OrdinalIgnoreCase))
            return mapPath.Contains("hardcoded-game", StringComparison.OrdinalIgnoreCase);
        if (sourcePath.Contains("ElfTools", StringComparison.OrdinalIgnoreCase))
            return mapPath.Contains("hardcoded-elftools", StringComparison.OrdinalIgnoreCase);
        return false;
    }

    private static string LocalizeLiteralParts(CompositeTextEntry entry,
        IReadOnlyDictionary<string, string> translations)
    {
        var builder = new StringBuilder();
        var searchStart = 0;
        foreach (var part in entry.Parts.OrderBy(part => part.Position))
        {
            if (!StringComparer.Ordinal.Equals(part.Kind, "Literal") ||
                !translations.TryGetValue(part.Value, out var replacement))
                continue;
            var index = entry.OriginalFormat.IndexOf(part.Value, searchStart,
                StringComparison.Ordinal);
            if (index < 0) throw new InvalidDataException(
                $"Cannot localize composite literal '{part.Value}' in '{entry.EntryPointId}'.");
            builder.Append(entry.OriginalFormat, searchStart, index - searchStart);
            builder.Append(replacement);
            searchStart = index + part.Value.Length;
        }
        builder.Append(entry.OriginalFormat, searchStart,
            entry.OriginalFormat.Length - searchStart);
        return builder.ToString();
    }

    private static string GetRuleScope(string? ruleId, string sourceKind) =>
        ruleId is not null && ruleId.StartsWith("il-rewrite-", StringComparison.Ordinal)
            ? "EntrySpecific"
            : StringComparer.Ordinal.Equals(ruleId, "runtime-display-fragment")
                ? "UniformFragment"
                : StringComparer.Ordinal.Equals(sourceKind, "RuntimeMap")
                    ? "RuntimeMap"
                    : "EntrySpecific";

    private static List<CompositeLocalizationRule> BuildRules(IEnumerable<CompositeTextEntry> entries,
        IEnumerable<CompositeLocalizationRule>? existingRules)
    {
        var rules = new Dictionary<string, CompositeLocalizationRule>(StringComparer.Ordinal)
        {
            ["runtime-richtext-final-process"] = new()
            {
                RuleId = "runtime-richtext-final-process",
                Kind = "RuntimeFinalDisplay",
                Status = "Active",
                EntryPointId = "AtTheGatesCommon.ns_Text.TextFormatter::Process",
                Description = "Final rich-text localization preserves concept keys and recursive hover structure.",
                Source = "tools/AtG.RuntimeText/DisplayStringLocalizer.cs",
            },
            ["runtime-display-exact"] = new()
            {
                RuleId = "runtime-display-exact",
                Kind = "RuntimeDisplayMap",
                Status = "Active",
                EntryPointId = "runtime-map:Exact",
                Description = "Exact final display strings are localized without token rewriting.",
                Source = "translations/runtime-display-strings.json",
            },
            ["runtime-display-plain"] = new()
            {
                RuleId = "runtime-display-plain",
                Kind = "RuntimeDisplayMap",
                Status = "Active",
                EntryPointId = "runtime-map:PlainText",
                Description = "Plain final display strings are localized at the rich-text display boundary.",
                Source = "translations/runtime-display-strings.json",
            },
            ["runtime-display-fragment"] = new()
            {
                RuleId = "runtime-display-fragment",
                Kind = "RuntimeDisplayMap",
                Status = "Active",
                EntryPointId = "runtime-map:PlainTextFragments",
                Description = "Legacy display fragments are applied only after the final rich-text boundary.",
                Source = "translations/runtime-display-strings.json",
            },
            ["runtime-display-template"] = new()
            {
                RuleId = "runtime-display-template",
                Kind = "RuntimeDisplayTemplate",
                Status = "Active",
                EntryPointId = "runtime-map:Templates",
                Description = "Entry-specific display templates preserve every runtime argument and rich-text structure.",
                Source = "translations/composite-entry-specific-rules.json",
            },
            ["runtime-display-concept"] = new()
            {
                RuleId = "runtime-display-concept",
                Kind = "RuntimeDisplayMap",
                Status = "Active",
                EntryPointId = "runtime-map:ConceptDisplay",
                Description = "Only concept-link display text changes; the concept key remains intact.",
                Source = "translations/runtime-display-strings.json",
            },
            ["xml-existing-translation"] = new()
            {
                RuleId = "xml-existing-translation",
                Kind = "XmlDisplayTemplate",
                Status = "Active",
                EntryPointId = "patch:xml",
                Description = "Existing patch XML supplies the localized display format for the same source node.",
                Source = "patch/Content",
            },
        };
        foreach (var existing in existingRules ?? [])
        {
            if (string.IsNullOrWhiteSpace(existing.RuleId) || rules.ContainsKey(existing.RuleId))
                continue;
            rules[existing.RuleId] = new CompositeLocalizationRule
            {
                RuleId = existing.RuleId,
                Kind = existing.Kind,
                Status = existing.Status,
                EntryPointId = existing.EntryPointId,
                Description = existing.Description,
                Source = existing.Source,
            };
        }
        foreach (var entry in entries)
        {
            if (string.IsNullOrWhiteSpace(entry.RuleId)) continue;
            if (rules.ContainsKey(entry.RuleId)) continue;
            rules[entry.RuleId] = new CompositeLocalizationRule
            {
                RuleId = entry.RuleId,
                Kind = entry.Source.Kind == "ManagedRewriteMap" ? "ManagedIlRewrite" : "Manual",
                Status = entry.Status,
                EntryPointId = entry.EntryPointId,
                Description = entry.Notes ?? "Preserved generated or manually maintained localization binding.",
                Source = entry.Source.RelativePath,
            };
        }
        return rules.Values.ToList();
    }

    private static IEnumerable<CompositeTextEntry> ReadRuntimeMapEntries(string root)
    {
        var path = Path.Combine(root, "translations", "runtime-display-strings.json");
        if (!File.Exists(path)) yield break;
        using var document = OpenJson(path);
        if (document.RootElement.ValueKind != JsonValueKind.Object) yield break;
        foreach (var section in new[] { "Exact", "PlainText", "PlainTextFragments", "ConceptDisplay" })
        {
            if (!document.RootElement.TryGetProperty(section, out var values) ||
                values.ValueKind != JsonValueKind.Array) continue;
            var position = 0;
            foreach (var value in values.EnumerateArray())
            {
                if (!TryGetString(value, "Original", out var original) ||
                    !TryGetString(value, "Translation", out var translation)) continue;
                var key = section == "ConceptDisplay" && TryGetString(value, "ConceptKey", out var conceptKey)
                    ? conceptKey : null;
                var originalFormat = key is null ? original : $"[{original}|{key}]";
                var localizedFormat = key is null ? translation : $"[{translation}|{key}]";
                var entry = NewEntry($"runtime-map:{section}:{ShortHash((key ?? "") + "\u001f" + original)}",
                    new CompositeTextSource
                    {
                        Kind = "RuntimeMap",
                        RelativePath = "translations/runtime-display-strings.json",
                        CallKind = section,
                    }, originalFormat,
                    [new CompositeTextPart { Position = 0, Kind = "Literal", Value = originalFormat }],
                    "DisplaySafe",
                    "Exact");
                entry.LocalizedFormat = localizedFormat;
                entry.Status = "ExistingRule";
                entry.RuleId = section switch
                {
                    "Exact" => "runtime-display-exact",
                    "PlainText" => "runtime-display-plain",
                    "PlainTextFragments" => "runtime-display-fragment",
                    _ => "runtime-display-concept",
                };
                entry.Notes = key is null ? "Generated from runtime display-map binding."
                    : $"Generated from runtime concept-display binding for key '{key}'.";
                yield return entry;
                position++;
            }
        }
    }

    private static IEnumerable<CompositeTextEntry> ReadManagedRewriteMapEntries(string root)
    {
        var maps = new[]
        {
            ("hardcoded-ui-il-rewrite.json", "il-rewrite-ui"),
            ("hardcoded-common-il-rewrite.json", "il-rewrite-common"),
            ("hardcoded-game-il-rewrite.json", "il-rewrite-game"),
            ("hardcoded-elftools-il-rewrite.json", "il-rewrite-elftools"),
        };
        foreach (var (name, ruleId) in maps)
        {
            var path = Path.Combine(root, "translations", name);
            if (!File.Exists(path)) continue;
            using var document = OpenJson(path);
            if (document.RootElement.ValueKind != JsonValueKind.Array) continue;
            foreach (var value in document.RootElement.EnumerateArray())
            {
                if (!TryGetString(value, "Original", out var original) ||
                    !TryGetString(value, "Translation", out var translation)) continue;
                if (!TryGetString(value, "MethodToken", out var token) ||
                    !value.TryGetProperty("ILOffset", out var offsetElement) ||
                    !offsetElement.TryGetInt32(out var offset)) continue;
                var relative = "translations/" + name;
                var entry = NewEntry($"managed-map:{name}:{token}:IL_{offset:X4}",
                    new CompositeTextSource
                    {
                        Kind = "ManagedRewriteMap",
                        RelativePath = relative,
                        TypeFullName = GetString(value, "TypeFullName"),
                        MethodName = GetString(value, "MethodName"),
                        MethodToken = token,
                        ILOffset = offset,
                        CallKind = "LdstrRewrite",
                    }, original,
                    [new CompositeTextPart { Position = 0, Kind = "Literal", Value = original }],
                    ClassifyManagedRewrite(name), "Exact");
                entry.LocalizedFormat = translation;
                entry.Status = "ExistingRule";
                entry.RuleId = ruleId;
                entry.Notes = GetString(value, "Note") ?? "Generated from existing managed IL rewrite map.";
                yield return entry;
            }
        }
    }

    private static CompositeCatalogDocument? LoadExisting(string rulesPath)
    {
        if (!File.Exists(rulesPath)) return null;
        try
        {
            return JsonSerializer.Deserialize<CompositeCatalogDocument>(File.ReadAllText(rulesPath),
                JsonOptions);
        }
        catch (JsonException exception)
        {
            throw new InvalidDataException($"Composite rules JSON is invalid: {rulesPath}", exception);
        }
    }

    private static CompositeTextEntry NewEntry(string entryId, CompositeTextSource source,
        string original, List<CompositeTextPart> parts, string classification, string confidence)
    {
        return new CompositeTextEntry
        {
            EntryPointId = entryId,
            Source = source,
            OriginalFormat = original,
            Classification = classification,
            Confidence = confidence,
            Parts = parts,
            StructuralFlags = GetStructuralFlags(original),
        };
    }

    private static bool TryGetCompositeCallKind(IMethod method, out string kind)
    {
        var declaring = method.DeclaringType?.FullName ?? "";
        var name = method.Name;
        if (declaring == "System.String" &&
            (name == "Concat" || name == "Format" || name == "Join"))
        {
            kind = "String." + name;
            return true;
        }
        if (declaring == "System.Text.StringBuilder" &&
            (name.StartsWith("Append", StringComparison.Ordinal) || name == "Insert"))
        {
            kind = "StringBuilder." + name;
            return true;
        }
        if (declaring == "AtTheGatesCommon.ns_Text.TextFormatter" &&
            (name == "Process" || name.StartsWith("Format", StringComparison.Ordinal)))
        {
            kind = "TextFormatter." + name;
            return true;
        }
        kind = "";
        return false;
    }

    private static List<CompositeTextPart> ExtractParts(IList<Instruction> instructions,
        int callIndex, IMethod target, string callKind)
    {
        if (callKind is "String.Format" or "StringBuilder.AppendFormat")
        {
            var format = FindFormatLiteral(instructions, callIndex);
            if (format is not null)
                return [new CompositeTextPart { Position = 0, Kind = "Literal", Value = format }];
        }
        var count = target.MethodSig?.Params.Count ?? 1;
        if (callKind.StartsWith("StringBuilder.", StringComparison.Ordinal)) count = Math.Max(1, count);
        count = Math.Clamp(count, 1, 8);
        var parts = new List<CompositeTextPart>();
        var examined = 0;
        for (var index = callIndex - 1; index >= 0 && parts.Count < count && examined < 32;
             index--, examined++)
        {
            var instruction = instructions[index];
            if (instruction.OpCode == OpCodes.Ldstr)
            {
                parts.Add(new CompositeTextPart { Kind = "Literal", Value = (string)instruction.Operand });
                continue;
            }
            if (IsTransparentStackInstruction(instruction)) continue;
            if (instruction.OpCode.FlowControl is FlowControl.Branch or FlowControl.Cond_Branch or
                FlowControl.Return or FlowControl.Throw) break;
            parts.Add(new CompositeTextPart { Kind = "Argument", Value = "" });
        }
        parts.Reverse();
        if (parts.Count == 0) parts.Add(new CompositeTextPart { Kind = "Argument", Value = "" });
        for (var index = 0; index < parts.Count; index++) parts[index].Position = index;
        return parts;
    }

    private static bool IsTransparentStackInstruction(Instruction instruction) =>
        instruction.OpCode is var opcode && (opcode == OpCodes.Box || opcode == OpCodes.Castclass ||
            opcode == OpCodes.Conv_I || opcode == OpCodes.Conv_I4 || opcode == OpCodes.Conv_I8 ||
            opcode == OpCodes.Conv_R4 || opcode == OpCodes.Conv_R8 || opcode == OpCodes.Nop);

    private static string? FindFormatLiteral(IList<Instruction> instructions, int callIndex)
    {
        for (var index = callIndex - 1; index >= 0 && callIndex - index <= 24; index--)
        {
            var instruction = instructions[index];
            if (instruction.OpCode == OpCodes.Ldstr) return (string)instruction.Operand;
            if (instruction.OpCode.FlowControl is FlowControl.Branch or FlowControl.Cond_Branch or
                FlowControl.Return or FlowControl.Throw) break;
        }
        return null;
    }

    private static string BuildOriginalFormat(IEnumerable<CompositeTextPart> parts, string callKind)
    {
        var list = parts.ToList();
        if (callKind == "String.Join" && list.Count == 1 && list[0].Kind == "Literal")
            return list[0].Value + "{arg:0}";
        var builder = new StringBuilder();
        foreach (var part in list)
        {
            builder.Append(part.Kind == "Literal" ? part.Value : "{arg:" + part.Position + "}");
        }
        return builder.ToString();
    }

    private static string Classify(string original, string callKind)
    {
        if (callKind.StartsWith("TextFormatter.", StringComparison.Ordinal)) return "DisplayComposite";
        if (RichTextLink.IsMatch(original) || Placeholder.IsMatch(original) ||
            BracketToken.IsMatch(original) || original.Contains("{arg:", StringComparison.Ordinal) ||
            PipeDelimitedAlias.IsMatch(original)) return "DisplayComposite";
        if (callKind.StartsWith("String.", StringComparison.Ordinal) ||
            callKind.StartsWith("StringBuilder.", StringComparison.Ordinal)) return "DisplayComposite";
        if (original.Length == 0) return "Technical";
        return "DisplayComposite";
    }

    private static string ClassifyManagedRewrite(string mapName) =>
        mapName.Contains("common", StringComparison.OrdinalIgnoreCase) ||
        mapName.Contains("game", StringComparison.OrdinalIgnoreCase)
            ? "LogicSensitive" : "DisplaySafe";

    private static string EstimateConfidence(IEnumerable<CompositeTextPart> parts, string callKind)
    {
        var list = parts.ToList();
        if (callKind is "String.Format" or "StringBuilder.AppendFormat" &&
            list.Count == 1 && list[0].Kind == "Literal") return "Exact";
        return list.All(part => part.Kind == "Literal") ? "Exact" : "Partial";
    }

    private static bool LooksComposite(string value) =>
        Placeholder.IsMatch(value) || RichTextLink.IsMatch(value) || BracketToken.IsMatch(value) ||
        PipeDelimitedAlias.IsMatch(value) ||
        value.Contains("TEXT.", StringComparison.Ordinal) ||
        value.Contains(":PLURAL", StringComparison.Ordinal) ||
        value.Contains(":SINGULAR", StringComparison.Ordinal);

    private static bool IsRuntimeSafeFragment(string value)
    {
        if (string.IsNullOrWhiteSpace(value) ||
            value.IndexOfAny(['[', ']', '|']) >= 0)
            return false;
        return value.Any(character => (character >= 'A' && character <= 'Z') ||
            (character >= 'a' && character <= 'z'));
    }

    private static List<string> GetStructuralFlags(string value)
    {
        var flags = new List<string>();
        if (RichTextLink.IsMatch(value)) flags.Add("ConceptLink");
        if (ContainsLegacyBareConceptAlias(value)) flags.Add("LegacyConceptAlias");
        if (Placeholder.IsMatch(value)) flags.Add("Placeholder");
        if (BracketToken.IsMatch(value)) flags.Add("RichTextMarkup");
        if (PipeDelimitedAlias.IsMatch(value)) flags.Add("PluralAlias");
        if (value.Contains("[HOTKEY", StringComparison.Ordinal)) flags.Add("Hotkey");
        if (value.Contains("TEXT.", StringComparison.Ordinal)) flags.Add("RuntimeKey");
        return flags;
    }

    private static void ValidateStructure(string original, string localized, string entryPointId)
    {
        var originalKeys = GetConceptKeys(original)
            .OrderBy(value => value, StringComparer.Ordinal).ToArray();
        var localizedKeys = GetConceptKeys(localized)
            .OrderBy(value => value, StringComparer.Ordinal).ToArray();
        if (!originalKeys.SequenceEqual(localizedKeys, StringComparer.Ordinal))
            throw new InvalidDataException(
                $"Localized format changes concept-link keys for '{entryPointId}'.");
        var originalPlaceholders = Placeholder.Matches(original).Select(match => match.Value)
            .OrderBy(value => value, StringComparer.Ordinal).ToArray();
        var localizedPlaceholders = Placeholder.Matches(localized).Select(match => match.Value)
            .OrderBy(value => value, StringComparer.Ordinal).ToArray();
        if (!originalPlaceholders.SequenceEqual(localizedPlaceholders, StringComparer.Ordinal))
            throw new InvalidDataException(
                $"Localized format changes placeholders for '{entryPointId}'.");
        var originalProtectedTags = GetProtectedTagSignatures(original)
            .OrderBy(value => value, StringComparer.Ordinal).ToArray();
        var localizedProtectedTags = GetProtectedTagSignatures(localized)
            .OrderBy(value => value, StringComparer.Ordinal).ToArray();
        if (!originalProtectedTags.SequenceEqual(localizedProtectedTags, StringComparer.Ordinal))
            throw new InvalidDataException(
                $"Localized format changes markup or hotkeys for '{entryPointId}'.");
        if (ContainsFormattingTag(original) && HasBalancedFormattingTags(original) &&
            !HasBalancedFormattingTags(localized))
            throw new InvalidDataException(
                $"Localized format has invalid FONT/COLOR nesting for '{entryPointId}'.");
    }

    private static IEnumerable<string> GetProtectedTagSignatures(string value)
    {
        foreach (Match match in BracketToken.Matches(value))
        {
            var token = match.Value;
            if (RichTextLink.IsMatch(token)) continue;
            var content = token[1..^1];
            if (LegacyBareConceptAliases.ContainsKey(content)) continue;
            if (TryGetPluralSelectorSignature(content, out var signature))
            {
                yield return signature;
                continue;
            }
            yield return "raw:" + token;
        }
    }

    private static IEnumerable<string> GetConceptKeys(string value)
    {
        foreach (Match match in RichTextLink.Matches(value))
        {
            var key = match.Groups[1].Value;
            if (!NonConceptDisplayKeys.Contains(key)) yield return key;
        }
        foreach (Match match in BracketToken.Matches(value))
        {
            var content = match.Value[1..^1];
            if (LegacyBareConceptAliases.TryGetValue(content, out var key))
                yield return key;
        }
    }

    private static bool ContainsLegacyBareConceptAlias(string value) =>
        BracketToken.Matches(value).Cast<Match>()
            .Any(match => LegacyBareConceptAliases.ContainsKey(match.Value[1..^1]));

    private static bool TryGetPluralSelectorSignature(string content, out string signature)
    {
        signature = "";
        var parts = content.Split('|');
        if (parts.Length < 2 || !parts[^1].StartsWith("###:", StringComparison.Ordinal))
            return false;
        if (parts.Take(parts.Length - 1).Any(part => part.Contains(':') || part.Contains('?')))
            return false;
        signature = $"plural:{parts.Length - 1}:{parts[^1]}";
        return true;
    }

    private static bool HasBalancedFormattingTags(string value)
    {
        var stack = new Stack<string>();
        foreach (Match match in BracketToken.Matches(value))
        {
            var content = match.Value[1..^1];
            if (content.StartsWith("/", StringComparison.Ordinal))
            {
                var closing = content[1..];
                if (closing is not ("FONT" or "COLOR")) continue;
                if (stack.Count == 0 || !StringComparer.Ordinal.Equals(stack.Pop(), closing))
                    return false;
                continue;
            }
            var separator = content.IndexOf(':');
            var opening = separator >= 0 ? content[..separator] : content;
            if (opening is "FONT" or "COLOR") stack.Push(opening);
        }
        return stack.Count == 0;
    }

    private static bool ContainsFormattingTag(string value) => BracketToken.Matches(value)
        .Select(match => match.Value[1..^1])
        .Any(content => content is "FONT" or "COLOR" or "/FONT" or "/COLOR" ||
            content.StartsWith("FONT:", StringComparison.Ordinal) ||
            content.StartsWith("COLOR:", StringComparison.Ordinal));

    private static IEnumerable<XmlValue> ReadXmlValues(string path)
    {
        var document = XDocument.Load(path, LoadOptions.PreserveWhitespace);
        foreach (var element in document.Descendants())
        {
            if (!element.HasElements && !string.IsNullOrEmpty(element.Value))
                yield return new XmlValue(GetXPath(element), element.Value);
            foreach (var attribute in element.Attributes().Where(attribute =>
                         !string.IsNullOrEmpty(attribute.Value)))
                yield return new XmlValue(GetXPath(attribute), attribute.Value);
        }
    }

    private static string GetXPath(XObject item)
    {
        if (item is XAttribute attribute)
            return GetXPath(attribute.Parent!) + "/@" + attribute.Name.LocalName;
        var element = (XElement)item;
        var parents = element.AncestorsAndSelf().Reverse().ToArray();
        var parts = new List<string>(parents.Length);
        foreach (var current in parents)
        {
            var index = current.Parent is null ? 1 : current.Parent.Elements(current.Name)
                .TakeWhile(sibling => sibling != current).Count() + 1;
            parts.Add(current.Name.LocalName + "[" + index + "]");
        }
        return "/" + string.Join("/", parts);
    }

    private static string GetPatchXmlPath(string root, string sourcePath)
    {
        var sourceRoot = Path.Combine(root, "source");
        var relative = Path.GetRelativePath(sourceRoot, sourcePath);
        if (StringComparer.OrdinalIgnoreCase.Equals(relative, "English.original.xml"))
            return Path.Combine(root, "patch", "Content", "Text", "English.xml");
        var patchRelative = relative.Replace(".original.xml", ".xml", StringComparison.OrdinalIgnoreCase);
        return Path.Combine(root, "patch", "Content", patchRelative);
    }

    private static JsonDocument OpenJson(string path) => JsonDocument.Parse(File.ReadAllText(path),
        new JsonDocumentOptions { AllowTrailingCommas = true, CommentHandling = JsonCommentHandling.Skip });

    private static bool TryGetString(JsonElement value, string name, out string result)
    {
        result = "";
        if (!value.TryGetProperty(name, out var property) ||
            property.ValueKind != JsonValueKind.String) return false;
        result = property.GetString() ?? "";
        return true;
    }

    private static string? GetString(JsonElement value, string name) =>
        value.TryGetProperty(name, out var property) && property.ValueKind == JsonValueKind.String
            ? property.GetString() : null;

    private static string RelativePath(string root, string path) =>
        Path.GetRelativePath(root, path).Replace('\\', '/');

    private static string ShortHash(string value)
    {
        var hash = SHA256.HashData(Encoding.UTF8.GetBytes(value));
        return Convert.ToHexString(hash).Substring(0, 16).ToLowerInvariant();
    }

    private static string AppendNote(string? existing, string additional) =>
        string.IsNullOrWhiteSpace(existing) ? additional : existing + " " + additional;

    private sealed record XmlValue(string XPath, string Value);

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        PropertyNameCaseInsensitive = true,
    };
}
