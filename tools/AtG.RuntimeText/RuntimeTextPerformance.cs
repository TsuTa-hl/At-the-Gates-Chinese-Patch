using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Text;
using System.Threading;

namespace AtG.RuntimeText
{
    internal static class RuntimeTextPerformance
    {
        private const int MaximumPendingLines = 1024;
        private static readonly bool Enabled =
            string.Equals(Environment.GetEnvironmentVariable("ATG_RUNTIME_TEXT_PERF"),
                "1", StringComparison.Ordinal);
        private static readonly object WriterGate = new object();
        private static readonly Queue<string> PendingLines = new Queue<string>();
        private static Thread _writer;
        private static bool _stopping;
        private static long _frame;
        private static long _mainThreadTicks;
        private static long _uploadTicks;
        private static long _rasterTicks;
        private static long _maximumUploadTicks;
        private static int _uploads;
        private static int _rasterized;
        private static int _requests;
        private static int _lookups;
        private static int _hits;
        private static int _misses;
        private static int _fallbacks;
        private static int _warmSkips;
        private static int _budgetStops;
        private static int _pageCreations;
        private static int _deviceResets;
        private static int _maximumPending;
        private static int _maximumReady;
        private static int _atlasPages;
        private static string _mode = "Budgeted";

        static RuntimeTextPerformance()
        {
            if (!Enabled) return;
            AppDomain.CurrentDomain.ProcessExit += delegate { StopWriter(); };
        }

        public static bool IsEnabled { get { return Enabled; } }

        public static long StartOperation()
        {
            return Enabled ? Stopwatch.GetTimestamp() : 0L;
        }

        public static void CompleteMainThreadOperation(long startedAt)
        {
            if (!Enabled || startedAt == 0L) return;
            Interlocked.Add(ref _mainThreadTicks,
                Math.Max(0L, Stopwatch.GetTimestamp() - startedAt));
        }

        public static void BeginFrame(string mode)
        {
            if (!Enabled) return;
            _mode = mode ?? "";
            var frame = Interlocked.Increment(ref _frame);
            if (frame == 1L)
            {
                // Constructor/LoadContent warmup happens before XNA's first
                // Draw. It is intentional loading work, not a render frame;
                // discard it so frame telemetry starts at the Draw boundary.
                ResetCounters();
            }
            else EnqueueLine(CaptureFrame(frame - 1L, _mode));
        }

        public static void RecordUpload(long elapsedTicks, bool uploaded, bool pageCreated)
        {
            if (!Enabled) return;
            var ticks = Math.Max(0L, elapsedTicks);
            Interlocked.Add(ref _uploadTicks, ticks);
            Interlocked.Add(ref _mainThreadTicks, ticks);
            SetMaximum(ref _maximumUploadTicks, ticks);
            if (uploaded) Interlocked.Increment(ref _uploads);
            if (pageCreated) Interlocked.Increment(ref _pageCreations);
        }

        public static void RecordRaster(long elapsedTicks)
        {
            if (!Enabled) return;
            Interlocked.Add(ref _rasterTicks, Math.Max(0L, elapsedTicks));
            Interlocked.Increment(ref _rasterized);
        }

        public static void RecordRequest() { if (Enabled) Interlocked.Increment(ref _requests); }
        public static void RecordGlyphLookup(bool hit)
        {
            if (!Enabled) return;
            Interlocked.Increment(ref _lookups);
            if (hit)
                Interlocked.Increment(ref _hits);
            else
                Interlocked.Increment(ref _misses);
        }
        public static void RecordFallback() { if (Enabled) Interlocked.Increment(ref _fallbacks); }
        public static void RecordWarmSkip() { if (Enabled) Interlocked.Increment(ref _warmSkips); }
        public static void RecordBudgetStop() { if (Enabled) Interlocked.Increment(ref _budgetStops); }
        public static void RecordDeviceReset() { if (Enabled) Interlocked.Increment(ref _deviceResets); }

