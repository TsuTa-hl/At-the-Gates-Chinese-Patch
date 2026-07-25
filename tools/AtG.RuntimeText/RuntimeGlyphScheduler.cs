using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Reflection;
using System.Threading;
using Microsoft.Xna.Framework.Graphics;

namespace AtG.RuntimeText
{
    public static class RuntimeGlyphScheduler
    {
        public const double UploadBudgetMilliseconds = 2d;
        public const int MaximumUploadsPerFrame = 16;
        public const int MaximumPageCreationsPerFrame = 1;
        public const int MaximumPendingRequests = 4096;
        public const int MaximumWarmRequests = 3584;
        public const int MaximumReadyGlyphs = 256;
        public const int MaximumReadyBytes = 4 * 1024 * 1024;
        public const int MaximumWarmAtlasPages = 6;

        private const int PriorityCount = 4;
        private const int LivePriority = 0;
        private const int StartupWarmMinimumPriority = 1;
        private const int StartupWarmMaximumPriority = PriorityCount - 1;
        private const int StartupWarmupTimeoutMilliseconds = 6000;
        private static readonly object Gate = new object();
        private static readonly object BudgetGate = new object();
        private static readonly Dictionary<string, GlyphRequest> Active =
            new Dictionary<string, GlyphRequest>(StringComparer.Ordinal);
        private static readonly PriorityDeduplicatingQueue<GlyphRequest> Pending =
            new PriorityDeduplicatingQueue<GlyphRequest>(
                PriorityCount, MaximumPendingRequests);
        private static readonly PriorityDeduplicatingQueue<PreparedGlyph> Ready =
            new PriorityDeduplicatingQueue<PreparedGlyph>(
                PriorityCount, MaximumReadyGlyphs);
        private static readonly FrameUploadBudget Budget =
            new FrameUploadBudget(UploadBudgetMilliseconds, Stopwatch.Frequency,
                MaximumUploadsPerFrame, MaximumPageCreationsPerFrame);
        private static readonly bool LegacySync =
            string.Equals(Environment.GetEnvironmentVariable("ATG_RUNTIME_TEXT_GLYPH_MODE"),
                "LegacySync", StringComparison.OrdinalIgnoreCase);
        private static Thread _worker;
        private static bool _stopping;
        private static bool _workerFaulted;
        private static bool _startupGraphicsPrepared;
        private static int _readyBytes;

        static RuntimeGlyphScheduler()
        {
            AppDomain.CurrentDomain.ProcessExit += delegate { StopWorker(); };
        }

        public static bool IsLegacySync { get { return LegacySync; } }
        public static string ModeName { get { return LegacySync ? "LegacySync" : "Budgeted"; } }

        // Invoked from GameCore's constructor, before XNA begins its first
        // Draw. The worker only uses GDI+ and the packaged font file, so it
        // can rasterize the deterministic warmset while the game starts.
        public static void PrimeWarmset()
        {
            RuntimeGlyphWarmset.Prime();
        }

        // Called at GameCore.LoadContent entry, after XNA has a GraphicsDevice
        // but before its first Draw.  The constructor hook has already queued
        // the deterministic warmset on the worker. Upload every queued warm
        // priority while loading owns the main thread, so the selected first
        // displays do not consume their normal 2 ms Draw-frame budget.
        public static void PrepareStartupGraphics(object game)
        {
            if (LegacySync || game == null) return;
            var device = ResolveGraphicsDevice(game);
            if (device == null || device.IsDisposed) return;
            lock (Gate)
            {
                if (_startupGraphicsPrepared) return;
                _startupGraphicsPrepared = true;
            }
            try
            {
                PumpStartupWarmUploads(device);
            }
            catch (Exception ex)
            {
                RuntimeTextTrace.Write("glyph-startup-upload-failed", null, null, ex);
            }
        }

        public static void BeginFrame()
        {
            lock (BudgetGate) Budget.BeginFrame();
            RuntimeTextPerformance.BeginFrame(ModeName);
        }

        internal static GlyphMetrics GetMetrics(FontDescriptor descriptor, char character)
        {
            bool reserved;
            var metrics = GlyphMetricsCache.GetOrReserve(
                descriptor, character, out reserved);
            if (!LegacySync && reserved)
                Request(descriptor, character, LivePriority, false);
            return metrics;
        }

        internal static void RequestLive(FontDescriptor descriptor, char character)
        {
            if (!LegacySync) Request(descriptor, character, LivePriority, false);
        }

        internal static void RequestWarm(FontDescriptor descriptor, char character, int warmPriority)
        {
            if (LegacySync) return;
            var priority = Math.Max(1, Math.Min(PriorityCount - 1, warmPriority + 1));
            Request(descriptor, character, priority, true);
        }

        internal static void NotifyFallback()
        {
            RuntimeTextPerformance.RecordFallback();
        }

