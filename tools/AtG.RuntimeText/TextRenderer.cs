using System;
using System.Text;
using Microsoft.Xna.Framework;
using Microsoft.Xna.Framework.Graphics;

namespace AtG.RuntimeText
{
    public static class TextRenderer
    {
        public static GlyphCacheDiagnostics GetGlyphCacheDiagnostics(GraphicsDevice device)
        {
            if (device == null) throw new ArgumentNullException("device");
            return GlyphAtlasRegistry.GetDiagnostics(device);
        }

        public static Vector2 MeasureString(SpriteFont font, string text)
        {
            if (font == null) throw new ArgumentNullException("font");
            if (text == null) throw new ArgumentNullException("text");
            if (!NeedsRuntimeProcessing(font, text))
            {
                var nativeSize = font.MeasureString(text);
                TraceResult("measure", text, font, null, null, nativeSize, 0);
                return nativeSize;
            }
            var descriptor = FontRegistry.Resolve(font);
            try
            {
                var width = 0f;
                var maximumWidth = 0f;
                var height = Math.Max(font.LineSpacing, descriptor.Size);
                var currentLineHeight = height;
                var missingGlyphs = 0;
                var originalRun = new StringBuilder();
                for (var index = 0; index < text.Length; index++)
                {
                    var character = text[index];
                    if (character == '\r') continue;
                    if (CjkText.IsIgnorableFormat(character)) continue;
                    if (character == '\n')
                    {
                        width += FlushOriginalMeasure(font, originalRun);
                        maximumWidth = Math.Max(maximumWidth, width);
                        width = 0;
                        height += currentLineHeight;
                        currentLineHeight = Math.Max(font.LineSpacing, descriptor.Size);
                    }
                    else if (CjkText.RequiresDynamicGlyph(character))
                    {
                        width += FlushOriginalMeasure(font, originalRun);
                        var glyphSize = MeasureDynamic(descriptor, character);
                        width += glyphSize.X;
                        currentLineHeight = Math.Max(currentLineHeight, glyphSize.Y);
                    }
                    else if (HasOriginalGlyph(font, character)) originalRun.Append(character);
                    else
                    {
                        originalRun.Append('?');
                        missingGlyphs++;
                        RuntimeTextTrace.Write("missing-original-glyph", character.ToString(), descriptor, null);
                    }
                }
                width += FlushOriginalMeasure(font, originalRun);
                maximumWidth = Math.Max(maximumWidth, width);
                var measured = new Vector2(maximumWidth, height);
                RuntimeTextTrace.Write("measure", text, descriptor, null,
                    CreateMetrics(null, measured, missingGlyphs));
                return measured;
            }
            catch (Exception ex)
            {
                var sanitized = Sanitize(font, text);
                var fallbackSize = font.MeasureString(sanitized);
                RuntimeTextTrace.Write("measure-fallback", text, descriptor, ex,
                    CreateMetrics(null, fallbackSize, CountReplacements(sanitized)));
                return fallbackSize;
            }
        }

        public static Vector2 MeasureString(SpriteFont font, StringBuilder text)
        {
            if (text == null) throw new ArgumentNullException("text");
            return MeasureString(font, text.ToString());
        }

        public static void DrawString(SpriteBatch batch, SpriteFont font, string text, Vector2 position, Color color)
        {
            DrawString(batch, font, text, position, color, 0f, Vector2.Zero, 1f, SpriteEffects.None, 0f);
        }

        public static void DrawString(SpriteBatch batch, SpriteFont font, string text, Vector2 position,
            Color color, float rotation, Vector2 origin, float scale,
            SpriteEffects effects, float layerDepth)
        {
            if (batch == null) throw new ArgumentNullException("batch");
            if (font == null) throw new ArgumentNullException("font");
            if (text == null) throw new ArgumentNullException("text");
            if (!NeedsRuntimeProcessing(font, text))
            {
                batch.DrawString(font, text, position, color, rotation, origin, scale, effects, layerDepth);
                if (RuntimeTextTrace.IsEnabled)
                    TraceResult("draw", text, font, null, position,
                        font.MeasureString(text) * scale, 0);
                return;
            }

            var descriptor = FontRegistry.Resolve(font);
            try
            {
                var atlas = GlyphAtlasRegistry.Get(batch.GraphicsDevice);
                var x = 0f;
                var y = 0f;
                var maximumWidth = 0f;
                var lineHeight = Math.Max(font.LineSpacing, descriptor.Size);
                var missingGlyphs = 0;
                var originalRun = new StringBuilder();
                for (var index = 0; index < text.Length; index++)
                {
                    var character = text[index];
                    if (character == '\r') continue;
                    if (CjkText.IsIgnorableFormat(character)) continue;
                    if (character == '\n')
                    {
                        x += DrawOriginalRun(batch, font, originalRun, x, y, position, color,
                            rotation, origin, scale, effects, layerDepth);
                        maximumWidth = Math.Max(maximumWidth, x);
                        x = 0;
                        y += lineHeight;
                        continue;
                    }
                    if (!CjkText.RequiresDynamicGlyph(character))
                    {
                        if (HasOriginalGlyph(font, character)) originalRun.Append(character);
                        else
                        {
                            originalRun.Append('?');
                            missingGlyphs++;
                            RuntimeTextTrace.Write("missing-original-glyph", character.ToString(), descriptor, null);
                        }
                        continue;
                    }
                    x += DrawOriginalRun(batch, font, originalRun, x, y, position, color,
                        rotation, origin, scale, effects, layerDepth);
                    var glyph = atlas.GetGlyph(descriptor, character,
                        SpriteBatchLifecycle.IsActive(batch));
                    if (glyph == null)
                    {
                        originalRun.Append('?');
                        missingGlyphs++;
                        continue;
                    }
                    var glyphPosition = Transform(new Vector2(x + 1, y + 1), position, origin, rotation, scale);
                    batch.Draw(glyph.Texture, glyphPosition, glyph.Source, color, rotation,
                        Vector2.Zero, scale, effects, layerDepth);
                    x += glyph.Advance;
                }
                x += DrawOriginalRun(batch, font, originalRun, x, y, position, color,
                    rotation, origin, scale, effects, layerDepth);
                maximumWidth = Math.Max(maximumWidth, x);
                RuntimeTextTrace.Write("draw", text, descriptor, null,
                    CreateMetrics(position,
                        new Vector2(maximumWidth * scale, (y + lineHeight) * scale),
                        missingGlyphs));
            }
            catch (Exception ex)
            {
                var sanitized = Sanitize(font, text);
                batch.DrawString(font, sanitized, position, color, rotation, origin, scale, effects, layerDepth);
                RuntimeTextTrace.Write("draw-fallback", text, descriptor, ex,
                    CreateMetrics(position, font.MeasureString(sanitized) * scale,
                        CountReplacements(sanitized)));
            }
        }

