using System;
using System.Globalization;

namespace AtG.RuntimeText
{
    public static class CjkText
    {
        private const string OpeningPunctuation =
            "([{\u2018\u201C\uFF08\uFF3B\uFF5B\u3008\u300A\u300C\u300E\u3010\u3014\u3016\u3018\u301A";
        private const string ClosingPunctuation =
            ")]},.!?;:\uFF09\uFF3D\uFF5D\u3009\u300B\u300D\u300F\u3011\u3015\u3017\u3019\u301B" +
            "\uFF0C\u3002\uFF01\uFF1F\uFF1B\uFF1A\u3001\u2026\u2014\u201D\u2019";
        private const string DynamicTypography = "\u2013\u2014\u2018\u2019\u201C\u201D\u2026";

        public static bool RequiresDynamicGlyph(char character)
        {
            if ((character >= (char)0x3000 && character <= (char)0x303F) ||
                character == (char)0x2013 || character == (char)0x2014 ||
                character == (char)0x2018 || character == (char)0x2019 ||
                character == (char)0x201C || character == (char)0x201D ||
                character == (char)0x2026) return true;
            return (character >= '\u2E80' && character <= '\u9FFF') ||
                   (character >= '\uF900' && character <= '\uFAFF') ||
                   (character >= '\u3000' && character <= '\u303F') ||
                   (character >= '\uFE10' && character <= '\uFE6F') ||
                   (character >= '\uFF00' && character <= '\uFFEF') ||
                   DynamicTypography.IndexOf(character) >= 0;
        }

        public static bool IsIgnorableFormat(char character)
        {
            return char.GetUnicodeCategory(character) == UnicodeCategory.Format;
        }

        public static bool CanBreakBetween(char previous, char next)
        {
            if (previous == '\r' || previous == '\n' || next == '\r' || next == '\n') return true;
            if (previous == (char)0x2018 || previous == (char)0x201C) return false;
            if (OpeningPunctuation.IndexOf(previous) >= 0) return false;
            if (ClosingPunctuation.IndexOf(next) >= 0) return false;
            return RequiresDynamicGlyph(previous) || RequiresDynamicGlyph(next) ||
                   char.IsWhiteSpace(previous) || char.IsWhiteSpace(next);
        }

        public static int FindLongestFittingBreak(string text, float availableWidth,
            Func<string, float> measure)
        {
            if (text == null) throw new ArgumentNullException("text");
            if (measure == null) throw new ArgumentNullException("measure");
            if (text.Length == 0) return 0;

            var starts = StringInfo.ParseCombiningCharacters(text);
            if (!ContainsCjkTextElement(text, starts)) return text.Length;
            if (measure(text) <= availableWidth) return text.Length;

            var boundaries = new System.Collections.Generic.List<int>();
            for (var element = 1; element < starts.Length; element++)
            {
                var boundary = starts[element];
                if (!CanBreakBetweenElements(text, starts[element - 1], boundary, starts,
                    element)) continue;
                boundaries.Add(boundary);
            }
            if (boundaries.Count == 0) return text.Length;

            var low = 0;
            var high = boundaries.Count - 1;
            var fittingIndex = -1;
            while (low <= high)
            {
                var middle = low + (high - low) / 2;
                var boundary = boundaries[middle];
                if (measure(text.Substring(0, boundary)) <= availableWidth)
                {
                    fittingIndex = middle;
                    low = middle + 1;
                }
                else high = middle - 1;
            }
            return fittingIndex >= 0 ? boundaries[fittingIndex] : boundaries[0];
        }

        public static int FindLongestFittingBreak(string text, int start,
            float availableWidth, float[] prefixWidths)
        {
            if (text == null) throw new ArgumentNullException("text");
            if (prefixWidths == null) throw new ArgumentNullException("prefixWidths");
            if (start < 0 || start > text.Length) throw new ArgumentOutOfRangeException("start");
            if (prefixWidths.Length != text.Length + 1)
                throw new ArgumentException("Prefix widths must contain one value per UTF-16 boundary.",
                    "prefixWidths");
            if (start == text.Length) return text.Length;
            if (prefixWidths[text.Length] - prefixWidths[start] <= availableWidth)
                return text.Length;

            var starts = StringInfo.ParseCombiningCharacters(text);
            var firstElement = Array.BinarySearch(starts, start);
            if (firstElement < 0) firstElement = ~firstElement;
            var firstAllowed = -1;
            var fitting = -1;
            for (var element = Math.Max(1, firstElement + 1);
                 element < starts.Length;
                 element++)
            {
                var boundary = starts[element];
                if (boundary <= start) continue;
                if (!CanBreakBetweenElements(text, starts[element - 1], boundary, starts,
                        element)) continue;
                if (firstAllowed < 0) firstAllowed = boundary;
                if (prefixWidths[boundary] - prefixWidths[start] <= availableWidth)
                    fitting = boundary;
                else break;
            }
            if (fitting > start) return fitting;
            if (firstAllowed > start) return firstAllowed;
            return text.Length;
        }

        public static bool ContainsBreakableCjk(string text)
        {
            if (string.IsNullOrEmpty(text)) return false;
            return ContainsCjkTextElement(text, StringInfo.ParseCombiningCharacters(text));
        }

        private static bool ContainsCjkTextElement(string text, int[] starts)
        {
            for (var index = 0; index < starts.Length; index++)
            {
                var codePoint = char.ConvertToUtf32(text, starts[index]);
                if ((codePoint >= 0x2E80 && codePoint <= 0x9FFF) ||
                    (codePoint >= 0xF900 && codePoint <= 0xFAFF) ||
                    (codePoint >= 0x20000 && codePoint <= 0x2FA1F) ||
                    (codePoint >= 0xFE10 && codePoint <= 0xFE6F) ||
                    (codePoint >= 0xFF00 && codePoint <= 0xFFEF)) return true;
            }
            return false;
        }

        private static bool CanBreakBetweenElements(string text, int previousStart,
            int nextStart, int[] starts, int nextElementIndex)
        {
            if (nextStart - previousStart == 1 && text[previousStart] == '\u00A0')
                return false;
            var nextLength = nextElementIndex + 1 < starts.Length
                ? starts[nextElementIndex + 1] - nextStart
                : text.Length - nextStart;
            if (nextLength == 1 && text[nextStart] == '\u00A0') return false;
            return CanBreakBetween(text[nextStart - 1], text[nextStart]);
        }
    }
}
