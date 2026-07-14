using AtG.Catalog;
using Microsoft.Data.Sqlite;

var tests = new (string Name, Action Body)[]
{
    ("duplicate source occurrences survive CSV import", DuplicateOccurrencesSurvive),
    ("normalized source text shares one semantic group", SemanticGroupingWorks),
    ("translation status and evidence round-trip", StatusAndEvidenceRoundTrip),
    ("CSV parser accepts reordered multiline review columns", ReorderedMultilineCsvImports),
    ("generated review views preserve occurrence rows", GeneratedViewsPreserveOccurrences),
    ("replacement import preserves semantic bindings and group evidence", ReplacementImportPreservesKnowledge),
    ("generated markdown remains an AI-friendly source index", GeneratedMarkdownIsAiFriendly),
    ("catalog search prioritizes exact and normalized text", CatalogSearchPrioritizesMatches),
    ("CLI imports and exports generated catalog views", CliImportsAndExports),
    ("schema contains required tables and indexes", SchemaContainsRequiredObjects),
};

var failed = 0;
foreach (var test in tests)
{
    try
    {
        test.Body();
        Console.WriteLine($"PASS {test.Name}");
    }
    catch (Exception ex)
    {
        failed++;
        Console.Error.WriteLine($"FAIL {test.Name}: {ex.Message}");
    }
}

return failed == 0 ? 0 : 1;

static void DuplicateOccurrencesSurvive()
{
    using var fixture = new CatalogFixture();
    var csv = fixture.WriteCsv(
        ReviewCsv.Header,
        ReviewCsv.Row("source\\A.dll", "SafeUI", "Same text", "同一文本", "Translated", "Reviewed", "", "DisplaySafe", "first", "Method=A"),
        ReviewCsv.Row("source\\A.dll", "SafeUI", "Same text", "同一文本", "Translated", "Reviewed", "", "DisplaySafe", "second", "Method=B"));

    using var database = CatalogDatabase.Open(fixture.DatabasePath);
    database.Initialize();
    var result = new ReviewImporter(database).Import(csv, replaceExisting: true);

    Assert.Equal(2L, result.ImportedOccurrences);
    Assert.Equal(2L, database.CountOccurrences());
    Assert.Equal(1L, database.CountSemanticGroups());
}

static void SemanticGroupingWorks()
{
    using var fixture = new CatalogFixture();
    using var database = CatalogDatabase.Open(fixture.DatabasePath);
    database.Initialize();

    var first = database.AddOccurrence(new SourceOccurrenceInput("a.xml", "DisplaySafe", "  Build\r\n  Camp  ", "建造营地", "Translated", "Reviewed", "", "DisplaySafe", "", "node=1"));
    var second = database.AddOccurrence(new SourceOccurrenceInput("b.xml", "DisplaySafe", "Build Camp", "建造营地", "Translated", "Reviewed", "", "DisplaySafe", "", "node=2"));

    Assert.Equal(first.SemanticGroupId, second.SemanticGroupId);
    Assert.Equal(2L, database.CountOccurrences());
    Assert.Equal(1L, database.CountSemanticGroups());
}

static void StatusAndEvidenceRoundTrip()
{
    using var fixture = new CatalogFixture();
    long groupId;
    long occurrenceId;
    using (var database = CatalogDatabase.Open(fixture.DatabasePath))
    {
        database.Initialize();
        var occurrence = database.AddOccurrence(new SourceOccurrenceInput("ui.dll", "DisplayComposite", "Clan {0}", "氏族 {0}", "Trial", "Pending", "", "DisplayComposite", "", "token=1"));
        groupId = occurrence.SemanticGroupId;
        occurrenceId = occurrence.Id;
        database.UpsertTranslation(new TranslationBindingInput(groupId, "氏族 {0}", "Accepted", "DisplayComposite", "RuntimeTemplate", "verified"));
        database.AddEvidence(new EvidenceInput(groupId, occurrenceId, "BlackBox", "scenario:clan-list", "passed"));
    }

    using (var reopened = CatalogDatabase.Open(fixture.DatabasePath))
    {
        var binding = reopened.GetTranslation(groupId);
        var evidence = reopened.GetEvidence(groupId).Single();
        Assert.Equal("Accepted", binding.Status);
        Assert.Equal("RuntimeTemplate", binding.PatchMethod);
        Assert.Equal("scenario:clan-list", evidence.Reference);
        Assert.Equal(occurrenceId, evidence.SourceOccurrenceId);
    }
}