        internal static void PumpReadyUploads(GraphicsDevice device)
        {
            if (LegacySync || device == null || device.IsDisposed) return;
            lock (BudgetGate)
            {
                if (!Budget.IsStarted) Budget.BeginFrame();
            }

            var atlas = GlyphAtlasRegistry.Get(device);
            atlas.BeginUploadPump();
            try
            {
                while (true)
                {
                    PreparedGlyph prepared;
                    string key;
                    int ignoredPriority;
                    lock (Gate)
                    {
                        if (!Ready.TryPeek(out key, out prepared, out ignoredPriority)) break;
                    }

                    var maximumPages = prepared.Request.IsWarmup
                        ? MaximumWarmAtlasPages
                        : DynamicGlyphAtlas.MaximumAtlasPages;
                    var requiresPage = atlas.RequiresNewPage(
                        prepared.Width, prepared.Height, maximumPages);
                    var canAttempt = false;
                    lock (BudgetGate) canAttempt = Budget.CanAttempt(requiresPage);
                    if (!canAttempt)
                    {
                        RuntimeTextPerformance.RecordBudgetStop();
                        break;
                    }

                    lock (Gate)
                    {
                        PreparedGlyph dequeued;
                        string dequeuedKey;
                        if (!Ready.TryDequeue(
                                out dequeuedKey, out dequeued, out ignoredPriority))
                            continue;
                        prepared = dequeued;
                        key = dequeuedKey;
                        _readyBytes -= prepared.Pixels.Length;
                        Monitor.PulseAll(Gate);
                        RecordQueueDepthLocked();
                    }

                    var started = Stopwatch.GetTimestamp();
                    var result = atlas.UploadPrepared(prepared, maximumPages);
                    var elapsed = Math.Max(0L, Stopwatch.GetTimestamp() - started);
                    lock (BudgetGate)
                        Budget.RecordOperation(elapsed, result.PageCreated);
                    RuntimeTextPerformance.RecordUpload(
                        elapsed, result.Status == GlyphUploadStatus.Uploaded, result.PageCreated);
                    RuntimeTextPerformance.RecordAtlasPages(atlas.PageCount);

                    if (result.Status == GlyphUploadStatus.Deferred)
                    {
                        ReturnReady(prepared);
                        break;
                    }
                    Complete(prepared.Request);
                    if (result.Status == GlyphUploadStatus.WarmBudgetReached)
                        RuntimeTextPerformance.RecordWarmSkip();
                }
            }
            finally
            {
                atlas.EndUploadPump();
            }
        }

