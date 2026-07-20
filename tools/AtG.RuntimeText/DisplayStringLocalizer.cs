using System;
using System.Collections.Generic;
using System.IO;
using System.Text;

namespace AtG.RuntimeText
{
    public static class DisplayStringLocalizer
    {
        private static readonly object Gate = new object();
        private static readonly Dictionary<string, string> ExactStrings =
            new Dictionary<string, string>(StringComparer.Ordinal);
        private static readonly Dictionary<string, string> PlainText =
            new Dictionary<string, string>(StringComparer.Ordinal);
        private static readonly Dictionary<string, string> PlainTextFragments =
            new Dictionary<string, string>(StringComparer.Ordinal);
        private static readonly Dictionary<string, Dictionary<string, string>> ConceptDisplay =
            new Dictionary<string, Dictionary<string, string>>(StringComparer.Ordinal);
        private static readonly HashSet<string> ConceptKeys =
            new HashSet<string>(StringComparer.Ordinal);
        private static bool DefaultLoadAttempted;

        public static void Register(string source, string translation)
        {
            RegisterValue(ExactStrings, source, translation, false);
        }

        public static void RegisterPlainText(string source, string translation)
        {
            ValidateDisplayValue(source, "source");
            ValidateDisplayValue(translation, "translation");
            lock (Gate) RegisterValue(PlainText, source, translation, true);
        }

        public static void RegisterPlainTextFragment(string source, string translation)
        {
            ValidateDisplayValue(source, "source");
            if (translation == null) throw new ArgumentNullException("translation");
            if (translation.IndexOf('[') >= 0 || translation.IndexOf(']') >= 0 ||
                translation.IndexOf('|') >= 0)
                throw new ArgumentException("Display text must not contain rich-text markup.", "translation");
            lock (Gate) RegisterValue(PlainTextFragments, source, translation, true);
        }

        public static void RegisterConceptKey(string conceptKey)
        {
            if (string.IsNullOrEmpty(conceptKey)) throw new ArgumentException("Concept key is required.", "conceptKey");
            lock (Gate) ConceptKeys.Add(conceptKey);
        }

        public static void RegisterConceptDisplay(string conceptKey, string source, string translation)
        {
            if (string.IsNullOrEmpty(conceptKey)) throw new ArgumentException("Concept key is required.", "conceptKey");
            ValidateDisplayValue(source, "source");
            ValidateDisplayValue(translation, "translation");
            lock (Gate)
            {
                ConceptKeys.Add(conceptKey);
                Dictionary<string, string> values;
                if (!ConceptDisplay.TryGetValue(conceptKey, out values))
                {
                    values = new Dictionary<string, string>(StringComparer.Ordinal);
                    ConceptDisplay.Add(conceptKey, values);
                }
                RegisterValue(values, source, translation, true);
            }
        }

        public static string LocalizeDisplayString(string value)
        {
            if (value == null) return null;
            EnsureDefaultLoaded();
            string translated;
            lock (Gate)
                return ExactStrings.TryGetValue(value, out translated) ? translated : value;
        }

        public static string LocalizeRichText(string value)
        {
            if (value == null) return null;
            EnsureDefaultLoaded();
            Dictionary<string, string> plain;
            Dictionary<string, string> fragments;
            Dictionary<string, Dictionary<string, string>> concepts;
            HashSet<string> keys;
            lock (Gate)
            {
                string exact;
                if (ExactStrings.TryGetValue(value, out exact)) return exact;
                plain = new Dictionary<string, string>(PlainText, StringComparer.Ordinal);
                fragments = new Dictionary<string, string>(PlainTextFragments, StringComparer.Ordinal);
                concepts = new Dictionary<string, Dictionary<string, string>>(StringComparer.Ordinal);
                foreach (var pair in ConceptDisplay)
                    concepts.Add(pair.Key,
                        new Dictionary<string, string>(pair.Value, StringComparer.Ordinal));
                keys = new HashSet<string>(ConceptKeys, StringComparer.Ordinal);
            }

            var nodes = RichTextAst.Parse(value, keys);
            var changed = false;
            var mapped = new List<RichNode>(nodes.Count);
            foreach (var node in nodes)
            {
                var text = node as PlainTextNode;
                if (text != null)
                {
                    string translated;
                    if (plain.TryGetValue(text.Text, out translated))
                    {
                        mapped.Add(new PlainTextNode(translated));
                        changed = true;
                    }
                    else
                    {
                        translated = ApplyPlainTextFragments(text.Text, fragments);
                        if (!StringComparer.Ordinal.Equals(translated, text.Text))
                        {
                            mapped.Add(new PlainTextNode(translated));
                            changed = true;
                        }
                        else mapped.Add(text);
                    }
                    continue;
                }

                var link = node as ConceptLinkNode;
                if (link != null)
                {
                    Dictionary<string, string> displays;
                    string translated;
                    if (concepts.TryGetValue(link.ConceptKey, out displays) &&
                        displays.TryGetValue(link.DisplayText, out translated))
                    {
                        mapped.Add(new ConceptLinkNode(translated, link.ConceptKey));
                        changed = true;
                    }
                    else mapped.Add(link);
                    continue;
                }
                mapped.Add(node);
            }
            return changed ? RichTextAst.Render(mapped) : value;
        }

