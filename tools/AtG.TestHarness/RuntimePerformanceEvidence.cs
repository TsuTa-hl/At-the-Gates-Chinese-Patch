using System.Globalization;
using System.Text;
using System.Text.Json;

namespace AtG.TestHarness;

public static class RuntimePerformanceEvidence
{
    public static IReadOnlyList<string> SplitBySession(
        string tracePath,
        string outputDirectory,
        IReadOnlyList<SessionResult> sessions)
    {
        if (sessions.Count == 0) return [];
        var resolvedTrace = Path.GetFullPath(tracePath);
        if (!File.Exists(resolvedTrace))
            throw new FileNotFoundException(
                "Runtime performance evidence was not produced.", resolvedTrace);

        var records = File.ReadLines(resolvedTrace, Encoding.UTF8)
            .Where(line => !string.IsNullOrWhiteSpace(line))
            .Select(line => new TimedRecord(ParseTime(line), line.TrimStart('\uFEFF')))
            .ToArray();
        Directory.CreateDirectory(outputDirectory);
        var outputs = new List<string>(sessions.Count);
        for (var index = 0; index < sessions.Count; index++)
        {
            var session = sessions[index];
            var end = session.StartedAtUtc.AddMilliseconds(session.DurationMs);
            var selected = records
                .Where(record =>
                    record.TimeUtc >= session.StartedAtUtc &&
                    record.TimeUtc <= end)
                .Select(record => record.Line)
                .ToArray();
            if (selected.Length == 0)
                throw new InvalidDataException(
                    $"No runtime performance frames overlap pass {index + 1}.");
            var output = Path.GetFullPath(Path.Combine(
                outputDirectory, $"runtime-performance.pass-{index + 1}.jsonl"));
            File.WriteAllLines(output, selected, new UTF8Encoding(false));
            outputs.Add(output);
        }
        return outputs;
    }

    private static DateTime ParseTime(string line)
    {
        try
        {
            using var document = JsonDocument.Parse(line.TrimStart('\uFEFF'));
            var value = document.RootElement.GetProperty("time").GetString();
            return DateTime.Parse(
                value ?? throw new InvalidDataException(
                    "Runtime performance entry has an empty time."),
                CultureInfo.InvariantCulture,
                DateTimeStyles.RoundtripKind).ToUniversalTime();
        }
        catch (Exception ex) when (ex is JsonException or FormatException or KeyNotFoundException)
        {
            throw new InvalidDataException(
                "Runtime performance entry has an invalid time.", ex);
        }
    }

    private sealed record TimedRecord(DateTime TimeUtc, string Line);
}
