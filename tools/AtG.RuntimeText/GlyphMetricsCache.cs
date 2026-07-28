using System;
using System.Collections.Generic;

namespace AtG.RuntimeText
{
    internal sealed class GlyphMetrics
    {
        public GlyphMetrics(float advance, float lineHeight, bool provisional)
        {
            Advance = advance;
            LineHeight = lineHeight;
            Provisional = provisional;
        }

        public float Advance { get; private set; }
        public float LineHeight { get; private set; }
        public bool Provisional { get; private set; }
    }

    internal static class GlyphMetricsCache
    {
        private struct MetricKey : IEquatable<MetricKey>
        {
            public MetricKey(string descriptorKey, char character)
            {
                DescriptorKey = descriptorKey;
                Character = character;
            }

            public readonly string DescriptorKey;
            public readonly char Character;

            public bool Equals(MetricKey other)
            {
                return Character == other.Character &&
                       StringComparer.Ordinal.Equals(DescriptorKey, other.DescriptorKey);
            }

            public override bool Equals(object value)
            {
                return value is MetricKey && Equals((MetricKey)value);
            }

            public override int GetHashCode()
            {
                return unchecked(
                    (StringComparer.Ordinal.GetHashCode(DescriptorKey) * 397) ^ Character);
            }
        }

        public const int MaximumEntries = 32768;
        private static readonly object Gate = new object();
        private static readonly Dictionary<MetricKey, GlyphMetrics> Values =
            new Dictionary<MetricKey, GlyphMetrics>();
        private static readonly Queue<MetricKey> InsertionOrder = new Queue<MetricKey>();

        public static GlyphMetrics GetOrReserve(FontDescriptor descriptor, char character)
        {
            bool reserved;
            return GetOrReserve(descriptor, character, out reserved);
        }

        public static GlyphMetrics GetOrReserve(FontDescriptor descriptor, char character,
            out bool reserved)
        {
            if (descriptor == null) throw new ArgumentNullException("descriptor");
            var key = new MetricKey(descriptor.CacheKey, character);
            lock (Gate)
            {
                GlyphMetrics existing;
                if (Values.TryGetValue(key, out existing))
                {
                    reserved = false;
                    return existing;
                }
                var fallback = new GlyphMetrics(
                    Math.Max(1f, descriptor.RasterSize),
                    Math.Max(1f, descriptor.RasterSize),
                    true);
                Add(key, fallback);
                reserved = true;
                return fallback;
            }
        }

        public static GlyphMetrics PublishMeasured(FontDescriptor descriptor, char character,
            float advance, float lineHeight)
        {
            if (descriptor == null) throw new ArgumentNullException("descriptor");
            var key = new MetricKey(descriptor.CacheKey, character);
            lock (Gate)
            {
                GlyphMetrics existing;
                if (Values.TryGetValue(key, out existing)) return existing;
                var measured = new GlyphMetrics(
                    Math.Max(1f, advance),
                    Math.Max(1f, lineHeight),
                    false);
                Add(key, measured);
                return measured;
            }
        }

        internal static int Count
        {
            get { lock (Gate) return Values.Count; }
        }

        internal static string CreateKey(FontDescriptor descriptor, char character)
        {
            return descriptor.CacheKey + "|" + ((int)character).ToString("X4");
        }

        internal static void ResetForTests()
        {
            lock (Gate)
            {
                Values.Clear();
                InsertionOrder.Clear();
            }
        }

        private static void Add(MetricKey key, GlyphMetrics metrics)
        {
            while (Values.Count >= MaximumEntries && InsertionOrder.Count > 0)
                Values.Remove(InsertionOrder.Dequeue());
            Values.Add(key, metrics);
            InsertionOrder.Enqueue(key);
        }
    }
}
