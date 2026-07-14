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
    }
}