        public static void Load(TextReader reader)
        {
            if (reader == null) throw new ArgumentNullException("reader");
            string line;
            var lineNumber = 0;
            while ((line = reader.ReadLine()) != null)
            {
                lineNumber++;
                if (line.Length == 0 || line[0] == '#') continue;
                var fields = line.Split('\t');
                try
                {
                    switch (fields[0])
                    {
                        case "K" when fields.Length == 2:
                            RegisterConceptKey(Decode(fields[1]));
                            break;
                        case "E" when fields.Length == 3:
                            Register(Decode(fields[1]), Decode(fields[2]));
                            break;
                        case "P" when fields.Length == 3:
                            RegisterPlainText(Decode(fields[1]), Decode(fields[2]));
                            break;
                        case "F" when fields.Length == 3:
                            RegisterPlainTextFragment(Decode(fields[1]), Decode(fields[2]));
                            break;
                        case "C" when fields.Length == 4:
                            RegisterConceptDisplay(Decode(fields[1]), Decode(fields[2]), Decode(fields[3]));
                            break;
                        default:
                            throw new InvalidDataException("Unknown runtime display-map record.");
                    }
                }
                catch (Exception ex)
                {
                    throw new InvalidDataException(
                        "Invalid runtime display-map record at line " + lineNumber + ".", ex);
                }
            }
        }

        internal static void ResetForTests()
        {
            lock (Gate)
            {
                ExactStrings.Clear();
                PlainText.Clear();
                PlainTextFragments.Clear();
                ConceptDisplay.Clear();
                ConceptKeys.Clear();
                DefaultLoadAttempted = false;
            }
        }

        private static void EnsureDefaultLoaded()
        {
            lock (Gate)
            {
                if (DefaultLoadAttempted) return;
                DefaultLoadAttempted = true;
                var path = Path.Combine(AppDomain.CurrentDomain.BaseDirectory,
                    "Content", "Text", "AtG.RuntimeText.tsv");
                if (!File.Exists(path)) return;
                try
                {
                    using (var reader = new StreamReader(path, Encoding.UTF8, true)) Load(reader);
                }
                catch (Exception ex)
                {
                    RuntimeTextTrace.Write("display-map-load-failed", path, null, ex);
                }
            }
        }

        private static string Decode(string value)
        {
            return Encoding.UTF8.GetString(Convert.FromBase64String(value));
        }

        private static string ApplyPlainTextFragments(string value, Dictionary<string, string> fragments)
        {
            if (value.Length == 0 || fragments.Count == 0) return value;
            var ordered = new List<KeyValuePair<string, string>>(fragments);
            ordered.Sort((left, right) =>
            {
                var length = right.Key.Length.CompareTo(left.Key.Length);
                return length != 0 ? length : StringComparer.Ordinal.Compare(left.Key, right.Key);
            });

            var builder = new StringBuilder(value.Length);
            var index = 0;
            while (index < value.Length)
            {
                KeyValuePair<string, string>? match = null;
                foreach (var entry in ordered)
                {
                    if (entry.Key.Length == 0) continue;
                    if (index + entry.Key.Length > value.Length) continue;
                    if (string.CompareOrdinal(value, index, entry.Key, 0, entry.Key.Length) == 0)
                    {
                        match = entry;
                        break;
                    }
                }

                if (match.HasValue)
                {
                    builder.Append(match.Value.Value);
                    index += match.Value.Key.Length;
                }
                else
                {
                    builder.Append(value[index]);
                    index++;
                }
            }
            return builder.ToString();
        }

        private static void RegisterValue(Dictionary<string, string> values,
            string source, string translation, bool gateAlreadyHeld)
        {
            if (source == null) throw new ArgumentNullException("source");
            if (translation == null) throw new ArgumentNullException("translation");
            if (!gateAlreadyHeld)
            {
                lock (Gate) RegisterValue(values, source, translation, true);
                return;
            }
            string existing;
            if (values.TryGetValue(source, out existing))
            {
                if (!StringComparer.Ordinal.Equals(existing, translation))
                    throw new InvalidOperationException("A different translation is already registered for this source text.");
                return;
            }
            values.Add(source, translation);
        }

        private static void ValidateDisplayValue(string value, string parameterName)
        {
            if (string.IsNullOrEmpty(value))
                throw new ArgumentException("Display text is required.", parameterName);
            if (value.IndexOf('[') >= 0 || value.IndexOf(']') >= 0 || value.IndexOf('|') >= 0)
                throw new ArgumentException("Display text must not contain rich-text markup.", parameterName);
        }
    }
}