        public static void RecordQueueDepth(int pending, int ready)
        {
            if (!Enabled) return;
            SetMaximum(ref _maximumPending, pending);
            SetMaximum(ref _maximumReady, ready);
        }

        public static void RecordAtlasPages(int pages)
        {
            if (Enabled) Interlocked.Exchange(ref _atlasPages, pages);
        }

        internal static string FormatLine(long frame, DateTime timeUtc, string mode,
            long mainThreadTicks, long uploadTicks, long rasterTicks,
            long maximumUploadTicks,
            int uploads, int rasterized, int requests, int lookups, int hits,
            int misses, int fallbacks, int warmSkips,
            int budgetStops, int pageCreations, int deviceResets,
            int maximumPending, int maximumReady, int atlasPages)
        {
            return "{\"time\":\"" + timeUtc.ToString("o", CultureInfo.InvariantCulture) +
                   "\",\"frame\":" + frame.ToString(CultureInfo.InvariantCulture) +
                   ",\"mode\":\"" + Escape(mode) +
                   "\",\"mainThreadMs\":" + Milliseconds(mainThreadTicks) +
                   ",\"uploadMs\":" + Milliseconds(uploadTicks) +
                   ",\"maxUploadMs\":" + Milliseconds(maximumUploadTicks) +
                   ",\"rasterMs\":" + Milliseconds(rasterTicks) +
                   ",\"uploads\":" + uploads.ToString(CultureInfo.InvariantCulture) +
                   ",\"rasterized\":" + rasterized.ToString(CultureInfo.InvariantCulture) +
                   ",\"requests\":" + requests.ToString(CultureInfo.InvariantCulture) +
                   ",\"lookups\":" + lookups.ToString(CultureInfo.InvariantCulture) +
                   ",\"hits\":" + hits.ToString(CultureInfo.InvariantCulture) +
                   ",\"misses\":" + misses.ToString(CultureInfo.InvariantCulture) +
                   ",\"hitRate\":" + Ratio(hits, lookups) +
                   ",\"fallbacks\":" + fallbacks.ToString(CultureInfo.InvariantCulture) +
                   ",\"warmSkips\":" + warmSkips.ToString(CultureInfo.InvariantCulture) +
                   ",\"budgetStops\":" + budgetStops.ToString(CultureInfo.InvariantCulture) +
                   ",\"pageCreations\":" + pageCreations.ToString(CultureInfo.InvariantCulture) +
                   ",\"deviceResets\":" + deviceResets.ToString(CultureInfo.InvariantCulture) +
                   ",\"maxPending\":" + maximumPending.ToString(CultureInfo.InvariantCulture) +
                   ",\"maxReady\":" + maximumReady.ToString(CultureInfo.InvariantCulture) +
                   ",\"atlasPages\":" + atlasPages.ToString(CultureInfo.InvariantCulture) + "}";
        }

        private static void EnqueueLine(string line)
        {
            lock (WriterGate)
            {
                if (_stopping) return;
                if (PendingLines.Count >= MaximumPendingLines) PendingLines.Dequeue();
                PendingLines.Enqueue(line);
                if (_writer == null)
                {
                    _writer = new Thread(WriterLoop)
                    {
                        IsBackground = true,
                        Name = "AtG RuntimeText performance writer",
                    };
                    _writer.Start();
                }
                Monitor.PulseAll(WriterGate);
            }
        }

        private static void WriterLoop()
        {
            try
            {
                var path = Path.Combine(AppDomain.CurrentDomain.BaseDirectory,
                    "AtG.RuntimeText.Perf.jsonl");
                while (true)
                {
                    string[] lines;
                    lock (WriterGate)
                    {
                        while (!_stopping && PendingLines.Count == 0)
                            Monitor.Wait(WriterGate);
                        if (_stopping && PendingLines.Count == 0) return;
                        lines = PendingLines.ToArray();
                        PendingLines.Clear();
                    }
                    File.AppendAllLines(path, lines, Encoding.UTF8);
                }
            }
            catch
            {
                // Performance telemetry must never affect rendering or shutdown.
            }
        }

