using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text;

namespace AtG.RuntimeText
{
    internal sealed class RuntimeGlyphWarmsetEntry
    {
        public int Priority;
        public string FontName;
        public float Size;
        public bool Bold;
        public string Characters;
        public string ScenarioIds;
    }

    internal static class RuntimeGlyphWarmsetCatalog
    {
        public const int Version = 1;

        public static IList<RuntimeGlyphWarmsetEntry> Load(TextReader reader)
        {
            if (reader == null) throw new ArgumentNullException("reader");
            var entries = new List<RuntimeGlyphWarmsetEntry>();
            string line;
            var lineNumber = 0;
            while ((line = reader.ReadLine()) != null)
            {
                lineNumber++;
                if (line.Length == 0 || line[0] == '#') continue;
                var fields = line.Split('\t');
                if (fields.Length != 7 || fields[0] != "W")
                    throw new InvalidDataException("Invalid runtime glyph warmset record at line " + lineNumber + ".");
                int priority;
                float size;
                if (!int.TryParse(fields[1], NumberStyles.Integer, CultureInfo.InvariantCulture,
                        out priority) || priority < 0 || priority > 2)
                    throw new InvalidDataException("Invalid warmset priority at line " + lineNumber + ".");
                if (!float.TryParse(fields[3], NumberStyles.Float, CultureInfo.InvariantCulture,
                        out size) || size <= 0f)
                    throw new InvalidDataException("Invalid warmset font size at line " + lineNumber + ".");
                if (fields[4] != "0" && fields[4] != "1")
                    throw new InvalidDataException("Invalid warmset bold flag at line " + lineNumber + ".");
                var characters = Decode(fields[5]);
                var seen = new HashSet<char>();
                for (var index = 0; index < characters.Length; index++)
                {
                    var character = characters[index];
                    if (!CjkText.RequiresDynamicGlyph(character) || !seen.Add(character))
                        throw new InvalidDataException(
                            "Warmset characters must be unique dynamic BMP glyphs at line " + lineNumber + ".");
                }
                entries.Add(new RuntimeGlyphWarmsetEntry
                {
                    Priority = priority,
                    FontName = Decode(fields[2]),
                    Size = size,
                    Bold = fields[4] == "1",
                    Characters = characters,
                    ScenarioIds = fields[6],
                });
            }
            return entries;
        }

        private static string Decode(string value)
        {
            try
            {
                return Encoding.UTF8.GetString(Convert.FromBase64String(value));
            }
            catch (FormatException ex)
            {
                throw new InvalidDataException("Warmset field is not valid Base64.", ex);
            }
        }
    }
}