static void ReorderedMultilineCsvImports()
{
    using var fixture = new CatalogFixture();
    var path = Path.Combine(fixture.Root, "reordered.csv");
    File.WriteAllText(path,
        "\"Original\",\"SourceFile\",\"Locators\",\"Notes\",\"Kind\",\"Translation\",\"Status\",\"ReviewState\",\"ReasonCode\",\"Safety\"\r\n" +
        "\"Line one\r\nLine two, quoted \"\"value\"\"\",\"x.dll\",\"token=7\",\"note, with comma\",\"SafeUI\",\"第一行\r\n第二行\",\"Translated\",\"Reviewed\",\"\",\"DisplaySafe\"\r\n",
        new System.Text.UTF8Encoding(encoderShouldEmitUTF8Identifier: true));

    using var database = CatalogDatabase.Open(fixture.DatabasePath);
    database.Initialize();
    new ReviewImporter(database).Import(path, replaceExisting: true);
    var occurrence = database.ReadOccurrences().Single();

    Assert.Equal("Line one\r\nLine two, quoted \"value\"", occurrence.Original);
    Assert.Equal("note, with comma", occurrence.Notes);
    Assert.Equal("第一行\r\n第二行", occurrence.Translation);
}

static void GeneratedViewsPreserveOccurrences()
{
    using var fixture = new CatalogFixture();
    using var database = CatalogDatabase.Open(fixture.DatabasePath);
    database.Initialize();
    database.AddOccurrence(new SourceOccurrenceInput("a.dll", "SafeUI", "Duplicate", "重复", "Translated", "Reviewed", "", "DisplaySafe", "one", "token=1"));
    database.AddOccurrence(new SourceOccurrenceInput("a.dll", "SafeUI", "Duplicate", "重复", "Translated", "Reviewed", "", "DisplaySafe", "two", "token=2"));

    var csv = Path.Combine(fixture.Root, "known-texts.csv");
    var markdown = Path.Combine(fixture.Root, "known-texts.md");
    new ReviewExporter(database).ExportCsv(csv);
    new ReviewExporter(database).ExportMarkdown(markdown);

    Assert.Equal(3, File.ReadAllLines(csv).Length);
    Assert.Contains("token=1", File.ReadAllText(markdown));
    Assert.Contains("token=2", File.ReadAllText(markdown));
}

static void ReplacementImportPreservesKnowledge()
{
    using var fixture = new CatalogFixture();
    long groupId;
    using (var database = CatalogDatabase.Open(fixture.DatabasePath))
    {
        database.Initialize();
        var occurrence = database.AddOccurrence(new SourceOccurrenceInput(
            "old.dll", "DisplaySafe", "Stable text", "稳定文本", "Translated",
            "Translated", "", "DisplaySafe", "old", "token=1"));
        groupId = occurrence.SemanticGroupId;
        database.UpsertTranslation(new TranslationBindingInput(
            groupId, "稳定文本", "Accepted", "DisplaySafe", "IlRewrite", "keep"));
        database.AddEvidence(new EvidenceInput(
            groupId, null, "BlackBox", "scenario:stable", "passed"));
    }

    var replacement = fixture.WriteCsv(
        ReviewCsv.Header,
        ReviewCsv.Row("new.dll", "DisplaySafe", "Stable text", "稳定文本", "Translated", "Translated", "", "DisplaySafe", "new", "token=2"));
    using var reopened = CatalogDatabase.Open(fixture.DatabasePath);
    reopened.Initialize();
    new ReviewImporter(reopened).Import(replacement, replaceExisting: true);

    var occurrenceAfter = reopened.ReadOccurrences().Single();
    Assert.Equal(groupId, occurrenceAfter.SemanticGroupId);
    Assert.Equal("new.dll", occurrenceAfter.SourceFile);
    Assert.Equal("token=2", occurrenceAfter.Locators);
    Assert.Equal("Accepted", reopened.GetTranslation(groupId).Status);
    Assert.Equal("scenario:stable", reopened.GetEvidence(groupId).Single().Reference);
}

