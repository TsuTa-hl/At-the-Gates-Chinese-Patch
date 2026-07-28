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

    internal enum GlyphUploadStatus
    {
        Uploaded,
        AlreadyCached,
        Deferred,
        WarmBudgetReached,
        Rejected,
    }

    internal sealed class GlyphUploadResult
    {
        public GlyphUploadResult(GlyphUploadStatus status, bool pageCreated)
        {
            Status = status;
            PageCreated = pageCreated;
        }

        public GlyphUploadStatus Status { get; private set; }
        public bool PageCreated { get; private set; }
    }

    internal sealed class DynamicGlyphAtlas
    {
        private sealed class PendingGlyph
        {
            public FontDescriptor Descriptor;
            public char Character;
        }

        internal const int AtlasPageSize = 1024;
        internal const int MaximumAtlasPages = 8;
        private const int GraphicsTextureSlotCount = 16;
        private const int VertexTextureSlotCount = 4;
        public const long MaximumTextureBytes =
            (long)AtlasPageSize * AtlasPageSize * 4L * MaximumAtlasPages;
        private readonly GraphicsDevice _device;
        private readonly object _gate = new object();
        private readonly Dictionary<string, Dictionary<char, DynamicGlyph>> _glyphs =
            new Dictionary<string, Dictionary<char, DynamicGlyph>>(StringComparer.Ordinal);
        private readonly Texture2D[] _pages = new Texture2D[MaximumAtlasPages];
        private readonly GlyphAtlasCacheState _state =
            new GlyphAtlasCacheState(AtlasPageSize, AtlasPageSize, MaximumAtlasPages);
        private readonly DeferredGlyphQueue<PendingGlyph> _pending =
            new DeferredGlyphQueue<PendingGlyph>();
        private readonly HashSet<int> _unboundPagesThisPump = new HashSet<int>();
        private readonly Dictionary<string, PendingGlyph> _observed =
            new Dictionary<string, PendingGlyph>(StringComparer.Ordinal);
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
                if (TryGetCachedGlyph(descriptor.CacheKey, character, out glyph))
                {
                    RuntimeTextPerformance.RecordGlyphLookup(true);
                    return glyph;
                }
                RuntimeTextPerformance.RecordGlyphLookup(false);
                var key = GlyphMetricsCache.CreateKey(descriptor, character);
                if (!_observed.ContainsKey(key))
                    _observed.Add(key, new PendingGlyph
                    {
                        Descriptor = descriptor,
                        Character = character,
                    });
                if (!RuntimeGlyphScheduler.IsLegacySync)
                {
                    RuntimeGlyphScheduler.RequestLive(descriptor, character);
                    return null;
                }
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
                        AddCachedGlyph(descriptor.CacheKey, character, glyph);
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

        public void FlushPendingLegacy()
        {
            var pending = _pending.Drain();
            foreach (var item in pending)
                GetGlyph(item.Descriptor, item.Character, false);
        }

        public int PageCount
        {
            get { lock (_gate) return _pageCount; }
        }

        public void BeginUploadPump()
        {
            lock (_gate) _unboundPagesThisPump.Clear();
        }

        public void EndUploadPump()
        {
            lock (_gate) _unboundPagesThisPump.Clear();
        }

        public bool RequiresNewPage(int width, int height, int maximumPageCount)
        {
            lock (_gate)
            {
                ObserveInvalidResources();
                return !_state.CanAllocateOnExistingPage(width, height, maximumPageCount);
            }
        }

        public GlyphUploadResult UploadPrepared(PreparedGlyph prepared, int maximumPageCount)
        {
            if (prepared == null) throw new ArgumentNullException("prepared");
            var request = prepared.Request;
            lock (_gate)
            {
                ObserveInvalidResources();
                if (_device.IsDisposed || _isResetting || _state.GetDiagnostics().IsFaulted)
                    return new GlyphUploadResult(GlyphUploadStatus.Deferred, false);

                DynamicGlyph existing;
                if (TryGetCachedGlyph(
                        request.Descriptor.CacheKey, request.Character, out existing))
                    return new GlyphUploadResult(GlyphUploadStatus.AlreadyCached, false);

                var canUseExisting = _state.CanAllocateOnExistingPage(
                    prepared.Width, prepared.Height, maximumPageCount);
                var allowNewPage = _pageCount < maximumPageCount;
                GlyphAtlasAllocation allocation;
                if (!_state.TryAllocate(prepared.Width, prepared.Height, maximumPageCount,
                        allowNewPage, !request.IsWarmup, out allocation))
                {
                    if (request.IsWarmup && !canUseExisting && _pageCount >= maximumPageCount)
                        return new GlyphUploadResult(GlyphUploadStatus.WarmBudgetReached, false);
                    RuntimeTextTrace.Write("texture-budget-full",
                        request.Character.ToString(), request.Descriptor, null);
                    return new GlyphUploadResult(GlyphUploadStatus.Rejected, false);
                }

                var pageCreated = allocation.PageIndex >= _pageCount;
                try
                {
                    var page = GetOrCreatePage(allocation.PageIndex);
                    if (_unboundPagesThisPump.Add(allocation.PageIndex)) UnbindTexture(page);
                    var bounds = new XnaRectangle(allocation.X, allocation.Y,
                        allocation.Width, allocation.Height);
                    page.SetData(0, bounds, prepared.Pixels, 0, prepared.Pixels.Length);
                    AddCachedGlyph(request.Descriptor.CacheKey, request.Character,
                        new DynamicGlyph
                    {
                        Texture = page,
                        Source = bounds,
                        Advance = prepared.Advance,
                        LineHeight = prepared.LineHeight,
                    });
                    _state.RecordGlyphCached();
                    return new GlyphUploadResult(GlyphUploadStatus.Uploaded, pageCreated);
                }
                catch (Exception ex)
                {
                    _state.MarkFaulted();
                    RuntimeTextTrace.Write("atlas-page-faulted",
                        request.Character.ToString(), request.Descriptor, ex);
                    return new GlyphUploadResult(GlyphUploadStatus.Rejected, pageCreated);
                }
            }
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

        private bool TryGetCachedGlyph(
            string descriptorKey, char character, out DynamicGlyph glyph)
        {
            Dictionary<char, DynamicGlyph> byCharacter;
            if (_glyphs.TryGetValue(descriptorKey, out byCharacter) &&
                byCharacter.TryGetValue(character, out glyph))
                return true;
            glyph = null;
            return false;
        }

        private void AddCachedGlyph(
            string descriptorKey, char character, DynamicGlyph glyph)
        {
            Dictionary<char, DynamicGlyph> byCharacter;
            if (!_glyphs.TryGetValue(descriptorKey, out byCharacter))
            {
                byCharacter = new Dictionary<char, DynamicGlyph>();
                _glyphs.Add(descriptorKey, byCharacter);
            }
            byCharacter.Add(character, glyph);
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
                    var observed = new List<PendingGlyph>(_observed.Values);
                    for (var pageIndex = 0; pageIndex < _pageCount; pageIndex++)
                        _pages[pageIndex] = null;
                    _pageCount = 0;
                    _glyphs.Clear();
                    _pending.Drain();
                    _state.ResetAfterResourcesReleased();
                    RuntimeTextPerformance.RecordDeviceReset();
                    RuntimeGlyphWarmset.RequeueAll();
                    foreach (var item in observed)
                        RuntimeGlyphScheduler.RequestLive(item.Descriptor, item.Character);
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
            var bounds = new System.Drawing.Rectangle(0, 0, bitmap.Width, bitmap.Height);
            var data = bitmap.LockBits(bounds, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
            try
            {
                var bytes = GlyphAlphaConverter.FromBgra(
                    data.Scan0, bitmap.Width, bitmap.Height, data.Stride);
                var pixels = new XnaColor[bitmap.Width * bitmap.Height];
                for (var index = 0; index < pixels.Length; index++)
                {
                    var alpha = bytes[index * 4 + 3];
                    pixels[index] = new XnaColor(alpha, alpha, alpha, alpha);
                }
                return pixels;
            }
            finally
            {
                bitmap.UnlockBits(data);
            }
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
            if (device == null) return;
            if (RuntimeGlyphScheduler.IsLegacySync)
            {
                if (Atlases.TryGetValue(device, out atlas)) atlas.FlushPendingLegacy();
                return;
            }
            RuntimeGlyphScheduler.PumpReadyUploads(device);
        }
    }
}