        private static void StopWriter()
        {
            if (!Enabled) return;
            var frame = Interlocked.Read(ref _frame);
            if (frame > 0L) EnqueueLine(CaptureFrame(frame, _mode));
            Thread writer;
            lock (WriterGate)
            {
                _stopping = true;
                writer = _writer;
                Monitor.PulseAll(WriterGate);
            }
            if (writer != null && writer.IsAlive) writer.Join(500);
        }

        private static string CaptureFrame(long frame, string mode)
        {
            return FormatLine(
                frame,
                DateTime.UtcNow,
                mode,
                Interlocked.Exchange(ref _mainThreadTicks, 0L),
                Interlocked.Exchange(ref _uploadTicks, 0L),
                Interlocked.Exchange(ref _rasterTicks, 0L),
                Interlocked.Exchange(ref _maximumUploadTicks, 0L),
                Interlocked.Exchange(ref _uploads, 0),
                Interlocked.Exchange(ref _rasterized, 0),
                Interlocked.Exchange(ref _requests, 0),
                Interlocked.Exchange(ref _lookups, 0),
                Interlocked.Exchange(ref _hits, 0),
                Interlocked.Exchange(ref _misses, 0),
                Interlocked.Exchange(ref _fallbacks, 0),
                Interlocked.Exchange(ref _warmSkips, 0),
                Interlocked.Exchange(ref _budgetStops, 0),
                Interlocked.Exchange(ref _pageCreations, 0),
                Interlocked.Exchange(ref _deviceResets, 0),
                Interlocked.Exchange(ref _maximumPending, 0),
                Interlocked.Exchange(ref _maximumReady, 0),
                VolatileRead(ref _atlasPages));
        }

        private static void ResetCounters()
        {
            Interlocked.Exchange(ref _mainThreadTicks, 0L);
            Interlocked.Exchange(ref _uploadTicks, 0L);
            Interlocked.Exchange(ref _rasterTicks, 0L);
            Interlocked.Exchange(ref _maximumUploadTicks, 0L);
            Interlocked.Exchange(ref _uploads, 0);
            Interlocked.Exchange(ref _rasterized, 0);
            Interlocked.Exchange(ref _requests, 0);
            Interlocked.Exchange(ref _lookups, 0);
            Interlocked.Exchange(ref _hits, 0);
            Interlocked.Exchange(ref _misses, 0);
            Interlocked.Exchange(ref _fallbacks, 0);
            Interlocked.Exchange(ref _warmSkips, 0);
            Interlocked.Exchange(ref _budgetStops, 0);
            Interlocked.Exchange(ref _pageCreations, 0);
            Interlocked.Exchange(ref _deviceResets, 0);
            Interlocked.Exchange(ref _maximumPending, 0);
            Interlocked.Exchange(ref _maximumReady, 0);
        }

        private static string Milliseconds(long ticks)
        {
            var value = ticks * 1000d / Stopwatch.Frequency;
            return value.ToString("0.###", CultureInfo.InvariantCulture);
        }

        private static string Ratio(int numerator, int denominator)
        {
            var value = denominator <= 0 ? 0d : numerator / (double)denominator;
            return value.ToString("0.######", CultureInfo.InvariantCulture);
        }

        private static string Escape(string value)
        {
            return (value ?? "").Replace("\\", "\\\\").Replace("\"", "\\\"");
        }

        private static void SetMaximum(ref int location, int value)
        {
            while (true)
            {
                var current = VolatileRead(ref location);
                if (value <= current) return;
                if (Interlocked.CompareExchange(ref location, value, current) == current) return;
            }
        }

        private static void SetMaximum(ref long location, long value)
        {
            while (true)
            {
                var current = Interlocked.Read(ref location);
                if (value <= current) return;
                if (Interlocked.CompareExchange(ref location, value, current) == current) return;
            }
        }

        private static int VolatileRead(ref int location)
        {
            return Interlocked.CompareExchange(ref location, 0, 0);
        }
    }
}
