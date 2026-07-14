using System;
using System.Collections.Generic;
using System.Text;

namespace AtG.RuntimeText
{
    public abstract class RichNode
    {
        public abstract string Render();
    }

    public sealed class PlainTextNode : RichNode
    {
        public PlainTextNode(string text) { Text = text; }
        public string Text { get; private set; }
        public override string Render() { return Text; }
    }

    public sealed class ConceptLinkNode : RichNode
    {
        public ConceptLinkNode(string displayText, string conceptKey)
        {
            DisplayText = displayText;
            ConceptKey = conceptKey;
        }
        public string DisplayText { get; private set; }
        public string ConceptKey { get; private set; }
        public override string Render() { return "[" + DisplayText + "|" + ConceptKey + "]"; }
    }

    public sealed class RawTagNode : RichNode
    {
        public RawTagNode(string rawText) { RawText = rawText; }
        public string RawText { get; private set; }
        public override string Render() { return RawText; }
    }

    public static class RichTextAst
    {
        public static IList<RichNode> Parse(string value)
        {
            return Parse(value, null);
        }

        public static IList<RichNode> Parse(string value, ISet<string> knownConceptKeys)
        {
            if (value == null) throw new ArgumentNullException("value");
            var result = new List<RichNode>();
            var plain = new StringBuilder();
            for (var index = 0; index < value.Length; index++)
            {
                if (value[index] != '[')
                {
                    plain.Append(value[index]);
                    continue;
                }
                var close = value.IndexOf(']', index + 1);
                if (close < 0)
                {
                    plain.Append(value[index]);
                    continue;
                }
                FlushPlain(result, plain);
                var body = value.Substring(index + 1, close - index - 1);
                var separator = body.IndexOf('|');
                var hasOneSeparator = separator > 0 && separator == body.LastIndexOf('|') &&
                    separator < body.Length - 1;
                var conceptKey = hasOneSeparator ? body.Substring(separator + 1) : null;
                if (hasOneSeparator &&
                    (knownConceptKeys == null || knownConceptKeys.Contains(conceptKey)))
                    result.Add(new ConceptLinkNode(body.Substring(0, separator), conceptKey));
                else
                    result.Add(new RawTagNode(value.Substring(index, close - index + 1)));
                index = close;
            }
            FlushPlain(result, plain);
            return result;
        }

        public static string Render(IEnumerable<RichNode> nodes)
        {
            var builder = new StringBuilder();
            foreach (var node in nodes) builder.Append(node.Render());
            return builder.ToString();
        }

        private static void FlushPlain(ICollection<RichNode> result, StringBuilder plain)
        {
            if (plain.Length == 0) return;
            result.Add(new PlainTextNode(plain.ToString()));
            plain.Length = 0;
        }
    }
}
