using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.Drawing.Text;
using System.Runtime.CompilerServices;
using Microsoft.Xna.Framework;
using Microsoft.Xna.Framework.Graphics;
using DrawingColor = System.Drawing.Color;
using XnaColor = Microsoft.Xna.Framework.Color;
using XnaRectangle = Microsoft.Xna.Framework.Rectangle;

namespace AtG.RuntimeText
{
    internal sealed class DynamicGlyph
    {
        public Texture2D Texture;
        public XnaRectangle Source;
        public float Advance;
        public float LineHeight;
    }

    internal sealed class DynamicGlyphAtlas
    {
        private sealed class PendingGlyph
        {
            public FontDescriptor Descriptor;
            public char Character;
        }

        private const int AtlasPageSize = 1024;
        private const int MaximumAtlasPages = 8;
        private const int GraphicsTextureSlotCount = 16;
        private const int VertexTextureSlotCount = 4;
        public const long MaximumTextureBytes =
            (long)AtlasPageSize * AtlasPageSize * 4L * MaximumAtlasPages;
        private readonly GraphicsDevice _device;
        private readonly object _gate = new object();
        private readonly Dictionary<string, DynamicGlyph> _glyphs = new Dictionary<string, DynamicGlyph>();
        private readonly Texture2D[] _pages = new Texture2D[MaximumAtlasPages];
        private readonly GlyphAtlasCacheState _state =
            new GlyphAtlasCacheState(AtlasPageSize, AtlasPageSize, MaximumAtlasPages);
        private readonly DeferredGlyphQueue<PendingGlyph> _pending =
            new DeferredGlyphQueue<PendingGlyph>();
        private int _pageCount;
        private bool _isResetting;

        public DynamicGlyphAtlas(GraphicsDevice device)
        {
            if (device == null) throw new ArgumentNullException("device");
            _device = device;
            _device.DeviceResetting += OnDeviceResetting;
            _device.DeviceReset += OnDeviceReset;
            if (_device.IsDisposed) _state.MarkFaulted();
        }

        public GlyphCacheDiagnostics GetDiagnostics()
        {
            lock (_gate)
            {
                ObserveInvalidResources();
                return _state.GetDiagnostics();
            }
        }

        public DynamicGlyph GetGlyph(FontDescriptor descriptor, char character, bool deferUpload)
        {
            var key = descriptor.CacheKey + "|" + ((int)character).ToString("X4");
            lock (_gate)
            {
                ObserveInvalidResources();
                if (_device.IsDisposed || _isResetting || _state.GetDiagnostics().IsFaulted)
                {
                    RuntimeTextTrace.Write(_device.IsDisposed
                        ? "graphics-device-disposed"
                        : "atlas-faulted", character.ToString(), descriptor, null);
                    return null;
                }

                DynamicGlyph glyph;
                if (_glyphs.TryGetValue(key, out glyph)) return glyph;
                if (deferUpload)
                {
                    if (_pending.Enqueue(key, new PendingGlyph
                    {
                        Descriptor = descriptor,
                        Character = character,
                    }))
                        RuntimeTextTrace.Write("glyph-upload-deferred", character.ToString(), descriptor, null);
                    return null;
                }

                using (var bitmap = RenderGlyph(descriptor, character, out var advance, out var lineHeight))
                {
                    var pixels = GetPremultipliedPixels(bitmap);
                    try
                    {
                        GlyphAtlasAllocation allocation;
                        if (!_state.TryAllocate(bitmap.Width, bitmap.Height, out allocation))
                        {
                            RuntimeTextTrace.Write("texture-budget-full", character.ToString(), descriptor, null);
                            return null;
                        }

                        var page = GetOrCreatePage(allocation.PageIndex);
                        UnbindTexture(page);
                        var bounds = new XnaRectangle(allocation.X, allocation.Y,
                            allocation.Width, allocation.Height);
                        page.SetData(0, bounds, pixels, 0, pixels.Length);
                        glyph = new DynamicGlyph
                        {
                            Texture = page,
                            Source = bounds,
                            Advance = advance,
                            LineHeight = lineHeight,
                        };
                        _glyphs.Add(key, glyph);
                        _state.RecordGlyphCached();
                    }
                    catch (Exception ex)
                    {
                        _state.MarkFaulted();
                        RuntimeTextTrace.Write("atlas-page-faulted", character.ToString(), descriptor, ex);
                        return null;
                    }
                    return glyph;
                }
            }
        }

        public void FlushPending()
        {
            var pending = _pending.Drain();
            foreach (var item in pending)
                GetGlyph(item.Descriptor, item.Character, false);
        }

        private Texture2D GetOrCreatePage(int pageIndex)
        {
            if (pageIndex < _pageCount)
            {
                var existing = _pages[pageIndex];
                if (existing == null || existing.IsDisposed)
                    throw new ObjectDisposedException("atlasPage");
                return existing;
            }
            if (pageIndex != _pageCount || pageIndex >= MaximumAtlasPages)
                throw new InvalidOperationException("Atlas allocator and texture pages are out of sync.");

            var page = new Texture2D(_device, AtlasPageSize, AtlasPageSize, false, SurfaceFormat.Color);
            _pages[pageIndex] = page;
            _pageCount++;
            _state.RecordPageCreated(pageIndex);
            return page;
        }

