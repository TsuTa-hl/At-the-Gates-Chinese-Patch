using System.Text;

namespace AtG.Catalog;

public sealed class ReviewExporter(CatalogDatabase database)
{
    private static readonly string[] Headers =
    [
        "SourceFile", "Kind", "Original", "Translation", "Status",
        "ReviewState", "ReasonCode", "Safety", "Notes", "Locators"
    ];

    public void ExportCsv(string outputPath)
    {
        EnsureParent(outputPath);
        using var writer = new StreamWriter(outputPath, append: false, new UTF8Encoding(encoderShouldEmitUTF8Identifier: true));
        writer.WriteLine(string.Join(',', Headers.Select(CsvRecords.Escape)));
        foreach (var item in database.ReadOccurrences())
        {
            writer.WriteLine(string.Join(',', new[]
            {
                item.SourceFile, item.Kind, item.Original, item.Translation, item.Status,
                item.ReviewState, item.ReasonCode, item.Safety, item.Notes, item.Locators
            }.Select(CsvRecords.Escape)));
        }
    }

    public void ExportMarkdown(string outputPath)
    {
        EnsureParent(outputPath);
        using var writer = new StreamWriter(outputPath, append: false, new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
        var items = database.ReadOccurrences();
        var translated = items.Count(item => !string.IsNullOrWhiteSpace(item.Translation));
        var reviewCounts = items
            .GroupBy(item => item.ReviewState, StringComparer.Ordinal)
            .ToDictionary(group => group.Key, group => group.Count(), StringComparer.Ordinal);

        writer.WriteLine("# Known Texts AI Index");
        writer.WriteLine();
        writer.WriteLine("Generated from `.cache/atg-catalog.sqlite`; the database is the primary generated state store.");
        writer.WriteLine("Query the SQLite catalog first through `tools\\Invoke-AtGPatchCli.ps1` when matching screenshot text.");
        writer.WriteLine("Use this Markdown for grouped source context. Use `docs\\review\\known-texts.csv` for human spreadsheet review.");
        writer.WriteLine("Do not use normalized `Original` text from this file as an IL rewrite operand; use the exact DLL catalog `Value` with `MethodToken + ILOffset`.");
        writer.WriteLine();
        writer.WriteLine("## Summary");
        writer.WriteLine();
        writer.WriteLine($"- Rows: {items.Count}");
        writer.WriteLine($"- Translated rows: {translated}");
        writer.WriteLine($"- Untranslated rows: {items.Count - translated}");
        foreach (var state in new[] { "Translated", "NeedsTrial", "Skipped", "RecheckedSkipped", "Rejected" })
            writer.WriteLine($"- ReviewState {state}: {reviewCounts.GetValueOrDefault(state)}");

        string? source = null;
        var rowNumber = 0;
        foreach (var item in items)
        {
            rowNumber++;
            if (!string.Equals(source, item.SourceFile, StringComparison.Ordinal))
            {
                source = item.SourceFile;
                writer.WriteLine();
                writer.WriteLine($"## Source: {Inline(source)}");
            }
            writer.WriteLine();
            writer.WriteLine($"### KT{rowNumber:D6} | {Inline(item.ReviewState)} | {Inline(item.Kind)}");
            writer.WriteLine($"- SourceOccurrenceId: {item.Id}");
            writer.WriteLine($"- SemanticGroupId: {item.SemanticGroupId}");
            writer.WriteLine($"- Status: {Inline(item.Status)}");
            writer.WriteLine($"- ReasonCode: {Inline(item.ReasonCode)}");
            writer.WriteLine($"- Safety: {Inline(item.Safety)}");
            writer.WriteLine($"- Notes: {Inline(item.Notes)}");
            writer.WriteLine($"- Locators: {Inline(item.Locators)}");
            WriteTextBlock(writer, "Original", item.Original);
            WriteTextBlock(writer, "Translation", item.Translation);
        }
    }

    private static string Inline(string value) => value
        .Replace("\r\n", "\\n", StringComparison.Ordinal)
        .Replace("\n", "\\n", StringComparison.Ordinal)
        .Replace("\r", "\\n", StringComparison.Ordinal);

    private static void WriteTextBlock(TextWriter writer, string label, string value)
    {
        writer.WriteLine($"{label}:");
        writer.WriteLine("```text");
        if (value.Length > 0) writer.WriteLine(value);
        writer.WriteLine("```");
    }

    private static void EnsureParent(string path) => Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path))!);
}
