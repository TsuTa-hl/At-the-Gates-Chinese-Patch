using System.Text;

namespace AtG.Catalog;

internal static class CsvRecords
{
    public static IEnumerable<string[]> Read(string path)
    {
        using var reader = new StreamReader(path, Encoding.UTF8, detectEncodingFromByteOrderMarks: true);
        foreach (var record in Parse(reader)) yield return record;
    }

    public static IEnumerable<string[]> Parse(TextReader reader)
    {
        var record = new List<string>();
        var field = new StringBuilder();
        var quoted = false;
        var afterQuote = false;
        while (true)
        {
            var next = reader.Read();
            if (next < 0)
            {
                if (quoted) throw new InvalidDataException("CSV ended inside a quoted field.");
                if (field.Length > 0 || record.Count > 0)
                {
                    record.Add(field.ToString());
                    yield return record.ToArray();
                }
                yield break;
            }

            var ch = (char)next;
            if (quoted)
            {
                if (ch == '"')
                {
                    if (reader.Peek() == '"')
                    {
                        reader.Read();
                        field.Append('"');
                    }
                    else
                    {
                        quoted = false;
                        afterQuote = true;
                    }
                }
                else field.Append(ch);
                continue;
            }

            if (afterQuote && ch is not ',' and not '\r' and not '\n')
                throw new InvalidDataException($"Unexpected character '{ch}' after a closing CSV quote.");

            if (ch == '"' && field.Length == 0 && !afterQuote) quoted = true;
            else if (ch == ',')
            {
                record.Add(field.ToString());
                field.Clear();
                afterQuote = false;
            }
            else if (ch is '\r' or '\n')
            {
                if (ch == '\r' && reader.Peek() == '\n') reader.Read();
                record.Add(field.ToString());
                field.Clear();
                afterQuote = false;
                if (record.Count > 1 || record[0].Length > 0) yield return record.ToArray();
                record.Clear();
            }
            else field.Append(ch);
        }
    }

    public static string Escape(string value) => $"\"{value.Replace("\"", "\"\"")}\"";
}
