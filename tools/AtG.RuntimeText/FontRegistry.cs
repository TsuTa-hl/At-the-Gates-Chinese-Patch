using System;
using System.Collections.Generic;
using System.Runtime.CompilerServices;
using Microsoft.Xna.Framework.Content;
using Microsoft.Xna.Framework.Graphics;

namespace AtG.RuntimeText
{
    public static class FontRegistry
    {
        private static readonly ConditionalWeakTable<SpriteFont, FontDescriptor> Fonts =
            new ConditionalWeakTable<SpriteFont, FontDescriptor>();
        private static readonly object Gate = new object();

        public static void Register(SpriteFont font, string name, float size, bool bold)
        {
            if (font == null) throw new ArgumentNullException("font");
            lock (Gate)
            {
                Fonts.Remove(font);
                Fonts.Add(font, new FontDescriptor(name, size, bold));
            }
        }

        public static SpriteFont RegisterAndReturn(SpriteFont font, string name, float size, bool bold)
        {
            Register(font, name, size, bold);
            return font;
        }

        public static SpriteFont Load(ContentManager content, string assetName)
        {
            if (content == null) throw new ArgumentNullException("content");
            var font = content.Load<SpriteFont>(assetName);
            FontDescriptor descriptor;
            if (FontDescriptor.TryFromAssetName(assetName, out descriptor))
                Register(font, descriptor.Name, descriptor.Size, descriptor.Bold);
            else RuntimeTextTrace.Write("unknown-font-asset", assetName, null, null);
            return font;
        }

        public static FontDescriptor Resolve(SpriteFont font)
        {
            if (font == null) throw new ArgumentNullException("font");
            FontDescriptor descriptor;
            if (Fonts.TryGetValue(font, out descriptor)) return descriptor;
            var inferredSize = Math.Max(8f, font.LineSpacing * 0.75f);
            descriptor = new FontDescriptor("NotoSansSC", inferredSize, false);
            lock (Gate)
            {
                if (!Fonts.TryGetValue(font, out var existing)) Fonts.Add(font, descriptor);
                else descriptor = existing;
            }
            return descriptor;
        }
    }
}