static void GeneratedMarkdownIsAiFriendly()
{
    using var fixture = new CatalogFixture();
    using var database = CatalogDatabase.Open(fixture.DatabasePath);
    database.Initialize();
    database.AddOccurrence(new SourceOccurrenceInput(
        "source\\A.dll", "DisplaySafe", "Line one\nLine two", "第一行\n第二行",
        "Translated", "Translated", "", "DisplaySafe", "note", "token=7"));

    var markdown = Path.Combine(fixture.Root, "known-texts.md");
    new ReviewExporter(database).ExportMarkdown(markdown);
    var text = File.ReadAllText(markdown);

    Assert.Contains("# Known Texts AI Index", text);
    Assert.Contains("Query the SQLite catalog first", text);
    Assert.Contains("Use this Markdown for grouped source context", text);
    Assert.DoesNotContain("Use this Markdown first for agent/workflow text matching", text);
    Assert.Contains("## Source: source\\A.dll", text);
    Assert.Contains("SourceOccurrenceId:", text);
    Assert.Contains("SemanticGroupId:", text);
    Assert.Contains("Original:\n```text\nLine one\nLine two\n```", text.Replace("\r\n", "\n"));
    Assert.Contains("Translation:\n```text\n第一行\n第二行\n```", text.Replace("\r\n", "\n"));
}

static void CatalogSearchPrioritizesMatches()
{
    using var fixture = new CatalogFixture();
    using (var database = CatalogDatabase.Open(fixture.DatabasePath))
    {
        database.Initialize();
        database.AddOccurrence(new SourceOccurrenceInput(
            "source\\UI.dll", "DisplaySafe", "A Clan joins", "一个氏族加入", "Translated",
            "Translated", "", "DisplaySafe", "composite", "token=2"));
        database.AddOccurrence(new SourceOccurrenceInput(
            "source\\Common.dll", "DisplaySafe", "Clan", "氏族", "Translated",
            "Translated", "", "DisplaySafe", "exact", "token=1"));
        database.AddOccurrence(new SourceOccurrenceInput(
            "source\\Other.dll", "Technical", "Unrelated", "无关", "Skipped",
            "Skipped", "TechnicalInternal", "Technical", "", "token=3"));

        var matches = database.SearchOccurrences("  Clan  ", 10, null);
        Assert.Equal(2, matches.Count);
        Assert.Equal("Clan", matches[0].Original);
        Assert.Equal("A Clan joins", matches[1].Original);
    }

    var stdout = new StringWriter();
    var stderr = new StringWriter();
    var exit = CatalogCommand.Run(
        ["search", "--database", fixture.DatabasePath, "--text", "Clan", "--source", "Common", "--limit", "5"],
        stdout, stderr);
    Assert.Equal(0, exit);
    Assert.Contains("Common.dll", stdout.ToString());
    Assert.Contains("token=1", stdout.ToString());
    Assert.Equal(false, stdout.ToString().Contains("token=2", StringComparison.Ordinal));
    Assert.Equal(string.Empty, stderr.ToString());
}

