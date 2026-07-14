using Microsoft.Data.Sqlite;

namespace AtG.Catalog;

public sealed class CatalogDatabase : IDisposable
{
    private readonly SqliteConnection connection;

    private CatalogDatabase(string path)
    {
        var fullPath = Path.GetFullPath(path);
        Directory.CreateDirectory(Path.GetDirectoryName(fullPath)!);
        connection = new SqliteConnection(new SqliteConnectionStringBuilder
        {
            DataSource = fullPath,
            Mode = SqliteOpenMode.ReadWriteCreate,
            Cache = SqliteCacheMode.Shared,
        }.ToString());
        connection.Open();
        Execute("PRAGMA foreign_keys = ON;");
        Execute("PRAGMA journal_mode = WAL;");
    }

    public static CatalogDatabase Open(string path) => new(path);

    public void Initialize()
    {
        Execute(
            """
            CREATE TABLE IF NOT EXISTS SemanticGroup (
                Id INTEGER PRIMARY KEY,
                NormalizedText TEXT NOT NULL UNIQUE,
                RepresentativeOriginal TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS SourceOccurrence (
                Id INTEGER PRIMARY KEY,
                SemanticGroupId INTEGER NOT NULL REFERENCES SemanticGroup(Id) ON DELETE CASCADE,
                SourceFile TEXT NOT NULL,
                Kind TEXT NOT NULL,
                Original TEXT NOT NULL,
                Translation TEXT NOT NULL DEFAULT '',
                Status TEXT NOT NULL DEFAULT '',
                ReviewState TEXT NOT NULL DEFAULT '',
                ReasonCode TEXT NOT NULL DEFAULT '',
                Safety TEXT NOT NULL DEFAULT '',
                Notes TEXT NOT NULL DEFAULT '',
                Locators TEXT NOT NULL DEFAULT ''
            );
            CREATE TABLE IF NOT EXISTS TranslationBinding (
                Id INTEGER PRIMARY KEY,
                SemanticGroupId INTEGER NOT NULL UNIQUE REFERENCES SemanticGroup(Id) ON DELETE CASCADE,
                Translation TEXT NOT NULL,
                Status TEXT NOT NULL,
                Safety TEXT NOT NULL DEFAULT '',
                PatchMethod TEXT NOT NULL DEFAULT '',
                Notes TEXT NOT NULL DEFAULT ''
            );
            CREATE TABLE IF NOT EXISTS Evidence (
                Id INTEGER PRIMARY KEY,
                SemanticGroupId INTEGER NULL REFERENCES SemanticGroup(Id) ON DELETE CASCADE,
                SourceOccurrenceId INTEGER NULL REFERENCES SourceOccurrence(Id) ON DELETE CASCADE,
                Kind TEXT NOT NULL,
                Reference TEXT NOT NULL,
                Details TEXT NOT NULL DEFAULT '',
                CreatedUtc TEXT NOT NULL
            );
            CREATE INDEX IF NOT EXISTS IX_SourceOccurrence_SourceFile ON SourceOccurrence(SourceFile);
            CREATE INDEX IF NOT EXISTS IX_SourceOccurrence_Kind ON SourceOccurrence(Kind);
            CREATE INDEX IF NOT EXISTS IX_SourceOccurrence_Status ON SourceOccurrence(Status);
            CREATE INDEX IF NOT EXISTS IX_SourceOccurrence_SemanticGroupId ON SourceOccurrence(SemanticGroupId);
            CREATE INDEX IF NOT EXISTS IX_TranslationBinding_Status ON TranslationBinding(Status);
            CREATE INDEX IF NOT EXISTS IX_Evidence_SemanticGroupId ON Evidence(SemanticGroupId);
            CREATE INDEX IF NOT EXISTS IX_Evidence_SourceOccurrenceId ON Evidence(SourceOccurrenceId);
            CREATE INDEX IF NOT EXISTS IX_Evidence_Reference ON Evidence(Reference);
            """);
    }

    public SourceOccurrence AddOccurrence(SourceOccurrenceInput input)
    {
        using var transaction = connection.BeginTransaction();
        var result = AddOccurrence(input, transaction);
        transaction.Commit();
        return result;
    }