        private static GraphicsDevice ResolveGraphicsDevice(object game)
        {
            try
            {
                var property = game.GetType().GetProperty("GraphicsDevice",
                    BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
                return property == null ? null : property.GetValue(game, null) as GraphicsDevice;
            }
            catch (Exception ex)
            {
                RuntimeTextTrace.Write("glyph-startup-device-resolve-failed", null, null, ex);
                return null;
            }
        }

        private static void PumpStartupWarmUploads(GraphicsDevice device)
        {
            var atlas = GlyphAtlasRegistry.Get(device);
            var deadline = Stopwatch.GetTimestamp() +
                (long)(Stopwatch.Frequency * StartupWarmupTimeoutMilliseconds / 1000d);
            atlas.BeginUploadPump();
            try
            {
                while (true)
                {
                    PreparedGlyph prepared;
                    string key;
                    int priority;
                    lock (Gate)
                    {
                        if (!Ready.TryPeek(out key, out prepared, out priority) ||
                            priority < StartupWarmMinimumPriority ||
                            priority > StartupWarmMaximumPriority)
                        {
                            if (!HasStartupWarmRequestLocked() ||
                                Stopwatch.GetTimestamp() >= deadline) break;
                            Monitor.Wait(Gate, 2);
                            continue;
                        }
                        PreparedGlyph dequeued;
                        string dequeuedKey;
                        if (!Ready.TryDequeue(out dequeuedKey, out dequeued, out priority))
                            continue;
                        prepared = dequeued;
                        key = dequeuedKey;
                        _readyBytes -= prepared.Pixels.Length;
                        Monitor.PulseAll(Gate);
                        RecordQueueDepthLocked();
                    }

                    var result = atlas.UploadPrepared(prepared, MaximumWarmAtlasPages);
                    if (result.Status == GlyphUploadStatus.Deferred)
                    {
                        ReturnReady(prepared);
                        break;
                    }
                    Complete(prepared.Request);
                }
            }
            finally
            {
                atlas.EndUploadPump();
            }
        }

        private static bool HasStartupWarmRequestLocked()
        {
            foreach (var request in Active.Values)
            {
                if (request.IsWarmup &&
                    request.Priority >= StartupWarmMinimumPriority &&
                    request.Priority <= StartupWarmMaximumPriority)
                    return true;
            }
            return false;
        }

        private static void Request(FontDescriptor descriptor, char character,
            int priority, bool isWarmup)
        {
            if (descriptor == null || !CjkText.RequiresDynamicGlyph(character)) return;
            var key = GlyphMetricsCache.CreateKey(descriptor, character);
            lock (Gate)
            {
                GlyphRequest existing;
                if (Active.TryGetValue(key, out existing))
                {
                    if (priority < existing.Priority)
                    {
                        existing.Priority = priority;
                        if (!isWarmup) existing.IsWarmup = false;
                        Pending.Promote(key, priority);
                        Ready.Promote(key, priority);
                    }
                    else if (!isWarmup)
                    {
                        existing.IsWarmup = false;
                    }
                    return;
                }

                var activeLimit = isWarmup ? MaximumWarmRequests : MaximumPendingRequests;
                if (_workerFaulted || _stopping || Active.Count >= activeLimit)
                {
                    RuntimeTextTrace.Write("glyph-request-rejected",
                        character.ToString(), descriptor, null);
                    return;
                }

                var request = new GlyphRequest(descriptor, character, priority, isWarmup);
                if (!Pending.Enqueue(key, request, priority)) return;
                Active.Add(key, request);
                RuntimeTextPerformance.RecordRequest();
                EnsureWorkerLocked();
                RecordQueueDepthLocked();
                Monitor.PulseAll(Gate);
            }
        }

        private static void EnsureWorkerLocked()
        {
            if (_worker != null) return;
            _worker = new Thread(WorkerLoop)
            {
                IsBackground = true,
                Name = "AtG RuntimeText glyph rasterizer",
            };
            _worker.Start();
        }

        private static void WorkerLoop()
        {
            try
            {
                using (var rasterizer = new GlyphRasterizer())
                {
                    while (true)
                    {
                        GlyphRequest request = null;
                        string ignoredKey;
                        int ignoredPriority;
                        lock (Gate)
                        {
                            while (!_stopping &&
                                   !Pending.TryDequeue(
                                       out ignoredKey, out request, out ignoredPriority))
                                Monitor.Wait(Gate);
                            if (_stopping) return;
                        }
                        if (request == null) continue;

                        PreparedGlyph prepared;
                        var started = Stopwatch.GetTimestamp();
                        try
                        {
                            prepared = rasterizer.Render(request);
                        }
                        catch (Exception ex)
                        {
                            RuntimeTextTrace.Write("glyph-raster-failed",
                                request.Character.ToString(), request.Descriptor, ex);
                            Complete(request);
                            continue;
                        }
                        finally
                        {
                            RuntimeTextPerformance.RecordRaster(
                                Math.Max(0L, Stopwatch.GetTimestamp() - started));
                        }
                        if (prepared.Pixels.Length > MaximumReadyBytes)
                        {
                            RuntimeTextTrace.Write("glyph-ready-too-large",
                                request.Character.ToString(), request.Descriptor, null);
                            Complete(request);
                            continue;
                        }

                        lock (Gate)
                        {
                            while (!_stopping &&
                                   (Ready.Count >= MaximumReadyGlyphs ||
                                    _readyBytes + prepared.Pixels.Length > MaximumReadyBytes))
                                Monitor.Wait(Gate);
                            if (_stopping) return;
                            GlyphRequest active;
                            if (!Active.TryGetValue(request.Key, out active) ||
                                !ReferenceEquals(active, request)) continue;
                            Ready.Enqueue(request.Key, prepared, request.Priority);
                            _readyBytes += prepared.Pixels.Length;
                            RecordQueueDepthLocked();
                            Monitor.PulseAll(Gate);
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                lock (Gate)
                {
                    _workerFaulted = true;
                    Pending.Clear();
                    Ready.Clear();
                    Active.Clear();
                    _readyBytes = 0;
                    Monitor.PulseAll(Gate);
                }
                RuntimeTextTrace.Write("glyph-worker-faulted", null, null, ex);
            }
        }

        private static void ReturnReady(PreparedGlyph prepared)
        {
            lock (Gate)
            {
                if (Ready.Enqueue(prepared.Request.Key, prepared, prepared.Request.Priority))
                    _readyBytes += prepared.Pixels.Length;
                else
                {
                    // A worker can refill the bounded ready queue between a
                    // device-side defer and this return. Keep the request
                    // active and rasterize it again instead of stranding its
                    // key forever in the deduplication table.
                    Pending.Enqueue(prepared.Request.Key, prepared.Request,
                        prepared.Request.Priority);
                }
                RecordQueueDepthLocked();
                Monitor.PulseAll(Gate);
            }
        }

        private static void Complete(GlyphRequest request)
        {
            lock (Gate)
            {
                GlyphRequest active;
                if (Active.TryGetValue(request.Key, out active) &&
                    ReferenceEquals(active, request))
                    Active.Remove(request.Key);
                RecordQueueDepthLocked();
                Monitor.PulseAll(Gate);
            }
        }

        private static void RecordQueueDepthLocked()
        {
            RuntimeTextPerformance.RecordQueueDepth(Pending.Count, Ready.Count);
        }

        private static void StopWorker()
        {
            Thread worker;
            lock (Gate)
            {
                _stopping = true;
                worker = _worker;
                Monitor.PulseAll(Gate);
            }
            if (worker != null && worker.IsAlive) worker.Join(500);
        }
    }
}
