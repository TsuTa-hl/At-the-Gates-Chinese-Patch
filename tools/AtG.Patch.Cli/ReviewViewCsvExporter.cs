using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using AtG.Catalog;
using AtG.ManagedRewrite;

internal sealed record CompositeCsvExportResult(
    int EntryCount,
    int RuleCount,
    int KnownTextLocatorCount,
    int ResolvedKnownTextLocatorCount,
    int UnresolvedKnownTextLocatorCount,
    string OutputPath);

internal sealed record KnownTextCsvExportResult(
    int OccurrenceCount,
    int CompositeReferenceCount,
    string OutputPath);

internal sealed record TodoCsvExportResult(
    int KnownTextRows,
    int OpenTextRows,
    int ResolvedBlankRows,
    int SameAsOriginalRows,
    int UnreviewedCompositeEntries,
    int ReviewedNoSafeCompositeEntries,
    int ExistingCompositeEntries,
    string OutputPath);

internal static class ReviewViewCsvExporter
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
    };
    private static readonly string[] CompositeHeaders =
    [
        "RowKind", "EntryPointId", "SourceKind", "SourceRelativePath", "TypeFullName",
        "MethodName", "MethodToken", "ILOffset", "XPath", "CallKind",
        "OriginalFormat", "LocalizedFormat", "Classification", "Status",
        "RuleId", "RuleKind", "RuleStatus", "RuleDescription", "RuleSource",
        "AuditStatus", "RuleScope", "Confidence", "KnownTextReferenceStatus",
        "KnownTextLocatorCount", "KnownTextUnresolvedCount", "KnownTextExcludedLiteralCount",
        "KnownTextOccurrenceIds",
        "KnownTextSemanticGroupIds", "KnownTextReferencesJson",
        "KnownTextUnresolvedReferencesJson", "KnownTextReferenceExclusionsJson", "PartsJson",
        "StructuralFlags", "Notes", "Stale",
    ];
    private static readonly string[] KnownTextHeaders =
    [
        "SourceOccurrenceId", "SemanticGroupId", "SourceFile", "Kind", "Original", "Translation",
        "Status", "ReviewState", "ReasonCode", "Safety", "Notes", "Locators",
        "CompositeReferenceCount", "CompositeEntryPointIds", "CompositeReferencesJson",
    ];
    private static readonly string[] TodoHeaders =
    [
        "RowKind", "TodoId", "QueueState", "CategoryId", "CategoryTitle",
        "RecommendedAction", "SourceOccurrenceId", "SourceFile", "SourceKind",
        "Kind", "Original", "Translation", "Status", "ReviewState",
        "ReasonCode", "Safety", "Notes", "Locators", "Route", "EntryPointId",
        "RuleId", "AuditStatus", "RuleScope", "Confidence", "CompositeLocator",
        "StructuralFlags", "CompositeReferenceCount", "CompositeReferencesJson",
        "KnownTextReferenceStatus", "KnownTextReferencesJson",
        "KnownTextUnresolvedReferencesJson", "KnownTextReferenceExclusionsJson", "PartsJson",
    ];

    public static CompositeCsvExportResult ExportComposite(string databasePath, string rulesPath,
        string outputPath)
    {
        var document = LoadComposite(rulesPath);
        var rules = document.Rules.ToDictionary(rule => rule.RuleId, StringComparer.Ordinal);
        using var database = CatalogDatabase.Open(databasePath);
        database.Initialize();
        var index = CompositeKnownTextIndex.Build(document.Entries, database.ReadOccurrences());
        outputPath = PrepareCsvOutput(outputPath);
        using var writer = CreateWriter(outputPath);
        WriteRow(writer, CompositeHeaders);

        foreach (var entry in document.Entries.OrderBy(item => item.EntryPointId, StringComparer.Ordinal))
        {
            var source = entry.Source ?? new CompositeTextSource();
            rules.TryGetValue(entry.RuleId ?? "", out var rule);
            var references = index.GetEntryLinks(entry.EntryPointId);
            var unresolved = index.GetEntryUnresolved(entry.EntryPointId);
            var exclusions = index.GetEntryExclusions(entry);
            WriteRow(writer,
            [
                "Entry",
                entry.EntryPointId,
                source.Kind,
                source.RelativePath,
                source.TypeFullName,
                source.MethodName,
                source.MethodToken,
                source.ILOffset?.ToString(CultureInfo.InvariantCulture),
                source.XPath,
                source.CallKind,
                entry.OriginalFormat,
                entry.LocalizedFormat,
                entry.Classification,
                entry.Status,
                entry.RuleId,
                rule?.Kind,
                rule?.Status,
                rule?.Description,
                rule?.Source,
                entry.AuditStatus,
                entry.RuleScope,
                entry.Confidence,
                index.GetEntryStatus(entry),
                index.GetEntryLocatorCount(entry).ToString(CultureInfo.InvariantCulture),
                unresolved.Count.ToString(CultureInfo.InvariantCulture),
                exclusions.Count.ToString(CultureInfo.InvariantCulture),
                string.Join(";", references.Select(link => link.SourceOccurrenceId)
                    .Distinct().Order()),
                string.Join(";", references.Select(link => link.SemanticGroupId)
                    .Distinct().Order()),
                SerializeKnownTextLinks(references),
                SerializeUnresolvedReferences(unresolved),
                SerializeReferenceExclusions(exclusions),
                JsonSerializer.Serialize(entry.Parts ?? [], JsonOptions),
                string.Join("; ", entry.StructuralFlags ?? []),
                entry.Notes,
                entry.Stale.ToString(CultureInfo.InvariantCulture),
            ]);
        }

        foreach (var rule in document.Rules.OrderBy(item => item.RuleId, StringComparer.Ordinal))
        {
            var ruleRow = new string?[CompositeHeaders.Length];
            ruleRow[0] = "Rule";
            ruleRow[1] = rule.EntryPointId;
            ruleRow[14] = rule.RuleId;
            ruleRow[15] = rule.Kind;
            ruleRow[16] = rule.Status;
            ruleRow[17] = rule.Description;
            ruleRow[18] = rule.Source;
            WriteRow(writer, ruleRow);
        }

        var locatorCount = document.Entries.Sum(entry => index.GetEntryLocatorCount(entry));
        var resolvedPartCount = document.Entries.Sum(entry => entry.Parts.Count(part =>
            part.KnownTextReference is not null && index.GetEntryLinks(entry.EntryPointId)
                .Any(link => link.PartPosition == part.Position)));
        return new CompositeCsvExportResult(document.Entries.Count, document.Rules.Count,
            locatorCount, resolvedPartCount, locatorCount - resolvedPartCount, outputPath);
    }

    public static KnownTextCsvExportResult ExportKnownTexts(string databasePath, string rulesPath,
        string outputPath)
    {
        var document = LoadComposite(rulesPath);
        using var database = CatalogDatabase.Open(databasePath);
        database.Initialize();
        var rows = database.ReadOccurrences();
        var index = CompositeKnownTextIndex.Build(document.Entries, rows);
        outputPath = PrepareCsvOutput(outputPath);
        using var writer = CreateWriter(outputPath);
        WriteRow(writer, KnownTextHeaders);
        foreach (var row in rows)
        {
            var references = index.GetOccurrenceLinks(row.Id);
            WriteRow(writer,
            [
                row.Id.ToString(CultureInfo.InvariantCulture),
                row.SemanticGroupId.ToString(CultureInfo.InvariantCulture),
                row.SourceFile,
                row.Kind,
                row.Original,
                row.Translation,
                row.Status,
                row.ReviewState,
                row.ReasonCode,
                row.Safety,
                row.Notes,
                row.Locators,
                references.Count.ToString(CultureInfo.InvariantCulture),
                string.Join(";", references.Select(link => link.EntryPointId)
                    .Distinct(StringComparer.Ordinal).Order(StringComparer.Ordinal)),
                SerializeCompositeLinks(references),
            ]);
        }
        return new KnownTextCsvExportResult(rows.Count, index.Links.Count, outputPath);
    }

    public static TodoCsvExportResult ExportTodo(string databasePath, string rulesPath,
        string outputPath)
    {
        var document = LoadComposite(rulesPath);
        var entries = document.Entries;
        using var database = CatalogDatabase.Open(databasePath);
        database.Initialize();
        var rows = database.ReadOccurrences();
        var compositeKnownTextIndex = CompositeKnownTextIndex.Build(entries, rows);
        var openRows = rows.Where(IsOpenTextRow).ToArray();
        var resolvedBlankRows = rows.Count(row =>
            string.Equals(row.Status, "Translated", StringComparison.Ordinal) &&
            string.IsNullOrWhiteSpace(row.Translation));
        var sameAsOriginalRows = rows.Count(row =>
            string.Equals(row.Status, "Translated", StringComparison.Ordinal) &&
            !string.IsNullOrWhiteSpace(row.Translation) &&
            string.Equals(row.Original, row.Translation, StringComparison.Ordinal));
        var unreviewedComposites = entries.Where(entry =>
            string.Equals(entry.AuditStatus, "Unreviewed", StringComparison.Ordinal)).ToArray();
        var reviewedNoSafeComposites = entries.Where(entry =>
            string.Equals(entry.AuditStatus, "ReviewedNoSafeRule", StringComparison.Ordinal)).ToArray();
        var existingComposites = entries.Count(entry =>
            string.Equals(entry.AuditStatus, "Localized", StringComparison.Ordinal));

        outputPath = PrepareCsvOutput(outputPath);
        using var writer = CreateWriter(outputPath);
        WriteRow(writer, TodoHeaders);

        foreach (var row in openRows
                     .Select(row => new
                     {
                         Row = row,
                         Category = GetTextCategory(row),
                         TodoId = "TXT-" + ShortHash(string.Join("\n",
                             row.SourceFile, row.Kind, row.Original, row.Locators)),
                         CompositeReferences = compositeKnownTextIndex.GetOccurrenceLinks(row.Id),
                     })
                     .OrderBy(item => CategoryRank(item.Category.Id))
                     .ThenBy(item => item.Row.SourceFile, StringComparer.Ordinal)
                     .ThenBy(item => item.Row.Kind, StringComparer.Ordinal)
                     .ThenBy(item => item.Row.Original, StringComparer.Ordinal)
                     .ThenBy(item => item.Row.Locators, StringComparer.Ordinal))
        {
            WriteRow(writer,
            [
                "Text",
                row.TodoId,
                row.Row.Status,
                row.Category.Id,
                row.Category.Title,
                row.Category.Action,
                row.Row.Id.ToString(CultureInfo.InvariantCulture),
                row.Row.SourceFile,
                "SourceOccurrence",
                row.Row.Kind,
                row.Row.Original,
                row.Row.Translation,
                row.Row.Status,
                row.Row.ReviewState,
                row.Row.ReasonCode,
                row.Row.Safety,
                row.Row.Notes,
                row.Row.Locators,
                GetCompositeRoute(row.Row, row.CompositeReferences),
                "", "", "", "", "", "", "",
                row.CompositeReferences.Count.ToString(CultureInfo.InvariantCulture),
                SerializeCompositeLinks(row.CompositeReferences),
                "",
                "",
                "",
                "",
                "",
            ]);
        }

        foreach (var entry in unreviewedComposites.OrderBy(item => item.EntryPointId, StringComparer.Ordinal))
        {
            WriteCompositeTodoRow(writer, entry, compositeKnownTextIndex,
                new TodoCategory(
                    "CompositeUnreviewed",
                    "未审查拼接入口",
                    "按完整格式审查；先复用安全统一译法，再考虑入口专用规则。"));
        }
        foreach (var entry in reviewedNoSafeComposites.OrderBy(item => item.EntryPointId, StringComparer.Ordinal))
        {
            WriteCompositeTodoRow(writer, entry, compositeKnownTextIndex,
                new TodoCategory(
                    "CompositeReviewedNoSafeRule",
                    "已审查但未添加规则的拼接入口",
                    "保留审计标记；取得新的界面或调用方证据前，不要重新作为未审查入口处理。"));
        }

        return new TodoCsvExportResult(
            rows.Count,
            openRows.Length,
            resolvedBlankRows,
            sameAsOriginalRows,
            unreviewedComposites.Length,
            reviewedNoSafeComposites.Length,
            existingComposites,
            outputPath);
    }

    private static CompositeCatalogDocument LoadComposite(string rulesPath)
    {
        rulesPath = Path.GetFullPath(rulesPath);
        if (!File.Exists(rulesPath))
            throw new FileNotFoundException("Composite rule source was not found.", rulesPath);
        try
        {
            var document = JsonSerializer.Deserialize<CompositeCatalogDocument>(
                File.ReadAllText(rulesPath), JsonOptions)
                ?? throw new InvalidDataException($"Composite rule source was empty: {rulesPath}");
            CompositeTextCatalog.Validate(document.Entries, document.Rules);
            return document;
        }
        catch (JsonException exception)
        {
            throw new InvalidDataException($"Composite rule source is invalid: {rulesPath}", exception);
        }
    }

    private static bool IsOpenTextRow(SourceOccurrence row) =>
        row.Status is "UntranslatedDiscovered" or "UntranslatedCandidate" or "RejectedTrial" &&
        !string.IsNullOrWhiteSpace(row.Original);

    private static TodoCategory GetTextCategory(SourceOccurrence row)
    {
        if (string.Equals(row.Status, "RejectedTrial", StringComparison.Ordinal))
            return new TodoCategory("RejectedTrial", "已拒绝的试探项（不自动重试）",
                "保留失败原因；仅在补丁机制或隔离回归条件改变后，使用单条试验重新评估。");
        if (string.Equals(row.ReasonCode, "TechnicalInternal", StringComparison.Ordinal) ||
            string.Equals(row.Kind, "Technical", StringComparison.Ordinal))
            return new TodoCategory("Technical", "技术、诊断或内部字符串（默认不汉化）",
                "不作为普通本地化项处理；只有证明该文本实际显示给玩家时，才回到目录做精确补丁。");
        if (string.Equals(row.ReasonCode, "FragmentOrToken", StringComparison.Ordinal) ||
            string.Equals(row.Safety, "DoNotPatchHere", StringComparison.Ordinal) ||
            string.Equals(row.Kind, "TextKeyReference", StringComparison.Ordinal))
            return new TodoCategory("CompositeOrKey", "拼接片段、标签或文本键（先处理完整入口）",
                "不得单词级替换；先解析文本键或复用对应组合入口的完整格式规则。");
        if (string.Equals(row.ReasonCode, "LogicSensitive", StringComparison.Ordinal) ||
            row.Safety is "ManualOnly" or "Skip" ||
            row.Kind is "FactionNameOrLabel" or "LogicSensitive" or "TodoPlaceholder")
            return new TodoCategory("LogicSensitive", "逻辑敏感或需人工确认的显示文本",
                "先进行小批隔离修改与目标回归；不得作为批量字符串替换对象。");
        if (row.Kind is "SafeUI" or "TooltipFragment" or "UI IL rewrite" or
            "UI byte/string map" or "UI in-place IL string")
            return new TodoCategory("DirectUi", "可优先定位的 UI / 提示候选",
                "优先从精确 ldstr/IL 位置或既有 UI 映射补丁处理；仍需保留富文本和占位符结构。");
        if (row.Kind is "CommonDisplayCandidate" or "Common IL rewrite" or
            "Common byte/string map" or "Common verified offset")
            return new TodoCategory("CommonCandidate", "Common 显示候选（高风险）",
                "先确认不是逻辑分支或序列化值；只做小批量、可回退的精确显示补丁。");
        if (row.Kind is "Review" or "Game EXE IL rewrite" or "ElfTools IL rewrite")
            return new TodoCategory("ManagedReview", "托管程序集显示候选（需按方法复核）",
                "按程序集、方法和 IL 偏移审查；优先完整模板或最终显示入口。");
        return new TodoCategory("Unclassified", "未分类的潜在显示文本",
            "先使用 SQLite 和源定位确认显示路径，再选择 XML、配置节点或精确程序集补丁。");
    }

    private static int CategoryRank(string id) => id switch
    {
        "DirectUi" => 0,
        "ManagedReview" => 1,
        "CommonCandidate" => 2,
        "CompositeOrKey" => 3,
        "LogicSensitive" => 4,
        "RejectedTrial" => 5,
        "Technical" => 6,
        _ => 7,
    };

    private static string GetCompositeRoute(SourceOccurrence row,
        IReadOnlyList<CompositeKnownTextLink> references)
    {
        if (string.Equals(row.Kind, "TextKeyReference", StringComparison.Ordinal))
            return "这是解析键；先在 SQLite/English.xml 找到最终显示文本，不能直接改配置键。";
        if (references.Count == 0)
            return "未建立精确 Composite 引用；按本行精确来源和分类处理。";
        var entryPoints = references.Select(link => link.EntryPointId)
            .Distinct(StringComparer.Ordinal).Order(StringComparer.Ordinal).ToArray();
        var parts = references.Select(link => link.PartPosition).Distinct().Order().ToArray();
        return "精确关联组合入口：" + string.Join(", ", entryPoints) +
            "；片段位置：" + string.Join(", ", parts);
    }

    private static void WriteCompositeTodoRow(TextWriter writer, CompositeTextEntry entry,
        CompositeKnownTextIndex index, TodoCategory category)
    {
        var source = entry.Source ?? new CompositeTextSource();
        var references = index.GetEntryLinks(entry.EntryPointId);
        var unresolved = index.GetEntryUnresolved(entry.EntryPointId);
        var exclusions = index.GetEntryExclusions(entry);
        WriteRow(writer,
        [
            "Composite",
            "CMP-" + ShortHash(entry.EntryPointId),
            entry.AuditStatus,
            category.Id,
            category.Title,
            category.Action,
            "",
            source.RelativePath,
            source.Kind,
            entry.Classification,
            entry.OriginalFormat,
            entry.LocalizedFormat,
            entry.Status,
            "",
            "",
            "",
            entry.Notes,
            "",
            "",
            entry.EntryPointId,
            entry.RuleId,
            entry.AuditStatus,
            entry.RuleScope,
            entry.Confidence,
            CompositeLocator(source),
            string.Join("; ", entry.StructuralFlags ?? []),
            "",
            "",
            index.GetEntryStatus(entry),
            SerializeKnownTextLinks(references),
            SerializeUnresolvedReferences(unresolved),
            SerializeReferenceExclusions(exclusions),
            JsonSerializer.Serialize(entry.Parts ?? [], JsonOptions),
        ]);
    }

    private static string CompositeLocator(CompositeTextSource source)
    {
        if (!string.IsNullOrWhiteSpace(source.MethodToken))
            return source.MethodToken + "@" +
                (source.ILOffset?.ToString(CultureInfo.InvariantCulture) ?? "");
        return source.XPath ?? "";
    }

    private static string SerializeKnownTextLinks(IEnumerable<CompositeKnownTextLink> links) =>
        JsonSerializer.Serialize(links.OrderBy(link => link.PartPosition)
            .ThenBy(link => link.SourceOccurrenceId)
            .Select(link => new
            {
                link.PartPosition,
                link.PartValue,
                link.LocatorKind,
                link.TextMatch,
                link.SourceOccurrenceId,
                link.SemanticGroupId,
                link.SourceFile,
                link.Original,
                link.Translation,
                link.Status,
                link.ReviewState,
                link.Safety,
                link.Locators,
            }), JsonOptions);

    private static string SerializeCompositeLinks(IEnumerable<CompositeKnownTextLink> links) =>
        JsonSerializer.Serialize(links.OrderBy(link => link.EntryPointId, StringComparer.Ordinal)
            .ThenBy(link => link.PartPosition)
            .Select(link => new
            {
                link.EntryPointId,
                link.PartPosition,
                link.PartValue,
                link.LocatorKind,
                link.TextMatch,
            }), JsonOptions);

    private static string SerializeUnresolvedReferences(
        IEnumerable<CompositeKnownTextUnresolvedReference> unresolved) =>
        JsonSerializer.Serialize(unresolved.OrderBy(item => item.PartPosition)
            .Select(item => new
            {
                item.PartPosition,
                item.PartValue,
                item.Reason,
            }), JsonOptions);

    private static string SerializeReferenceExclusions(
        IEnumerable<CompositeKnownTextReferenceExclusion> exclusions) =>
        JsonSerializer.Serialize(exclusions.OrderBy(item => item.PartPosition)
            .Select(item => new
            {
                item.PartPosition,
                item.PartValue,
                item.Reason,
            }), JsonOptions);

    private static string ShortHash(string value) =>
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(value))).Substring(0, 12);

    private static string PrepareCsvOutput(string outputPath)
    {
        outputPath = Path.GetFullPath(outputPath);
        if (!string.Equals(Path.GetExtension(outputPath), ".csv",
                StringComparison.OrdinalIgnoreCase))
            throw new ArgumentException($"Review view output must be a .csv file: {outputPath}");
        Directory.CreateDirectory(Path.GetDirectoryName(outputPath)!);
        return outputPath;
    }

    private static StreamWriter CreateWriter(string outputPath) =>
        new(outputPath, append: false, new UTF8Encoding(encoderShouldEmitUTF8Identifier: true));

    private static void WriteRow(TextWriter writer, IEnumerable<string?> values) =>
        writer.WriteLine(string.Join(',', values.Select(value =>
            "\"" + (value ?? "").Replace("\"", "\"\"", StringComparison.Ordinal) + "\"")));

    private sealed record TodoCategory(string Id, string Title, string Action);
}
