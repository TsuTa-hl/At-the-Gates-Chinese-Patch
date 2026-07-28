using System;
using System.Collections.Generic;
using System.IO;
using System.Text;

namespace AtG.RuntimeText
{
    internal static class RuntimeGlyphWarmset
    {
        private static readonly object Gate = new object();
        private static readonly bool Enabled =
            !string.Equals(Environment.GetEnvironmentVariable("ATG_RUNTIME_TEXT_WARMSET"),
                "0", StringComparison.Ordinal);
        private static readonly Dictionary<string, FontDescriptor> RegisteredDescriptors =
            new Dictionary<string, FontDescriptor>(StringComparer.Ordinal);
        private static IList<RuntimeGlyphWarmsetEntry> _entries;

        // Called from the GameCore constructor, before the first XNA Draw.
        // The private CJK font does not depend on the game's SpriteFont
        // content, so preparing known descriptors here gives the worker the
        // complete startup interval to rasterize the deterministic set.
        public static void Prime()
        {
            if (!Enabled || RuntimeGlyphScheduler.IsLegacySync) return;
            var descriptors = new List<FontDescriptor>();
            foreach (var entry in GetEntries())
            {
                var descriptor = new FontDescriptor(
                    entry.FontName, entry.Size, entry.Bold);
                lock (Gate)
                {
                    if (RegisteredDescriptors.ContainsKey(descriptor.CacheKey)) continue;
                    RegisteredDescriptors.Add(descriptor.CacheKey, descriptor);
                }
                descriptors.Add(descriptor);
            }
            foreach (var descriptor in descriptors) Enqueue(descriptor);
        }

        public static void Register(FontDescriptor descriptor)
        {
            if (!Enabled || descriptor == null || RuntimeGlyphScheduler.IsLegacySync) return;
            lock (Gate)
            {
                if (RegisteredDescriptors.ContainsKey(descriptor.CacheKey)) return;
                RegisteredDescriptors.Add(descriptor.CacheKey, descriptor);
            }
            Enqueue(descriptor);
        }

        public static void RequeueAll()
        {
            if (!Enabled || RuntimeGlyphScheduler.IsLegacySync) return;
            FontDescriptor[] descriptors;
            lock (Gate)
            {
                descriptors = new FontDescriptor[RegisteredDescriptors.Count];
                RegisteredDescriptors.Values.CopyTo(descriptors, 0);
            }
            foreach (var descriptor in descriptors) Enqueue(descriptor);
        }

        private static void Enqueue(FontDescriptor descriptor)
        {
            var entries = GetEntries();
            foreach (var entry in entries)
            {
                if (!StringComparer.OrdinalIgnoreCase.Equals(entry.FontName, descriptor.Name) ||
                    Math.Abs(entry.Size - descriptor.Size) > 0.001f ||
                    entry.Bold != descriptor.Bold) continue;
                for (var index = 0; index < entry.Characters.Length; index++)
                    RuntimeGlyphScheduler.RequestWarm(
                        descriptor, entry.Characters[index], entry.Priority);
            }
        }

        internal static int PairCount
        {
            get
            {
                var count = 0;
                foreach (var entry in GetEntries()) count += entry.Characters.Length;
                return count;
            }
        }

        private static IList<RuntimeGlyphWarmsetEntry> GetEntries()
        {
            lock (Gate)
            {
                if (_entries != null) return _entries;
                var path = Path.Combine(AppDomain.CurrentDomain.BaseDirectory,
                    "Content", "Fonts", "AtG.RuntimeGlyphWarmset.tsv");
                if (!File.Exists(path))
                {
                    RuntimeTextTrace.Write("glyph-warmset-missing", path, null,
                        new FileNotFoundException("Runtime glyph warmset was not found.", path));
                    _entries = new List<RuntimeGlyphWarmsetEntry>();
                    return _entries;
                }
                try
                {
                    using (var reader = new StreamReader(path, Encoding.UTF8, true))
                        _entries = RuntimeGlyphWarmsetCatalog.Load(reader);
                }
                catch (Exception ex)
                {
                    RuntimeTextTrace.Write("glyph-warmset-load-failed", path, null, ex);
                    _entries = new List<RuntimeGlyphWarmsetEntry>();
                }
                return _entries;
            }
        }
    }
}