    internal SourceOccurrence AddOccurrence(SourceOccurrenceInput input, SqliteTransaction transaction)
    {
        var groupId = GetOrCreateSemanticGroup(input.Original, transaction);
        using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText =
            """
            INSERT INTO SourceOccurrence
                (SemanticGroupId, SourceFile, Kind, Original, Translation, Status, ReviewState, ReasonCode, Safety, Notes, Locators)
            VALUES
                ($group, $source, $kind, $original, $translation, $status, $review, $reason, $safety, $notes, $locators);
            SELECT last_insert_rowid();
            """;
        command.Parameters.AddWithValue("$group", groupId);
        command.Parameters.AddWithValue("$source", input.SourceFile);
        command.Parameters.AddWithValue("$kind", input.Kind);
        command.Parameters.AddWithValue("$original", input.Original);
        command.Parameters.AddWithValue("$translation", input.Translation);
        command.Parameters.AddWithValue("$status", input.Status);
        command.Parameters.AddWithValue("$review", input.ReviewState);
        command.Parameters.AddWithValue("$reason", input.ReasonCode);
        command.Parameters.AddWithValue("$safety", input.Safety);
        command.Parameters.AddWithValue("$notes", input.Notes);
        command.Parameters.AddWithValue("$locators", input.Locators);
        var id = (long)(command.ExecuteScalar() ?? throw new InvalidOperationException("Source occurrence insert returned no id."));
        return new SourceOccurrence(id, groupId, input.SourceFile, input.Kind, input.Original, input.Translation, input.Status, input.ReviewState, input.ReasonCode, input.Safety, input.Notes, input.Locators);
    }

    public void UpsertTranslation(TranslationBindingInput input)
    {
        using var command = connection.CreateCommand();
        command.CommandText =
            """
            INSERT INTO TranslationBinding (SemanticGroupId, Translation, Status, Safety, PatchMethod, Notes)
            VALUES ($group, $translation, $status, $safety, $method, $notes)
            ON CONFLICT(SemanticGroupId) DO UPDATE SET
                Translation = excluded.Translation,
                Status = excluded.Status,
                Safety = excluded.Safety,
                PatchMethod = excluded.PatchMethod,
                Notes = excluded.Notes;
            """;
        command.Parameters.AddWithValue("$group", input.SemanticGroupId);
        command.Parameters.AddWithValue("$translation", input.Translation);
        command.Parameters.AddWithValue("$status", input.Status);
        command.Parameters.AddWithValue("$safety", input.Safety);
        command.Parameters.AddWithValue("$method", input.PatchMethod);
        command.Parameters.AddWithValue("$notes", input.Notes);
        command.ExecuteNonQuery();
    }

    public TranslationBinding GetTranslation(long semanticGroupId)
    {
        using var command = connection.CreateCommand();
        command.CommandText = "SELECT Id, SemanticGroupId, Translation, Status, Safety, PatchMethod, Notes FROM TranslationBinding WHERE SemanticGroupId = $group;";
        command.Parameters.AddWithValue("$group", semanticGroupId);
        using var reader = command.ExecuteReader();
        if (!reader.Read()) throw new KeyNotFoundException($"No translation binding exists for semantic group {semanticGroupId}.");
        return new TranslationBinding(reader.GetInt64(0), reader.GetInt64(1), reader.GetString(2), reader.GetString(3), reader.GetString(4), reader.GetString(5), reader.GetString(6));
    }

    public Evidence AddEvidence(EvidenceInput input)
    {
        var createdUtc = DateTimeOffset.UtcNow.ToString("O");
        using var command = connection.CreateCommand();
        command.CommandText =
            """
            INSERT INTO Evidence (SemanticGroupId, SourceOccurrenceId, Kind, Reference, Details, CreatedUtc)
            VALUES ($group, $occurrence, $kind, $reference, $details, $created);
            SELECT last_insert_rowid();
            """;
        command.Parameters.AddWithValue("$group", (object?)input.SemanticGroupId ?? DBNull.Value);
        command.Parameters.AddWithValue("$occurrence", (object?)input.SourceOccurrenceId ?? DBNull.Value);
        command.Parameters.AddWithValue("$kind", input.Kind);
        command.Parameters.AddWithValue("$reference", input.Reference);
        command.Parameters.AddWithValue("$details", input.Details);
        command.Parameters.AddWithValue("$created", createdUtc);
        var id = (long)(command.ExecuteScalar() ?? throw new InvalidOperationException("Evidence insert returned no id."));
        return new Evidence(id, input.SemanticGroupId, input.SourceOccurrenceId, input.Kind, input.Reference, input.Details, createdUtc);
    }

