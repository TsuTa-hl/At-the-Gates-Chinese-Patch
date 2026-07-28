using System;
using System.Collections.Generic;

namespace AtG.RuntimeText
{
    public static class CjkLineBreaker
    {
        public static IList<string> SplitWord(string text, float firstLineWidth,
            float subsequentLineWidth, Func<string, float> measure)
        {
            if (text == null) throw new ArgumentNullException("text");
            if (measure == null) throw new ArgumentNullException("measure");
            var result = new List<string>();
            if (text.Length == 0)
            {
                result.Add(text);
                return result;
            }

            var remaining = text;
            var available = Math.Max(0f, firstLineWidth);
            while (remaining.Length > 0)
            {
                var boundary = CjkText.FindLongestFittingBreak(remaining, available, measure);
                if (boundary <= 0 || boundary >= remaining.Length)
                {
                    result.Add(remaining);
                    break;
                }
                result.Add(remaining.Substring(0, boundary));
                remaining = remaining.Substring(boundary);
                available = Math.Max(0f, subsequentLineWidth);
            }
            return result;
        }

        public static IList<string> SplitWord(string text, float firstLineWidth,
            float subsequentLineWidth, float[] prefixWidths)
        {
            if (text == null) throw new ArgumentNullException("text");
            if (prefixWidths == null) throw new ArgumentNullException("prefixWidths");
            if (prefixWidths.Length != text.Length + 1)
                throw new ArgumentException("Prefix widths must match the input text.",
                    "prefixWidths");
            var result = new List<string>();
            if (text.Length == 0)
            {
                result.Add(text);
                return result;
            }

            var start = 0;
            var available = Math.Max(0f, firstLineWidth);
            while (start < text.Length)
            {
                var boundary = CjkText.FindLongestFittingBreak(
                    text, start, available, prefixWidths);
                if (boundary <= start || boundary >= text.Length)
                {
                    result.Add(text.Substring(start));
                    break;
                }
                result.Add(text.Substring(start, boundary - start));
                start = boundary;
                available = Math.Max(0f, subsequentLineWidth);
            }
            return result;
        }
    }
}
