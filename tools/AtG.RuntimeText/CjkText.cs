using System;
using System.Globalization;

namespace AtG.RuntimeText
{
    public static class CjkText
    {
        private const string OpeningPunctuation =
            "([{\uFF08\uFF3B\uFF5B\u3008\u300A\u300C\u300E\u3010\u3014\u3016\u3018\u301A";
        private const string ClosingPunctuation =
            ")]},.!?;:\uFF09\uFF3D\uFF5D\u3009\u300B\u300D\u300F\u3011\u3015\u3017\u3019\u301B" +
            "\uFF0C\u3002\uFF01\uFF1F\uFF1B\uFF1A\u3001\u2026\u2014\u201D\u2019";

        public static bool RequiresDynamicGlyph(char character)
        {
            return (character >= '\u2E80' && character <= '\u9FFF') ||
                   (character >= '\uF900' && character <= '\uFAFF') ||
                   (character >= '\uFE10' && character <= '\uFE6F') ||
                   (character >= '\uFF00' && character <= '\uFFEF');
        }

        public static bool IsIgnorableFormat(char character)
        {
            return char.GetUnicodeCategory(character) == UnicodeCategory.Format;
        }

        public static bool CanBreakBetween(char previous, char next)
        {
            if (previous == '\r' || previous == '\n' || next == '\r' || next == '\n') return true;
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

            var fitting = -1;
            var firstAllowedAfterFit = -1;
            for (var element = 1; element < starts.Length; element++)
            {
                var boundary = starts[element];
                if (!CanBreakBetweenElements(text, starts[element - 1], boundary, starts,
                    element)) continue;
                if (measure(text.Substring(0, boundary)) <= availableWidth)
                    fitting = boundary;
                else if (firstAllowedAfterFit < 0)
                    firstAllowedAfterFit = boundary;
            }
            if (fitting > 0) return fitting;
            if (firstAllowedAfterFit > 0) return firstAllowedAfterFit;
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
            var previousLength = nextStart - previousStart;
            var nextLength = nextElementIndex + 1 < starts.Length
                ? starts[nextElementIndex + 1] - nextStart
                : text.Length - nextStart;
            var previous = text.Substring(previousStart, previousLength);
            var next = text.Substring(nextStart, nextLength);
            if (previous == "\u00A0" || next == "\u00A0") return false;
            return CanBreakBetween(previous[previous.Length - 1], next[0]);
        }
    }
}
