using System;
using System.Globalization;
using System.IO;

namespace AtG.RuntimeText
{
    public sealed class FontDescriptor
    {
        // SpriteFont asset sizes are logical XNA sizes, while the private CJK
        // rasterizer consumes pixel sizes. This calibration keeps Chinese glyphs
        // visually aligned with the original Latin SpriteFonts without changing
        // the original font or control coordinates.
        public const float DefaultCjkScale = 1.15f;

        public FontDescriptor(string name, float size, bool bold)
            : this(name, size, bold, DefaultCjkScale)
        {
        }

        public FontDescriptor(string name, float size, bool bold, float cjkScale)
        {
            if (string.IsNullOrEmpty(name)) throw new ArgumentNullException("name");
            if (size <= 0f) throw new ArgumentOutOfRangeException("size");
            if (cjkScale < 1f || cjkScale > 1.35f)
                throw new ArgumentOutOfRangeException("cjkScale");
            Name = name;
            Size = size;
            Bold = bold;
            CjkScale = cjkScale;
        }

        public string Name { get; private set; }
        public float Size { get; private set; }
        public bool Bold { get; private set; }
        public float CjkScale { get; private set; }
        public float RasterSize { get { return Size * CjkScale; } }
        public float CjkBaselineOffset { get { return ResolveCjkBaselineOffset(Size, Bold); } }
        public string CacheKey
        {
            get
            {
                return Name + "|" + Size.ToString("0.###") + "|" + Bold +
                    "|cjk=" + CjkScale.ToString("0.###", CultureInfo.InvariantCulture);
            }
        }

        public static bool TryFromAssetName(string assetName, out FontDescriptor descriptor)
        {
            descriptor = null;
            if (string.IsNullOrEmpty(assetName)) return false;
            var name = Path.GetFileName(assetName.Replace('/', Path.DirectorySeparatorChar));
            if (string.Equals(name, "SegoeUI_UltraTiny", StringComparison.OrdinalIgnoreCase))
            {
                descriptor = new FontDescriptor(name, 8f, false);
                return true;
            }
            if (name.StartsWith("SegoeUI_", StringComparison.OrdinalIgnoreCase))
            {
                var suffix = name.Substring("SegoeUI_".Length);
                var bold = suffix.EndsWith("_Bold", StringComparison.OrdinalIgnoreCase);
                if (bold) suffix = suffix.Substring(0, suffix.Length - "_Bold".Length);
                float size;
                if (float.TryParse(suffix, NumberStyles.Integer, CultureInfo.InvariantCulture, out size))
                {
                    descriptor = new FontDescriptor(name, size, bold);
                    return true;
                }
            }
            if (string.Equals(name, "Leelawalee_10", StringComparison.OrdinalIgnoreCase) ||
                string.Equals(name, "LucidaConsole_10_AtG", StringComparison.OrdinalIgnoreCase))
            {
                descriptor = new FontDescriptor(name, 10f, false);
                return true;
            }
            return false;
        }

        private static float ResolveCjkBaselineOffset(float size, bool bold)
        {
            // GDI+ and the original XNA SpriteFonts use different vertical
            // bearings. These offsets were calibrated against the original
            // SpriteFont assets and matching original/localized screenshots.
            if (size <= 10f) return -2f;
            if (size <= 11f) return -3f;
            if (size <= 13f) return -2f;
            if (size <= 15f) return bold ? -3f : -1f;
            if (size <= 16f) return -1f;
            if (size <= 18f) return -2f;
            if (size < 40f) return -1f;
            return 0f;
        }
    }
}
