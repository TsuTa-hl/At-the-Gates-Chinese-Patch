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

    private static void EnsureParent(string path) => Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path))!);
}
