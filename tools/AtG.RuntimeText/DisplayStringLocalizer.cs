using System;
using System.Collections.Concurrent;
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
        private static readonly Dictionary<string, string> RichTextFragments =
            new Dictionary<string, string>(StringComparer.Ordinal);
        private static readonly Dictionary<string, string> Templates =
            new Dictionary<string, string>(StringComparer.Ordinal);
        private static readonly Dictionary<string, Dictionary<string, string>> ConceptDisplay =
            new Dictionary<string, Dictionary<string, string>>(StringComparer.Ordinal);
        private static readonly HashSet<string> ConceptKeys =
            new HashSet<string>(StringComparer.Ordinal);
        private static readonly Dictionary<string, string> GameMonthNames =
            new Dictionary<string, string>(StringComparer.Ordinal)
            {
                { "January", "1月" }, { "February", "2月" }, { "March", "3月" },
                { "April", "4月" }, { "May", "5月" }, { "June", "6月" },
                { "July", "7月" }, { "August", "8月" }, { "September", "9月" },
                { "October", "10月" }, { "November", "11月" }, { "December", "12月" },
            };
        private static volatile BoundedLocalizationCache ResultCache =
            new BoundedLocalizationCache(4096, 2 * 1024 * 1024);
        private static volatile LocalizationSnapshot Snapshot;
        private static bool DefaultLoadAttempted;

        private sealed class LocalizationSnapshot
        {
            public Dictionary<string, string> Exact;
            public Dictionary<string, string> Plain;
            public Dictionary<char, KeyValuePair<string, string>[]> FragmentsByFirstCharacter;
            public Dictionary<char, KeyValuePair<string, string>[]> RichTextFragmentsByFirstCharacter;
            public KeyValuePair<string, string>[] Templates;
            public Dictionary<string, Dictionary<string, string>> Concepts;
            public HashSet<string> Keys;
        }

        private sealed class BoundedLocalizationCache
        {
            private struct CacheKey : IEquatable<CacheKey>
            {
                public CacheKey(char kind, string source)
                {
                    Kind = kind;
                    Source = source;
                }

                public readonly char Kind;
                public readonly string Source;

                public bool Equals(CacheKey other)
                {
                    return Kind == other.Kind &&
                           StringComparer.Ordinal.Equals(Source, other.Source);
                }

                public override bool Equals(object value)
                {
                    return value is CacheKey && Equals((CacheKey)value);
                }

                public override int GetHashCode()
                {
                    return unchecked((Kind * 397) ^
                        StringComparer.Ordinal.GetHashCode(Source));
                }
            }

            private readonly int _maximumEntries;
            private readonly int _maximumBytes;
            private readonly object _clearGate = new object();
            private readonly ConcurrentDictionary<CacheKey, string> _values =
                new ConcurrentDictionary<CacheKey, string>();
            private int _count;
            private int _bytes;

            public BoundedLocalizationCache(int maximumEntries, int maximumBytes)
            {
                _maximumEntries = maximumEntries;
                _maximumBytes = maximumBytes;
            }

            public bool TryGet(char kind, string source, out string value)
            {
                return _values.TryGetValue(new CacheKey(kind, source), out value);
            }

            public void Add(char kind, string source, string value)
            {
                var key = new CacheKey(kind, source);
                var bytes = checked(
                    (source.Length + (value == null ? 0 : value.Length)) * 2 + 72);
                if (bytes > _maximumBytes) return;
                lock (_clearGate)
                {
                    if (_count >= _maximumEntries || _bytes + bytes > _maximumBytes)
                    {
                        _values.Clear();
                        _count = 0;
                        _bytes = 0;
                    }
                    if (!_values.TryAdd(key, value)) return;
                    _count++;
                    _bytes += bytes;
                }
            }

            public void Clear()
            {
                lock (_clearGate)
                {
                    _values.Clear();
                    _count = 0;
                    _bytes = 0;
                }
            }
        }

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

        public static void RegisterRichTextFragment(string source, string translation)
        {
            if (string.IsNullOrEmpty(source)) throw new ArgumentException("Rich-text source is required.", "source");
            if (string.IsNullOrEmpty(translation)) throw new ArgumentException("Rich-text translation is required.", "translation");
            lock (Gate) RegisterValue(RichTextFragments, source, translation, true);
        }

        public static void RegisterTemplate(string source, string translation)
        {
            ValidateTemplate(source, translation);
            lock (Gate) RegisterValue(Templates, source, translation, true);
        }

        public static void RegisterConceptKey(string conceptKey)
        {
            if (string.IsNullOrEmpty(conceptKey)) throw new ArgumentException("Concept key is required.", "conceptKey");
            lock (Gate)
            {
                if (ConceptKeys.Add(conceptKey)) InvalidateSnapshot();
            }
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
            var resultCache = ResultCache;
            string cached;
            if (resultCache.TryGet('D', value, out cached)) return cached;
            var snapshot = GetSnapshot();
            string translated;
            if (snapshot.Exact.TryGetValue(value, out translated))
            {
                resultCache.Add('D', value, translated);
                return translated;
            }
            if (snapshot.Plain.TryGetValue(value, out translated))
            {
                resultCache.Add('D', value, translated);
                return translated;
            }

            if (TryLocalizeGameDate(value, out translated))
            {
                resultCache.Add('D', value, translated);
                return translated;
            }

            // Dynamic status values can be appended after TextFormatter has
            // processed the original rich-text template. Apply both fragment
            // tables to final display strings: rich fragments handle complete
            // markup-bearing templates (for example a trait phrase), while
            // plain fragments handle generated reason/operation clauses that
            // may be wrapped by a color or hover tag. Plain fragments must be
            // applied outside bracketed tags so a concept link such as
            // [Content|MOOD] keeps its display/key pair intact.
            if (!TryApplyTemplate(value, snapshot.Templates, out translated))
            {
                translated = ApplyPlainTextFragments(value,
                    snapshot.RichTextFragmentsByFirstCharacter);
                translated = translated.IndexOf('[') >= 0
                    ? ApplyPlainTextFragmentsOutsideMarkup(translated,
                        snapshot.FragmentsByFirstCharacter)
                    : ApplyPlainTextFragments(translated,
                        snapshot.FragmentsByFirstCharacter);
            }
            resultCache.Add('D', value, translated);
            return translated;
        }

        public static string LocalizeRichText(string value)
        {
            if (value == null) return null;
            EnsureDefaultLoaded();
            var resultCache = ResultCache;
            string cached;
            if (resultCache.TryGet('R', value, out cached)) return cached;
            var snapshot = GetSnapshot();
            string exact;
            if (snapshot.Exact.TryGetValue(value, out exact))
            {
                resultCache.Add('R', value, exact);
                return exact;
            }

            var changed = TryApplyTemplate(value, snapshot.Templates, out var templated);
            if (changed) value = templated;
            var richLocalized = ApplyPlainTextFragments(value,
                snapshot.RichTextFragmentsByFirstCharacter);
            if (!StringComparer.Ordinal.Equals(richLocalized, value))
            {
                value = richLocalized;
                changed = true;
            }
            var nodes = RichTextAst.Parse(value, snapshot.Keys);
            var mapped = new List<RichNode>(nodes.Count);
            foreach (var node in nodes)
            {
                var text = node as PlainTextNode;
                if (text != null)
                {
                    string translated;
                    if (snapshot.Plain.TryGetValue(text.Text, out translated))
                    {
                        mapped.Add(new PlainTextNode(translated));
                        changed = true;
                    }
                    else
                    {
                        translated = ApplyPlainTextFragments(
                            text.Text, snapshot.FragmentsByFirstCharacter);
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
                    if (snapshot.Concepts.TryGetValue(link.ConceptKey, out displays) &&
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
            if (CollapseInlineWhitespaceBetweenChineseConcepts(mapped)) changed = true;
            var result = changed ? RichTextAst.Render(mapped) : value;
            resultCache.Add('R', value, result);
            return result;
        }

        private static bool CollapseInlineWhitespaceBetweenChineseConcepts(List<RichNode> nodes)
        {
            var changed = false;
            for (var index = 0; index < nodes.Count; index++)
            {
                var plain = nodes[index] as PlainTextNode;
                if (plain == null) continue;
                var text = plain.Text;
                if (index + 1 < nodes.Count &&
                    nodes[index + 1] is ConceptLinkNode nextLink &&
                    CjkText.ContainsBreakableCjk(nextLink.DisplayText))
                {
                    var trimmed = TrimTrailingChineseLinkWhitespace(text);
                    if (!StringComparer.Ordinal.Equals(trimmed, text))
                    {
                        nodes[index] = plain = new PlainTextNode(trimmed);
                        text = trimmed;
                        changed = true;
                    }
                }
                if (index > 0 &&
                    nodes[index - 1] is ConceptLinkNode previousLink &&
                    CjkText.ContainsBreakableCjk(previousLink.DisplayText))
                {
                    var trimmed = TrimLeadingChineseLinkWhitespace(text);
                    if (!StringComparer.Ordinal.Equals(trimmed, text))
                    {
                        nodes[index] = new PlainTextNode(trimmed);
                        changed = true;
                    }
                }
            }
            for (var index = 1; index < nodes.Count - 1; index++)
            {
                var whitespace = nodes[index] as PlainTextNode;
                if (whitespace == null || !IsInlineWhitespace(whitespace.Text))
                    continue;

                var previous = nodes[index - 1] as ConceptLinkNode;
                var next = nodes[index + 1] as ConceptLinkNode;
                var previousPlain = nodes[index - 1] as PlainTextNode;
                var nextPlain = nodes[index + 1] as PlainTextNode;
                var previousIsChinese = previous != null
                    ? CjkText.ContainsBreakableCjk(previous.DisplayText)
                    : previousPlain != null && EndsWithBreakableCjk(previousPlain.Text);
                var nextIsChinese = next != null
                    ? CjkText.ContainsBreakableCjk(next.DisplayText)
                    : nextPlain != null && StartsWithBreakableCjk(nextPlain.Text);
                if (!previousIsChinese || !nextIsChinese)
                    continue;

                nodes[index] = new PlainTextNode(string.Empty);
                changed = true;
            }
            return changed;
        }

        private static string TrimTrailingChineseLinkWhitespace(string value)
        {
            var end = value.Length;
            while (end > 0 && (value[end - 1] == ' ' || value[end - 1] == '\t')) end--;
            if (end == value.Length || end == 0 ||
                !CjkText.ContainsBreakableCjk(value[end - 1].ToString())) return value;
            return value.Substring(0, end);
        }

        private static string TrimLeadingChineseLinkWhitespace(string value)
        {
            var start = 0;
            while (start < value.Length && (value[start] == ' ' || value[start] == '\t')) start++;
            if (start == 0 || start == value.Length ||
                !CjkText.ContainsBreakableCjk(value[start].ToString())) return value;
            return value.Substring(start);
        }

        private static bool EndsWithBreakableCjk(string value)
        {
            return !string.IsNullOrEmpty(value) &&
                CjkText.ContainsBreakableCjk(value[value.Length - 1].ToString());
        }

        private static bool StartsWithBreakableCjk(string value)
        {
            return !string.IsNullOrEmpty(value) &&
                CjkText.ContainsBreakableCjk(value[0].ToString());
        }

        private static bool IsInlineWhitespace(string value)
        {
            if (value.Length == 0) return false;
            for (var index = 0; index < value.Length; index++)
            {
                var character = value[index];
                if (character != ' ' && character != '\t') return false;
            }
            return true;
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
                        case "R" when fields.Length == 3:
                            RegisterRichTextFragment(Decode(fields[1]), Decode(fields[2]));
                            break;
                        case "T" when fields.Length == 3:
                            RegisterTemplate(Decode(fields[1]), Decode(fields[2]));
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
                RichTextFragments.Clear();
                Templates.Clear();
                ConceptDisplay.Clear();
                ConceptKeys.Clear();
                Snapshot = null;
                ResultCache = new BoundedLocalizationCache(4096, 2 * 1024 * 1024);
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

        private static bool TryLocalizeGameDate(string value, out string translated)
        {
            const string eraSuffix = " AD";
            if (!value.EndsWith(eraSuffix, StringComparison.Ordinal))
            {
                translated = value;
                return false;
            }
            var comma = value.LastIndexOf(", ", StringComparison.Ordinal);
            if (comma <= 0 || comma + 2 >= value.Length - eraSuffix.Length)
            {
                translated = value;
                return false;
            }
            var year = value.Substring(comma + 2,
                value.Length - comma - 2 - eraSuffix.Length);
            if (!IsAsciiDigits(year))
            {
                translated = value;
                return false;
            }

            var monthWithPart = value.Substring(0, comma);
            var part = "";
            if (monthWithPart.StartsWith("Early ", StringComparison.Ordinal))
            {
                monthWithPart = monthWithPart.Substring("Early ".Length);
                part = "上旬";
            }
            else if (monthWithPart.StartsWith("Late ", StringComparison.Ordinal))
            {
                monthWithPart = monthWithPart.Substring("Late ".Length);
                part = "下旬";
            }

            string month;
            if (!GameMonthNames.TryGetValue(monthWithPart, out month))
            {
                translated = value;
                return false;
            }
            translated = "公元" + year + "年" + month + part;
            return true;
        }

        private static bool IsAsciiDigits(string value)
        {
            if (value.Length == 0) return false;
            for (var index = 0; index < value.Length; index++)
            {
                var character = value[index];
                if (character < '0' || character > '9') return false;
            }
            return true;
        }

        private static bool TryApplyTemplate(string value,
            KeyValuePair<string, string>[] templates, out string translated)
        {
            foreach (var template in templates)
            {
                if (!TryMatchTemplate(template.Key, value, out var arguments)) continue;
                translated = ReplaceTemplateArguments(template.Value, arguments);
                return true;
            }
            translated = value;
            return false;
        }

        private static bool TryMatchTemplate(string template, string value,
            out Dictionary<string, string> arguments)
        {
            arguments = new Dictionary<string, string>(StringComparer.Ordinal);
            var templateIndex = 0;
            var valueIndex = 0;
            while (templateIndex < template.Length)
            {
                var tokenStart = template.IndexOf("{arg:", templateIndex,
                    StringComparison.Ordinal);
                if (tokenStart < 0)
                {
                    var suffix = template.Substring(templateIndex);
                    return value.Length - valueIndex == suffix.Length &&
                        string.CompareOrdinal(value, valueIndex, suffix, 0, suffix.Length) == 0;
                }
                var literal = template.Substring(templateIndex, tokenStart - templateIndex);
                if (value.Length - valueIndex < literal.Length ||
                    string.CompareOrdinal(value, valueIndex, literal, 0, literal.Length) != 0)
                    return false;
                valueIndex += literal.Length;
                var tokenEnd = template.IndexOf('}', tokenStart + 5);
                if (tokenEnd < 0) return false;
                var argument = template.Substring(tokenStart, tokenEnd - tokenStart + 1);
                var nextToken = template.IndexOf("{arg:", tokenEnd + 1,
                    StringComparison.Ordinal);
                var nextLiteral = nextToken < 0
                    ? template.Substring(tokenEnd + 1)
                    : template.Substring(tokenEnd + 1, nextToken - tokenEnd - 1);
                string captured;
                if (nextLiteral.Length == 0)
                {
                    captured = value.Substring(valueIndex);
                    valueIndex = value.Length;
                }
                else
                {
                    var nextIndex = value.IndexOf(nextLiteral, valueIndex,
                        StringComparison.Ordinal);
                    if (nextIndex < 0) return false;
                    captured = value.Substring(valueIndex, nextIndex - valueIndex);
                    valueIndex = nextIndex;
                }
                if (arguments.TryGetValue(argument, out var existing) &&
                    !StringComparer.Ordinal.Equals(existing, captured))
                    return false;
                arguments[argument] = captured;
                templateIndex = tokenEnd + 1;
            }
            return valueIndex == value.Length;
        }

        private static string ReplaceTemplateArguments(string template,
            Dictionary<string, string> arguments)
        {
            var builder = new StringBuilder(template.Length);
            var index = 0;
            while (index < template.Length)
            {
                var tokenStart = template.IndexOf("{arg:", index,
                    StringComparison.Ordinal);
                if (tokenStart < 0)
                {
                    builder.Append(template, index, template.Length - index);
                    break;
                }
                builder.Append(template, index, tokenStart - index);
                var tokenEnd = template.IndexOf('}', tokenStart + 5);
                if (tokenEnd < 0) throw new InvalidDataException("Invalid display template token.");
                var argument = template.Substring(tokenStart, tokenEnd - tokenStart + 1);
                if (!arguments.TryGetValue(argument, out var captured))
                    throw new InvalidDataException("Display template omits a source argument.");
                builder.Append(captured);
                index = tokenEnd + 1;
            }
            return builder.ToString();
        }

        private static void ValidateTemplate(string source, string translation)
        {
            if (string.IsNullOrEmpty(source) || string.IsNullOrEmpty(translation))
                throw new ArgumentException("Display template text is required.");
            var sourceArguments = GetTemplateArguments(source);
            var translatedArguments = GetTemplateArguments(translation);
            sourceArguments.Sort(StringComparer.Ordinal);
            translatedArguments.Sort(StringComparer.Ordinal);
            if (sourceArguments.Count == 0 || sourceArguments.Count != translatedArguments.Count)
                throw new ArgumentException("Display template must preserve every source argument.");
            for (var index = 0; index < sourceArguments.Count; index++)
            {
                if (!StringComparer.Ordinal.Equals(sourceArguments[index], translatedArguments[index]))
                    throw new ArgumentException("Display template must preserve every source argument.");
            }
        }

        private static List<string> GetTemplateArguments(string value)
        {
            var arguments = new List<string>();
            var index = 0;
            while (index < value.Length)
            {
                var tokenStart = value.IndexOf("{arg:", index, StringComparison.Ordinal);
                if (tokenStart < 0) break;
                var tokenEnd = value.IndexOf('}', tokenStart + 5);
                if (tokenEnd < 0) throw new ArgumentException("Invalid display template token.");
                arguments.Add(value.Substring(tokenStart, tokenEnd - tokenStart + 1));
                index = tokenEnd + 1;
            }
            return arguments;
        }

        private static string ApplyPlainTextFragments(string value,
            Dictionary<char, KeyValuePair<string, string>[]> fragments)
        {
            if (value.Length == 0 || fragments.Count == 0) return value;
            StringBuilder builder = null;
            var index = 0;
            var copyStart = 0;
            while (index < value.Length)
            {
                KeyValuePair<string, string>? match = null;
                var matchLength = 0;
                KeyValuePair<string, string>[] candidates;
                if (fragments.TryGetValue(value[index], out candidates))
                {
                    foreach (var entry in candidates)
                    {
                        if (index + entry.Key.Length > value.Length) continue;
                        int candidateLength;
                        if (TryMatchPlainTextFragment(value, index, entry.Key,
                                out candidateLength))
                        {
                            match = entry;
                            matchLength = candidateLength;
                            break;
                        }
                    }
                }

                if (match.HasValue)
                {
                    if (builder == null) builder = new StringBuilder(value.Length);
                    if (index > copyStart) builder.Append(value, copyStart, index - copyStart);
                    builder.Append(match.Value.Value);
                    index += matchLength;
                    copyStart = index;
                }
                else index++;
            }
            if (builder == null) return value;
            if (copyStart < value.Length)
                builder.Append(value, copyStart, value.Length - copyStart);
            return builder.ToString();
        }

        private static bool TryMatchPlainTextFragment(string value, int valueIndex,
            string source, out int matchedLength)
        {
            var sourceIndex = 0;
            var candidateIndex = valueIndex;
            while (sourceIndex < source.Length)
            {
                if (source[sourceIndex] == ' ')
                {
                    var separatorStart = candidateIndex;
                    while (candidateIndex < value.Length &&
                           IsFlexibleFragmentSeparator(value[candidateIndex]))
                        candidateIndex++;
                    if (candidateIndex == separatorStart)
                    {
                        matchedLength = 0;
                        return false;
                    }
                    sourceIndex++;
                    continue;
                }

                if (candidateIndex >= value.Length ||
                    value[candidateIndex] != source[sourceIndex])
                {
                    matchedLength = 0;
                    return false;
                }
                sourceIndex++;
                candidateIndex++;
            }

            matchedLength = candidateIndex - valueIndex;
            return true;
        }

        private static bool IsFlexibleFragmentSeparator(char character)
        {
            return char.IsWhiteSpace(character) || character == '\u00a0' ||
                   CjkText.IsIgnorableFormat(character);
        }

        private static string ApplyPlainTextFragmentsOutsideMarkup(string value,
            Dictionary<char, KeyValuePair<string, string>[]> fragments)
        {
            if (value.Length == 0 || fragments.Count == 0) return value;

            StringBuilder builder = null;
            var segmentStart = 0;
            var index = 0;
            while (index < value.Length)
            {
                if (value[index] != '[')
                {
                    index++;
                    continue;
                }

                var close = value.IndexOf(']', index + 1);
                if (close < 0)
                {
                    // An incomplete tag is safer left untouched than having
                    // a fragment replacement corrupt the remaining markup.
                    break;
                }

                if (builder == null) builder = new StringBuilder(value.Length);
                if (index > segmentStart)
                    builder.Append(ApplyPlainTextFragments(
                        value.Substring(segmentStart, index - segmentStart),
                        fragments));
                builder.Append(value, index, close - index + 1);
                index = close + 1;
                segmentStart = index;
            }

            if (builder == null) return value;
            if (segmentStart < value.Length)
                builder.Append(ApplyPlainTextFragments(
                    value.Substring(segmentStart), fragments));
            return builder.ToString();
        }

        private static Dictionary<char, KeyValuePair<string, string>[]> BuildFragmentIndex(
            Dictionary<string, string> values)
        {
            var buckets = new Dictionary<char, List<KeyValuePair<string, string>>>();
            foreach (var entry in values)
            {
                if (entry.Key.Length == 0) continue;
                List<KeyValuePair<string, string>> bucket;
                if (!buckets.TryGetValue(entry.Key[0], out bucket))
                {
                    bucket = new List<KeyValuePair<string, string>>();
                    buckets.Add(entry.Key[0], bucket);
                }
                bucket.Add(entry);
            }
            var result = new Dictionary<char, KeyValuePair<string, string>[]>();
            foreach (var bucket in buckets)
            {
                bucket.Value.Sort((left, right) =>
                {
                    var length = right.Key.Length.CompareTo(left.Key.Length);
                    return length != 0
                        ? length
                        : StringComparer.Ordinal.Compare(left.Key, right.Key);
                });
                result.Add(bucket.Key, bucket.Value.ToArray());
            }
            return result;
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
            InvalidateSnapshot();
        }

        private static void ValidateDisplayValue(string value, string parameterName)
        {
            if (string.IsNullOrEmpty(value))
                throw new ArgumentException("Display text is required.", parameterName);
            if (value.IndexOf('[') >= 0 || value.IndexOf(']') >= 0 || value.IndexOf('|') >= 0)
                throw new ArgumentException("Display text must not contain rich-text markup.", parameterName);
        }

        private static LocalizationSnapshot GetSnapshot()
        {
            var snapshot = Snapshot;
            if (snapshot != null) return snapshot;
            lock (Gate)
            {
                snapshot = Snapshot;
                if (snapshot != null) return snapshot;

                var fragmentIndex = BuildFragmentIndex(PlainTextFragments);
                var richTextFragmentIndex = BuildFragmentIndex(RichTextFragments);

                var concepts =
                    new Dictionary<string, Dictionary<string, string>>(StringComparer.Ordinal);
                foreach (var pair in ConceptDisplay)
                    concepts.Add(pair.Key,
                        new Dictionary<string, string>(pair.Value, StringComparer.Ordinal));
                var templates = new List<KeyValuePair<string, string>>(Templates);
                templates.Sort((left, right) =>
                {
                    var length = right.Key.Length.CompareTo(left.Key.Length);
                    return length != 0
                        ? length
                        : StringComparer.Ordinal.Compare(left.Key, right.Key);
                });
                snapshot = new LocalizationSnapshot
                {
                    Exact = new Dictionary<string, string>(ExactStrings, StringComparer.Ordinal),
                    Plain = new Dictionary<string, string>(PlainText, StringComparer.Ordinal),
                    FragmentsByFirstCharacter = fragmentIndex,
                    RichTextFragmentsByFirstCharacter = richTextFragmentIndex,
                    Templates = templates.ToArray(),
                    Concepts = concepts,
                    Keys = new HashSet<string>(ConceptKeys, StringComparer.Ordinal),
                };
                Snapshot = snapshot;
                return snapshot;
            }
        }

        private static void InvalidateSnapshot()
        {
            Snapshot = null;
            ResultCache = new BoundedLocalizationCache(4096, 2 * 1024 * 1024);
        }
    }
}
