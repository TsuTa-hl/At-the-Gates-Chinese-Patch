using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Text;
using System.IO;

namespace AtG.RuntimeText
{
    internal static class PrivateFontProvider
    {
        private static readonly object Gate = new object();
        private static readonly PrivateFontCollection Collection = new PrivateFontCollection();
        private static readonly Dictionary<string, Font> Fonts = new Dictionary<string, Font>();
        private static bool _loaded;

        public static Font GetFont(FontDescriptor descriptor)
        {
            lock (Gate)
            {
                EnsureLoaded();
                Font font;
                if (Fonts.TryGetValue(descriptor.CacheKey, out font)) return font;
                var style = descriptor.Bold ? FontStyle.Bold : FontStyle.Regular;
                var family = Collection.Families.Length > 0
                    ? Collection.Families[Math.Min(descriptor.Bold ? 1 : 0, Collection.Families.Length - 1)]
                    : new FontFamily("Microsoft YaHei");
                font = new Font(family, descriptor.Size, style, GraphicsUnit.Pixel);
                Fonts.Add(descriptor.CacheKey, font);
                return font;
            }
        }

        private static void EnsureLoaded()
        {
            if (_loaded) return;
            var fontRoot = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "Content", "Fonts");
            AddIfPresent(Path.Combine(fontRoot, "NotoSansSC-Regular.otf"));
            AddIfPresent(Path.Combine(fontRoot, "NotoSansSC-Bold.otf"));
            _loaded = true;
        }

        private static void AddIfPresent(string path)
        {
            if (File.Exists(path)) Collection.AddFontFile(path);
            else RuntimeTextTrace.Write("missing-font-file", path, null, null);
        }
    }
}
