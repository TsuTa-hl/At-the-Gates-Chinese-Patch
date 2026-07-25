using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.Drawing.Text;
using System.IO;
using DrawingRectangle = System.Drawing.Rectangle;

namespace AtG.RuntimeText
{
    internal sealed class GlyphRequest
    {
        public GlyphRequest(FontDescriptor descriptor, char character, int priority, bool isWarmup)
        {
            Descriptor = descriptor;
            Character = character;
            Priority = priority;
            IsWarmup = isWarmup;
            Key = GlyphMetricsCache.CreateKey(descriptor, character);
        }

        public readonly string Key;
        public readonly FontDescriptor Descriptor;
        public readonly char Character;
        public int Priority;
        public bool IsWarmup;
    }

    internal sealed class PreparedGlyph
    {
        public GlyphRequest Request;
        public int Width;
        public int Height;
        public byte[] Pixels;
        public float Advance;
        public float LineHeight;
    }

    internal sealed class GlyphRasterizer : IDisposable
    {
        private readonly PrivateFontCollection _collection = new PrivateFontCollection();
        private readonly Dictionary<string, Font> _fonts =
            new Dictionary<string, Font>(StringComparer.Ordinal);
        private readonly Bitmap _measureBitmap = new Bitmap(1, 1);
        private readonly Graphics _measureGraphics;
        private FontFamily _fallbackFamily;

        public GlyphRasterizer()
        {
            var fontRoot = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "Content", "Fonts");
            AddIfPresent(Path.Combine(fontRoot, "NotoSansSC-Regular.otf"));
            AddIfPresent(Path.Combine(fontRoot, "NotoSansSC-Bold.otf"));
            _measureGraphics = Graphics.FromImage(_measureBitmap);
            _measureGraphics.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
        }

        public PreparedGlyph Render(GlyphRequest request)
        {
            if (request == null) throw new ArgumentNullException("request");
            var font = GetFont(request.Descriptor);
            var text = request.Character.ToString();
            var size = _measureGraphics.MeasureString(text, font,
                new PointF(0, 0), StringFormat.GenericTypographic);
            var measuredAdvance = Math.Max(1f, size.Width);
            var measuredLineHeight = Math.Max(1f, font.GetHeight(_measureGraphics));
            var metrics = GlyphMetricsCache.PublishMeasured(
                request.Descriptor, request.Character, measuredAdvance, measuredLineHeight);
            var width = Math.Max(2, (int)Math.Ceiling(size.Width) + 4);
            var height = Math.Max(2, (int)Math.Ceiling(measuredLineHeight) + 4);

            using (var bitmap = new Bitmap(width, height, PixelFormat.Format32bppArgb))
            {
                using (var target = Graphics.FromImage(bitmap))
                {
                    target.Clear(Color.Transparent);
                    target.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
                    target.DrawString(text, font, Brushes.White,
                        new PointF(1, 1), StringFormat.GenericTypographic);
                }
                var pixels = ReadPixels(bitmap);
                return new PreparedGlyph
                {
                    Request = request,
                    Width = width,
                    Height = height,
                    Pixels = pixels,
                    Advance = metrics.Advance,
                    LineHeight = metrics.LineHeight,
                };
            }
        }

        public void Dispose()
        {
            foreach (var font in _fonts.Values) font.Dispose();
            _fonts.Clear();
            _measureGraphics.Dispose();
            _measureBitmap.Dispose();
            if (_fallbackFamily != null) _fallbackFamily.Dispose();
            _collection.Dispose();
        }

        private Font GetFont(FontDescriptor descriptor)
        {
            Font existing;
            if (_fonts.TryGetValue(descriptor.CacheKey, out existing)) return existing;
            var style = descriptor.Bold ? FontStyle.Bold : FontStyle.Regular;
            FontFamily family = null;
            foreach (var candidate in _collection.Families)
            {
                if (!candidate.IsStyleAvailable(style)) continue;
                family = candidate;
                break;
            }
            if (family == null && _collection.Families.Length > 0)
                family = _collection.Families[0];
            if (family == null)
            {
                if (_fallbackFamily == null) _fallbackFamily = new FontFamily("Microsoft YaHei");
                family = _fallbackFamily;
            }
            if (!family.IsStyleAvailable(style)) style = FontStyle.Regular;
            var font = new Font(family, descriptor.RasterSize, style, GraphicsUnit.Pixel);
            _fonts.Add(descriptor.CacheKey, font);
            return font;
        }

        private static byte[] ReadPixels(Bitmap bitmap)
        {
            var bounds = new DrawingRectangle(0, 0, bitmap.Width, bitmap.Height);
            var data = bitmap.LockBits(bounds, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
            try
            {
                return GlyphAlphaConverter.FromBgra(
                    data.Scan0, bitmap.Width, bitmap.Height, data.Stride);
            }
            finally
            {
                bitmap.UnlockBits(data);
            }
        }

        private void AddIfPresent(string path)
        {
            if (File.Exists(path)) _collection.AddFontFile(path);
            else RuntimeTextTrace.Write("missing-font-file", path, null,
                new FileNotFoundException("Runtime font file was not found.", path));
        }
    }
}
