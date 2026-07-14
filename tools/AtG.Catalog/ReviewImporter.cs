namespace AtG.Catalog;

public sealed class ReviewImporter(CatalogDatabase database)
{
    private static readonly string[] RequiredHeaders =
    [
        "SourceFile", "Kind", "Original", "Translation", "Status",
        "ReviewState", "ReasonCode", "Safety", "Notes", "Locators"
    ];

    public ImportResult Import(string csvPath, bool replaceExisting)
    {
        var records = CsvRecords.Read(csvPath).GetEnumerator();
        if (!records.MoveNext()) throw new InvalidDataException("Review CSV is empty.");
        var headers = records.Current
            .Select((name, index) => (Name: name.TrimStart('\uFEFF'), Index: index))
            .ToDictionary(item => item.Name, item => item.Index, StringComparer.OrdinalIgnoreCase);
        var missing = RequiredHeaders.Where(header => !headers.ContainsKey(header)).ToArray();
        if (missing.Length > 0) throw new InvalidDataException($"Review CSV is missing required columns: {string.Join(", ", missing)}.");

        long imported = 0;
        using var transaction = database.BeginTransaction();
        if (replaceExisting) database.ResetForImport(transaction);
        while (records.MoveNext())
        {
            var row = records.Current;
            string Get(string name)
            {
                var index = headers[name];
                if (index >= row.Length) throw new InvalidDataException($"CSV row {imported + 2} has no value for '{name}'.");
                return row[index];
            }
            database.AddOccurrence(new SourceOccurrenceInput(
                Get("SourceFile"), Get("Kind"), Get("Original"), Get("Translation"), Get("Status"),
                Get("ReviewState"), Get("ReasonCode"), Get("Safety"), Get("Notes"), Get("Locators")), transaction);
            imported++;
        }
        database.FinishImport(transaction);
        transaction.Commit();
        return new ImportResult(imported, database.CountSemanticGroups());
    }
}