static void CliImportsAndExports()
{
    using var fixture = new CatalogFixture();
    var input = fixture.WriteCsv(
        ReviewCsv.Header,
        ReviewCsv.Row("source\\A.dll", "SafeUI", "Hello", "你好", "Translated", "Reviewed", "", "DisplaySafe", "", "token=1"));
    var csv = Path.Combine(fixture.Root, "export", "known-texts.csv");
    var markdown = Path.Combine(fixture.Root, "export", "known-texts.md");
    var stdout = new StringWriter();
    var stderr = new StringWriter();

    var importExit = CatalogCommand.Run(["import", "--input", input, "--database", fixture.DatabasePath], stdout, stderr);
    var exportExit = CatalogCommand.Run(["export", "--database", fixture.DatabasePath, "--csv", csv, "--markdown", markdown], stdout, stderr);

    Assert.Equal(0, importExit);
    Assert.Equal(0, exportExit);
    Assert.Equal(true, File.Exists(fixture.DatabasePath));
    Assert.Equal(true, File.Exists(csv));
    Assert.Equal(true, File.Exists(markdown));
    Assert.Contains("Imported 1 source occurrences", stdout.ToString());
    Assert.Equal(string.Empty, stderr.ToString());
}

static void SchemaContainsRequiredObjects()
{
    using var fixture = new CatalogFixture();
    using (var database = CatalogDatabase.Open(fixture.DatabasePath)) database.Initialize();
    using var connection = new SqliteConnection($"Data Source={fixture.DatabasePath}");
    connection.Open();
    using var command = connection.CreateCommand();
    command.CommandText = "SELECT name FROM sqlite_master WHERE type IN ('table', 'index') ORDER BY name;";
    using var reader = command.ExecuteReader();
    var names = new List<string>();
    while (reader.Read()) names.Add(reader.GetString(0));

    foreach (var required in new[]
    {
        "SourceOccurrence", "SemanticGroup", "TranslationBinding", "Evidence",
        "IX_SourceOccurrence_SourceFile", "IX_SourceOccurrence_SemanticGroupId",
        "IX_TranslationBinding_Status", "IX_Evidence_Reference"
    }) Assert.Equal(true, names.Contains(required, StringComparer.Ordinal));
}

sealed class CatalogFixture : IDisposable
{
    public CatalogFixture()
    {
        Root = Path.Combine(Path.GetTempPath(), "AtG.Catalog.Tests", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(Root);
        DatabasePath = Path.Combine(Root, "catalog.sqlite");
    }

    public string Root { get; }
    public string DatabasePath { get; }

    public string WriteCsv(params string[] lines)
    {
        var path = Path.Combine(Root, "known-texts.csv");
        File.WriteAllText(path, string.Join("\r\n", lines) + "\r\n", new System.Text.UTF8Encoding(true));
        return path;
    }

    public void Dispose()
    {
        try { Directory.Delete(Root, recursive: true); } catch { }
    }
}

static class ReviewCsv
{
    public const string Header = "\"SourceFile\",\"Kind\",\"Original\",\"Translation\",\"Status\",\"ReviewState\",\"ReasonCode\",\"Safety\",\"Notes\",\"Locators\"";

    public static string Row(params string[] fields) => string.Join(",", fields.Select(Escape));

    private static string Escape(string value) => $"\"{value.Replace("\"", "\"\"")}\"";
}

static class Assert
{
    public static void Equal<T>(T expected, T actual)
    {
        if (!EqualityComparer<T>.Default.Equals(expected, actual))
            throw new InvalidOperationException($"Expected <{expected}> but got <{actual}>.");
    }

    public static void Contains(string expected, string actual)
    {
        if (!actual.Contains(expected, StringComparison.Ordinal))
            throw new InvalidOperationException($"Expected text to contain <{expected}>.");
    }

    public static void DoesNotContain(string unexpected, string actual)
    {
        if (actual.Contains(unexpected, StringComparison.Ordinal))
            throw new InvalidOperationException($"Expected text not to contain <{unexpected}>.");
    }
}