    public IReadOnlyList<Evidence> GetEvidence(long semanticGroupId)
    {
        using var command = connection.CreateCommand();
        command.CommandText = "SELECT Id, SemanticGroupId, SourceOccurrenceId, Kind, Reference, Details, CreatedUtc FROM Evidence WHERE SemanticGroupId = $group ORDER BY Id;";
        command.Parameters.AddWithValue("$group", semanticGroupId);
        using var reader = command.ExecuteReader();
        var items = new List<Evidence>();
        while (reader.Read())
        {
            items.Add(new Evidence(
                reader.GetInt64(0),
                reader.IsDBNull(1) ? null : reader.GetInt64(1),
                reader.IsDBNull(2) ? null : reader.GetInt64(2),
                reader.GetString(3), reader.GetString(4), reader.GetString(5), reader.GetString(6)));
        }
        return items;
    }

    public IReadOnlyList<SourceOccurrence> ReadOccurrences()
    {
        using var command = connection.CreateCommand();
        command.CommandText =
            """
            SELECT Id, SemanticGroupId, SourceFile, Kind, Original, Translation, Status, ReviewState, ReasonCode, Safety, Notes, Locators
            FROM SourceOccurrence ORDER BY Id;
            """;
        using var reader = command.ExecuteReader();
        var items = new List<SourceOccurrence>();
        while (reader.Read())
        {
            items.Add(new SourceOccurrence(
                reader.GetInt64(0), reader.GetInt64(1), reader.GetString(2), reader.GetString(3), reader.GetString(4), reader.GetString(5),
                reader.GetString(6), reader.GetString(7), reader.GetString(8), reader.GetString(9), reader.GetString(10), reader.GetString(11)));
        }
        return items;
    }

    public IReadOnlyList<SourceOccurrence> SearchOccurrences(string text, int limit = 25, string? sourceContains = null)
    {
        if (string.IsNullOrWhiteSpace(text)) throw new ArgumentException("Search text must not be empty.", nameof(text));
        if (limit is < 1 or > 500) throw new ArgumentOutOfRangeException(nameof(limit), "Search limit must be between 1 and 500.");

        var exact = text.Trim();
        var normalized = TextNormalizer.Normalize(text);
        var literalPattern = $"%{EscapeLike(exact)}%";
        var normalizedPattern = $"%{EscapeLike(normalized)}%";
        var sourcePattern = string.IsNullOrWhiteSpace(sourceContains)
            ? "%"
            : $"%{EscapeLike(sourceContains.Trim())}%";
        using var command = connection.CreateCommand();
        command.CommandText =
            """
            SELECT occurrence.Id, occurrence.SemanticGroupId, occurrence.SourceFile, occurrence.Kind,
                   occurrence.Original, occurrence.Translation, occurrence.Status, occurrence.ReviewState,
                   occurrence.ReasonCode, occurrence.Safety, occurrence.Notes, occurrence.Locators
            FROM SourceOccurrence occurrence
            JOIN SemanticGroup semanticGroup ON semanticGroup.Id = occurrence.SemanticGroupId
            WHERE occurrence.SourceFile LIKE $source ESCAPE '\'
              AND (
                    occurrence.Original = $exact
                 OR semanticGroup.NormalizedText = $normalized
                 OR occurrence.Translation = $exact
                 OR occurrence.Original LIKE $literalPattern ESCAPE '\'
                 OR occurrence.Translation LIKE $literalPattern ESCAPE '\'
                 OR semanticGroup.NormalizedText LIKE $normalizedPattern ESCAPE '\')
            ORDER BY CASE
                WHEN occurrence.Original = $exact THEN 0
                WHEN semanticGroup.NormalizedText = $normalized THEN 1
                WHEN occurrence.Translation = $exact THEN 2
                WHEN occurrence.Original LIKE $literalPattern ESCAPE '\' THEN 3
                WHEN occurrence.Translation LIKE $literalPattern ESCAPE '\' THEN 4
                ELSE 5
            END,
            occurrence.SourceFile,
            occurrence.Id
            LIMIT $limit;
            """;
        command.Parameters.AddWithValue("$exact", exact);
        command.Parameters.AddWithValue("$normalized", normalized);
        command.Parameters.AddWithValue("$literalPattern", literalPattern);
        command.Parameters.AddWithValue("$normalizedPattern", normalizedPattern);
        command.Parameters.AddWithValue("$source", sourcePattern);
        command.Parameters.AddWithValue("$limit", limit);
        using var reader = command.ExecuteReader();
        var items = new List<SourceOccurrence>();
        while (reader.Read())
        {
            items.Add(new SourceOccurrence(
                reader.GetInt64(0), reader.GetInt64(1), reader.GetString(2), reader.GetString(3),
                reader.GetString(4), reader.GetString(5), reader.GetString(6), reader.GetString(7),
                reader.GetString(8), reader.GetString(9), reader.GetString(10), reader.GetString(11)));
        }
        return items;
    }

