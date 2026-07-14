using System;
using System.Collections.Generic;

namespace AtG.RuntimeText
{
    internal sealed class GlyphAtlasCacheState
    {
        private readonly object _gate = new object();
        private readonly GlyphAtlasAllocator _allocator;
        private readonly long _pageBytes;
        private readonly HashSet<int> _createdPages = new HashSet<int>();
        private int _glyphCount;
        private bool _isFaulted;
        private long _peakBytes;
        private long _rejectionCount;

        public GlyphAtlasCacheState(int pageWidth, int pageHeight, int maximumPages)
        {
            _allocator = new GlyphAtlasAllocator(pageWidth, pageHeight, maximumPages);
            _pageBytes = checked((long)pageWidth * pageHeight * 4L);
        }

        public int AllocatedPageCount
        {
            get { lock (_gate) return _allocator.PageCount; }
        }

        public bool TryAllocate(int width, int height, out GlyphAtlasAllocation allocation)
        {
            lock (_gate)
            {
                if (_isFaulted)
                {
                    allocation = null;
                    return false;
                }
                if (_allocator.TryAllocate(width, height, out allocation)) return true;
                _rejectionCount++;
                return false;
            }
        }

        public void RecordPageCreated(int pageIndex)
        {
            lock (_gate)
            {
                if (pageIndex < 0 || pageIndex >= _allocator.PageCount)
                    throw new ArgumentOutOfRangeException("pageIndex");
                if (!_createdPages.Add(pageIndex)) return;
                _peakBytes = Math.Max(_peakBytes, checked(_createdPages.Count * _pageBytes));
            }
        }

        public void RecordGlyphCached()
        {
            lock (_gate) _glyphCount++;
        }

        public void MarkFaulted()
        {
            lock (_gate) _isFaulted = true;
        }

        public void RecoverRetainedResourcesAfterDeviceReset()
        {
            lock (_gate) _isFaulted = false;
        }

        public void ResetAfterResourcesReleased()
        {
            lock (_gate)
            {
                _allocator.Reset();
                _createdPages.Clear();
                _glyphCount = 0;
                _isFaulted = false;
            }
        }

        public GlyphCacheDiagnostics GetDiagnostics()
        {
            lock (_gate)
            {
                return new GlyphCacheDiagnostics(_glyphCount, _createdPages.Count, _isFaulted,
                    checked(_createdPages.Count * _pageBytes), _peakBytes, _rejectionCount);
            }
        }
    }
}
