using System;
using System.Globalization;
using System.IO;

namespace AtG.RuntimeText
{
    public sealed class FontDescriptor
    {
        public FontDescriptor(string name, float size, bool bold)
        {
            Name = name;
            Size = size;
            Bold = bold;
        }

        public string Name { get; private set; }
        public float Size { get; private set; }
        public bool Bold { get; private set; }
        public string CacheKey { get { return Name + "|" + Size.ToString("0.###") + "|" + Bold; } }

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
    }
}