    public long CountOccurrences() => ScalarLong("SELECT COUNT(*) FROM SourceOccurrence;");
    public long CountSemanticGroups() => ScalarLong("SELECT COUNT(*) FROM SemanticGroup;");

    internal SqliteTransaction BeginTransaction() => connection.BeginTransaction();

    internal void ResetForImport(SqliteTransaction transaction)
    {
        // Source rows are generated and replaceable. Semantic knowledge is not:
        // keep group-level translations and evidence across catalog rebuilds.
        Execute("DELETE FROM SourceOccurrence;", transaction);
    }

    internal void FinishImport(SqliteTransaction transaction)
    {
        Execute(
            """
            DELETE FROM SemanticGroup
            WHERE NOT EXISTS (
                SELECT 1 FROM SourceOccurrence occurrence
                WHERE occurrence.SemanticGroupId = SemanticGroup.Id)
              AND NOT EXISTS (
                SELECT 1 FROM TranslationBinding binding
                WHERE binding.SemanticGroupId = SemanticGroup.Id)
              AND NOT EXISTS (
                SELECT 1 FROM Evidence evidence
                WHERE evidence.SemanticGroupId = SemanticGroup.Id);
            """, transaction);
    }

    private long GetOrCreateSemanticGroup(string original, SqliteTransaction transaction)
    {
        var normalized = TextNormalizer.Normalize(original);
        using (var insert = connection.CreateCommand())
        {
            insert.Transaction = transaction;
            insert.CommandText = "INSERT INTO SemanticGroup (NormalizedText, RepresentativeOriginal) VALUES ($normalized, $original) ON CONFLICT(NormalizedText) DO NOTHING;";
            insert.Parameters.AddWithValue("$normalized", normalized);
            insert.Parameters.AddWithValue("$original", original);
            insert.ExecuteNonQuery();
        }
        using var select = connection.CreateCommand();
        select.Transaction = transaction;
        select.CommandText = "SELECT Id FROM SemanticGroup WHERE NormalizedText = $normalized;";
        select.Parameters.AddWithValue("$normalized", normalized);
        return (long)(select.ExecuteScalar() ?? throw new InvalidOperationException("Semantic group lookup failed."));
    }

    private long ScalarLong(string sql)
    {
        using var command = connection.CreateCommand();
        command.CommandText = sql;
        return (long)(command.ExecuteScalar() ?? 0L);
    }

    private static string EscapeLike(string value) => value
        .Replace("\\", "\\\\", StringComparison.Ordinal)
        .Replace("%", "\\%", StringComparison.Ordinal)
        .Replace("_", "\\_", StringComparison.Ordinal);

    private void Execute(string sql, SqliteTransaction? transaction = null)
    {
        using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = sql;
        command.ExecuteNonQuery();
    }

    public void Dispose() => connection.Dispose();
}