        private void ObserveInvalidResources()
        {
            if (_device.IsDisposed)
            {
                _state.MarkFaulted();
                return;
            }

            for (var pageIndex = 0; pageIndex < _pageCount; pageIndex++)
            {
                var page = _pages[pageIndex];
                if (page != null && !page.IsDisposed) continue;
                _state.MarkFaulted();
                return;
            }
        }

        private void OnDeviceResetting(object sender, EventArgs args)
        {
            lock (_gate)
            {
                _isResetting = true;
                _state.MarkFaulted();
            }
        }

        private void OnDeviceReset(object sender, EventArgs args)
        {
            lock (_gate)
            {
                _isResetting = false;
                if (_device.IsDisposed)
                {
                    _state.MarkFaulted();
                    return;
                }

                var livePages = 0;
                for (var pageIndex = 0; pageIndex < _pageCount; pageIndex++)
                {
                    var page = _pages[pageIndex];
                    if (page != null && !page.IsDisposed) livePages++;
                }

                var action = GlyphAtlasResetDecision.Evaluate(_pageCount, livePages);
                if (action == GlyphAtlasResetAction.RetainLivePages)
                {
                    // XNA owns resource reset semantics. Retaining the same objects also
                    // keeps Deferred SpriteBatch commands valid and preserves the budget.
                    _state.RecoverRetainedResourcesAfterDeviceReset();
                    return;
                }
                if (action == GlyphAtlasResetAction.ReleaseAllPages)
                {
                    for (var pageIndex = 0; pageIndex < _pageCount; pageIndex++)
                        _pages[pageIndex] = null;
                    _pageCount = 0;
                    _glyphs.Clear();
                    _pending.Drain();
                    _state.ResetAfterResourcesReleased();
                    return;
                }

                // A partial release cannot be accounted safely. Keep the full ledger
                // charged and refuse new allocations rather than exceeding 32 MiB.
                _state.MarkFaulted();
                RuntimeTextTrace.Write("atlas-reset-partial-release", null, null, null);
            }
        }

        private void UnbindTexture(Texture2D texture)
        {
            var pixelSlots = TextureBindingSlots.FindReferenceSlots<Texture>(texture,
                GraphicsTextureSlotCount, slot => _device.Textures[slot]);
            foreach (var slot in pixelSlots) _device.Textures[slot] = null;

            var vertexSlots = TextureBindingSlots.FindReferenceSlots<Texture>(texture,
                VertexTextureSlotCount, slot => _device.VertexTextures[slot]);
            foreach (var slot in vertexSlots) _device.VertexTextures[slot] = null;
        }

        private static XnaColor[] GetPremultipliedPixels(Bitmap bitmap)
        {
            var pixels = new XnaColor[bitmap.Width * bitmap.Height];
            for (var y = 0; y < bitmap.Height; y++)
                for (var x = 0; x < bitmap.Width; x++)
                {
                    var pixel = bitmap.GetPixel(x, y);
                    // SpriteBatch.AlphaBlend expects premultiplied alpha.
                    pixels[y * bitmap.Width + x] = new XnaColor(pixel.A, pixel.A, pixel.A, pixel.A);
                }
            return pixels;
        }

        private static Bitmap RenderGlyph(FontDescriptor descriptor, char character,
            out float advance, out float lineHeight)
        {
            var font = PrivateFontProvider.GetFont(descriptor);
            using (var measureBitmap = new Bitmap(1, 1))
            using (var graphics = System.Drawing.Graphics.FromImage(measureBitmap))
            {
                graphics.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
                var size = graphics.MeasureString(character.ToString(), font,
                    new PointF(0, 0), StringFormat.GenericTypographic);
                advance = Math.Max(1f, size.Width);
                lineHeight = Math.Max(1f, font.GetHeight(graphics));
                var bitmap = new Bitmap(Math.Max(2, (int)Math.Ceiling(size.Width) + 4),
                    Math.Max(2, (int)Math.Ceiling(lineHeight) + 4), PixelFormat.Format32bppArgb);
                using (var target = System.Drawing.Graphics.FromImage(bitmap))
                {
                    target.Clear(DrawingColor.Transparent);
                    target.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
                    target.DrawString(character.ToString(), font, Brushes.White,
                        new PointF(1, 1), StringFormat.GenericTypographic);
                }
                return bitmap;
            }
        }

    }

    internal static class GlyphAtlasRegistry
    {
        private static readonly ConditionalWeakTable<GraphicsDevice, DynamicGlyphAtlas> Atlases =
            new ConditionalWeakTable<GraphicsDevice, DynamicGlyphAtlas>();
        public static DynamicGlyphAtlas Get(GraphicsDevice device) { return Atlases.GetValue(device, d => new DynamicGlyphAtlas(d)); }
        public static GlyphCacheDiagnostics GetDiagnostics(GraphicsDevice device)
        {
            return Get(device).GetDiagnostics();
        }
        public static void FlushPending(GraphicsDevice device)
        {
            DynamicGlyphAtlas atlas;
            if (device != null && Atlases.TryGetValue(device, out atlas)) atlas.FlushPending();
        }
    }
}
