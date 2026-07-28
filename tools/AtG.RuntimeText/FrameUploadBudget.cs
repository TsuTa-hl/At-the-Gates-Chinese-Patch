using System;

namespace AtG.RuntimeText
{
    internal sealed class FrameUploadBudget
    {
        private readonly long _budgetTicks;
        private readonly int _maximumUploads;
        private readonly int _maximumPageCreations;
        private long _consumedTicks;
        private int _uploadCount;
        private int _pageCreationCount;
        private bool _started;

        public FrameUploadBudget(double budgetMilliseconds, long clockFrequency,
            int maximumUploads, int maximumPageCreations)
        {
            if (budgetMilliseconds <= 0d) throw new ArgumentOutOfRangeException("budgetMilliseconds");
            if (clockFrequency <= 0L) throw new ArgumentOutOfRangeException("clockFrequency");
            if (maximumUploads <= 0) throw new ArgumentOutOfRangeException("maximumUploads");
            if (maximumPageCreations <= 0) throw new ArgumentOutOfRangeException("maximumPageCreations");
            _budgetTicks = Math.Max(1L,
                (long)Math.Ceiling(budgetMilliseconds * clockFrequency / 1000d));
            _maximumUploads = maximumUploads;
            _maximumPageCreations = maximumPageCreations;
        }

        public bool IsStarted { get { return _started; } }
        public long ConsumedTicks { get { return _consumedTicks; } }
        public int UploadCount { get { return _uploadCount; } }
        public int PageCreationCount { get { return _pageCreationCount; } }

        public void BeginFrame()
        {
            _consumedTicks = 0L;
            _uploadCount = 0;
            _pageCreationCount = 0;
            _started = true;
        }

        public bool CanAttempt(bool requiresPageCreation)
        {
            return _started &&
                   _consumedTicks < _budgetTicks &&
                   _uploadCount < _maximumUploads &&
                   (!requiresPageCreation || _pageCreationCount < _maximumPageCreations);
        }

        public void RecordOperation(long elapsedTicks, bool pageCreated)
        {
            if (!_started) throw new InvalidOperationException("Frame budget has not started.");
            _consumedTicks = checked(_consumedTicks + Math.Max(0L, elapsedTicks));
            _uploadCount++;
            if (pageCreated) _pageCreationCount++;
        }
    }
}
