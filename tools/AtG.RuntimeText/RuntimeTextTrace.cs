using System;
using System.Globalization;
using System.Collections.Generic;
using System.IO;
using System.Text;

namespace AtG.RuntimeText
{
    internal sealed class RuntimeTextTraceMetrics
    {
        public float? X;
        public float? Y;
        public float? Width;
        public float? Height;
        public int MissingGlyphs;
    }

    internal static class RuntimeTextTrace
    {
        private static readonly object Gate = new object();
        private static readonly Dictionary<string, DateTime> LastWrites =
            new Dictionary<string, DateTime>();
        private static readonly TimeSpan RepeatInterval = TimeSpan.FromMilliseconds(500);
        private static readonly bool Enabled =
            string.Equals(Environment.GetEnvironmentVariable("ATG_RUNTIME_TEXT_TRACE"), "1", StringComparison.Ordinal);

        public static bool IsEnabled { get { return Enabled; } }

        public static void Write(string eventName, string text, FontDescriptor font, Exception error)
        {
            Write(eventName, text, font, error, null);
        }

        public static void Write(string eventName, string text, FontDescriptor font, Exception error,
            RuntimeTextTraceMetrics metrics)
        {
            if (!Enabled && error == null) return;
            TraceWriteGuard.Try(delegate
            {
                var now = DateTime.UtcNow;
                var path = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "AtG.RuntimeText.jsonl");
                var line = FormatLine(eventName, text, font, error, metrics, now);
                var repeatKey = eventName + "|" + text + "|" +
                    (font == null ? "" : font.CacheKey);
                lock (Gate)
                {
                    if (error == null)
                    {
                        DateTime previous;
                        if (LastWrites.TryGetValue(repeatKey, out previous) &&
                            now - previous < RepeatInterval) return;
                        LastWrites[repeatKey] = now;
                    }
                    File.AppendAllText(path, line + Environment.NewLine, Encoding.UTF8);
                }
            });
        }

        internal static string FormatLine(string eventName, string text, FontDescriptor font,
            Exception error, RuntimeTextTraceMetrics metrics, DateTime timeUtc)
        {
            return "{\"time\":\"" + timeUtc.ToString("o", CultureInfo.InvariantCulture) +
                   "\",\"event\":\"" + Escape(eventName) +
                   "\",\"text\":\"" + Escape(text) +
                   "\",\"font\":\"" + Escape(font == null ? "" : font.CacheKey) +
                   "\",\"error\":\"" + Escape(error == null ? "" : error.ToString()) +
                   "\",\"x\":" + Number(metrics == null ? null : metrics.X) +
                   ",\"y\":" + Number(metrics == null ? null : metrics.Y) +
                   ",\"width\":" + Number(metrics == null ? null : metrics.Width) +
                   ",\"height\":" + Number(metrics == null ? null : metrics.Height) +
                   ",\"missingGlyphs\":" + (metrics == null ? "0" : metrics.MissingGlyphs.ToString(CultureInfo.InvariantCulture)) + "}";
        }

        private static string Number(float? value)
        {
            return value.HasValue
                ? value.Value.ToString("0.###", CultureInfo.InvariantCulture)
                : "null";
        }

        private static string Escape(string value)
        {
            if (value == null) return "";
            return value.Replace("\\", "\\\\").Replace("\"", "\\\"")
                .Replace("\r", "\\r").Replace("\n", "\\n");
        }
    }
}