        private static void TraceResult(string eventName, string text, SpriteFont font,
            Exception error, Vector2? position, Vector2 size, int missingGlyphs)
        {
            if (!RuntimeTextTrace.IsEnabled && error == null) return;
            FontDescriptor descriptor = null;
            try { descriptor = FontRegistry.Resolve(font); }
            catch { }
            RuntimeTextTrace.Write(eventName, text, descriptor, error,
                CreateMetrics(position, size, missingGlyphs));
        }

        private static RuntimeTextTraceMetrics CreateMetrics(Vector2? position,
            Vector2 size, int missingGlyphs)
        {
            return new RuntimeTextTraceMetrics
            {
                X = position.HasValue ? (float?)position.Value.X : null,
                Y = position.HasValue ? (float?)position.Value.Y : null,
                Width = size.X,
                Height = size.Y,
                MissingGlyphs = missingGlyphs,
            };
        }

        private static int CountReplacements(string text)
        {
            var count = 0;
            for (var index = 0; index < text.Length; index++)
                if (text[index] == '?') count++;
            return count;
        }

        private static float FlushOriginalMeasure(SpriteFont font, StringBuilder run)
        {
            if (run.Length == 0) return 0f;
            var width = font.MeasureString(run).X;
            run.Length = 0;
            return width;
        }

        private static Vector2 MeasureDynamic(FontDescriptor descriptor, char character)
        {
            var font = PrivateFontProvider.GetFont(descriptor);
            using (var bitmap = new System.Drawing.Bitmap(1, 1))
            using (var graphics = System.Drawing.Graphics.FromImage(bitmap))
            {
                var size = graphics.MeasureString(character.ToString(), font,
                    new System.Drawing.PointF(0, 0), System.Drawing.StringFormat.GenericTypographic);
                return new Vector2(size.Width, font.GetHeight(graphics));
            }
        }

        private static float DrawOriginalRun(SpriteBatch batch, SpriteFont font, StringBuilder run,
            float x, float y, Vector2 position, Color color, float rotation, Vector2 origin,
            float scale, SpriteEffects effects, float layerDepth)
        {
            if (run.Length == 0) return 0f;
            var value = run.ToString();
            run.Length = 0;
            var localPosition = Transform(new Vector2(x, y), position, origin, rotation, scale);
            batch.DrawString(font, value, localPosition, color, rotation, Vector2.Zero,
                scale, effects, layerDepth);
            return font.MeasureString(value).X;
        }

        private static Vector2 Transform(Vector2 local, Vector2 position, Vector2 origin,
            float rotation, float scale)
        {
            local -= origin;
            var cosine = (float)Math.Cos(rotation);
            var sine = (float)Math.Sin(rotation);
            return position + new Vector2(
                (local.X * cosine - local.Y * sine) * scale,
                (local.X * sine + local.Y * cosine) * scale);
        }

        private static bool NeedsRuntimeProcessing(SpriteFont font, string text)
        {
            for (var index = 0; index < text.Length; index++)
            {
                var character = text[index];
                if (CjkText.RequiresDynamicGlyph(character) ||
                    CjkText.IsIgnorableFormat(character) ||
                    !HasOriginalGlyph(font, character)) return true;
            }
            return false;
        }

        private static bool HasOriginalGlyph(SpriteFont font, char character)
        {
            return character == '\r' || character == '\n' || font.Characters.Contains(character);
        }

        private static string Sanitize(SpriteFont font, string text)
        {
            var builder = new StringBuilder(text.Length);
            foreach (var character in text)
            {
                if (CjkText.IsIgnorableFormat(character)) continue;
                builder.Append(CjkText.RequiresDynamicGlyph(character) || !HasOriginalGlyph(font, character)
                    ? '?'
                    : character);
            }
            return builder.ToString();
        }
    }
}
