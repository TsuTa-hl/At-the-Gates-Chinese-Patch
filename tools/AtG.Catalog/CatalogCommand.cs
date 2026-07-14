using System.Text.Json;

namespace AtG.Catalog;

public static class CatalogCommand
{
    public static int Run(string[] args, TextWriter output, TextWriter error)
    {
        try
        {
            if (args.Length == 0 || args[0] is "-h" or "--help" or "help")
            {
                WriteUsage(output);
                return args.Length == 0 ? 2 : 0;
            }

            var root = FindRepositoryRoot(Environment.CurrentDirectory);
            var options = ParseOptions(args.Skip(1).ToArray());
            var databasePath = Get(options, "database", Path.Combine(root, ".cache", "atg-catalog.sqlite"));
            return args[0].ToLowerInvariant() switch
            {
                "import" => Import(databasePath, Get(options, "input", Path.Combine(root, "docs", "review", "known-texts.csv")), !options.ContainsKey("append"), output),
                "export" => Export(databasePath,
                    Get(options, "csv", Path.Combine(root, "docs", "review", "known-texts.csv")),
                    Get(options, "markdown", Path.Combine(root, "docs", "review", "known-texts.md")), output),
                "rebuild" => Rebuild(databasePath,
                    Get(options, "input", Path.Combine(root, "docs", "review", "known-texts.csv")),
                    Get(options, "csv", Path.Combine(root, "docs", "review", "known-texts.csv")),
                    Get(options, "markdown", Path.Combine(root, "docs", "review", "known-texts.md")), output),
                "search" => Search(databasePath,
                    Get(options, "text", ""),
                    GetOptional(options, "source"),
                    GetLimit(options), output),
                "stats" => Stats(databasePath, output),
                _ => UnknownCommand(args[0], error),
            };
        }
        catch (Exception ex)
        {
            error.WriteLine($"Catalog command failed: {ex.Message}");
            return 1;
        }
    }

    private static int Import(string databasePath, string inputPath, bool replaceExisting, TextWriter output)
    {
        using var database = CatalogDatabase.Open(databasePath);
        database.Initialize();
        var result = new ReviewImporter(database).Import(inputPath, replaceExisting);
        output.WriteLine($"Imported {result.ImportedOccurrences} source occurrences into {result.SemanticGroups} semantic groups.");
        output.WriteLine($"Catalog: {Path.GetFullPath(databasePath)}");
        return 0;
    }

    private static int Export(string databasePath, string csvPath, string markdownPath, TextWriter output)
    {
        using var database = CatalogDatabase.Open(databasePath);
        database.Initialize();
        var exporter = new ReviewExporter(database);
        exporter.ExportMarkdown(markdownPath);
        exporter.ExportCsv(csvPath);
        output.WriteLine($"Exported {database.CountOccurrences()} source occurrences.");
        output.WriteLine($"CSV: {Path.GetFullPath(csvPath)}");
        output.WriteLine($"Markdown: {Path.GetFullPath(markdownPath)}");
        return 0;
    }

    private static int Rebuild(string databasePath, string inputPath, string csvPath, string markdownPath, TextWriter output)
    {
        var temporaryInput = Path.GetFullPath(inputPath);
        var csvOutput = Path.GetFullPath(csvPath);
        string? snapshot = null;
        if (string.Equals(temporaryInput, csvOutput, StringComparison.OrdinalIgnoreCase))
        {
            snapshot = Path.Combine(Path.GetTempPath(), $"atg-known-texts-{Guid.NewGuid():N}.csv");
            File.Copy(temporaryInput, snapshot);
            temporaryInput = snapshot;
        }
        try
        {
            var importExit = Import(databasePath, temporaryInput, replaceExisting: true, output);
            return importExit == 0 ? Export(databasePath, csvPath, markdownPath, output) : importExit;
        }
        finally
        {
            if (snapshot is not null) File.Delete(snapshot);
        }
    }

    private static int Stats(string databasePath, TextWriter output)
    {
        using var database = CatalogDatabase.Open(databasePath);
        database.Initialize();
        output.WriteLine($"Source occurrences: {database.CountOccurrences()}");
        output.WriteLine($"Semantic groups: {database.CountSemanticGroups()}");
        return 0;
    }

    private static int Search(string databasePath, string text, string? source, int limit, TextWriter output)
    {
        if (string.IsNullOrWhiteSpace(text)) throw new ArgumentException("--text requires a non-empty value.");
        using var database = CatalogDatabase.Open(databasePath);
        database.Initialize();
        var matches = database.SearchOccurrences(text, limit, source);
        output.WriteLine(JsonSerializer.Serialize(matches, new JsonSerializerOptions { WriteIndented = true }));
        return 0;
    }

    private static Dictionary<string, string?> ParseOptions(string[] args)
    {
        var result = new Dictionary<string, string?>(StringComparer.OrdinalIgnoreCase);
        for (var index = 0; index < args.Length; index++)
        {
            var argument = args[index];
            if (!argument.StartsWith("--", StringComparison.Ordinal))
                throw new ArgumentException($"Unexpected argument '{argument}'. Options must start with --.");
            var name = argument[2..];
            if (name.Length == 0) throw new ArgumentException("Empty option name.");
            if (index + 1 < args.Length && !args[index + 1].StartsWith("--", StringComparison.Ordinal))
                result[name] = args[++index];
            else result[name] = null;
        }
        return result;
    }

    private static string Get(IReadOnlyDictionary<string, string?> options, string name, string fallback)
    {
        if (!options.TryGetValue(name, out var value)) return fallback;
        if (string.IsNullOrWhiteSpace(value)) throw new ArgumentException($"--{name} requires a value.");
        return value;
    }

    private static string? GetOptional(IReadOnlyDictionary<string, string?> options, string name)
    {
        if (!options.TryGetValue(name, out var value)) return null;
        if (string.IsNullOrWhiteSpace(value)) throw new ArgumentException($"--{name} requires a value.");
        return value;
    }

    private static int GetLimit(IReadOnlyDictionary<string, string?> options)
    {
        var value = GetOptional(options, "limit");
        if (value is null) return 25;
        if (!int.TryParse(value, out var limit) || limit is < 1 or > 500)
            throw new ArgumentException("--limit must be an integer between 1 and 500.");
        return limit;
    }

    private static string FindRepositoryRoot(string start)
    {
        for (var directory = new DirectoryInfo(Path.GetFullPath(start)); directory is not null; directory = directory.Parent)
        {
            if (Directory.Exists(Path.Combine(directory.FullName, "docs", "review"))) return directory.FullName;
        }
        return Path.GetFullPath(start);
    }

    private static int UnknownCommand(string command, TextWriter error)
    {
        error.WriteLine($"Unknown catalog command '{command}'. Use --help for usage.");
        return 2;
    }

    private static void WriteUsage(TextWriter output)
    {
        output.WriteLine("AtG.Catalog - generated localization catalog");
        output.WriteLine("  import  [--input <known-texts.csv>] [--database <catalog.sqlite>] [--append]");
        output.WriteLine("  export  [--database <catalog.sqlite>] [--csv <known-texts.csv>] [--markdown <known-texts.md>]");
        output.WriteLine("  rebuild [all import/export options]");
        output.WriteLine("  search  --text <text> [--source <source-file-fragment>] [--limit <1-500>] [--database <catalog.sqlite>]");
        output.WriteLine("  stats   [--database <catalog.sqlite>]");
        output.WriteLine("Defaults use .cache/atg-catalog.sqlite and docs/review generated views under the repository root.");
    }
}
