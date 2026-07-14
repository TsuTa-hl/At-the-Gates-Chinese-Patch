using System;
using System.Collections.Generic;

namespace AtG.RuntimeText
{
    internal sealed class GlyphAtlasAllocation
    {
        public GlyphAtlasAllocation(int pageIndex, int x, int y, int width, int height)
        {
            PageIndex = pageIndex;
            X = x;
            Y = y;
            Width = width;
            Height = height;
        }

        public int PageIndex { get; private set; }
        public int X { get; private set; }
        public int Y { get; private set; }
        public int Width { get; private set; }
        public int Height { get; private set; }
    }

    internal sealed class GlyphAtlasAllocator
    {
        private sealed class Shelf
        {
            public int Y;
            public int Height;
            public int NextX;
        }

        private sealed class Page
        {
            public readonly List<Shelf> Shelves = new List<Shelf>();
            public int NextShelfY;
        }

        private readonly object _gate = new object();
        private readonly int _pageWidth;
        private readonly int _pageHeight;
        private readonly int _maximumPages;
        private readonly List<Page> _pages = new List<Page>();

        public GlyphAtlasAllocator(int pageWidth, int pageHeight, int maximumPages)
        {
            if (pageWidth <= 0) throw new ArgumentOutOfRangeException("pageWidth");
            if (pageHeight <= 0) throw new ArgumentOutOfRangeException("pageHeight");
            if (maximumPages <= 0) throw new ArgumentOutOfRangeException("maximumPages");
            _pageWidth = pageWidth;
            _pageHeight = pageHeight;
            _maximumPages = maximumPages;
        }

        public int PageCount
        {
            get { lock (_gate) return _pages.Count; }
        }

        public bool TryAllocate(int width, int height, out GlyphAtlasAllocation allocation)
        {
            lock (_gate)
            {
                allocation = null;
                if (width <= 0 || height <= 0 || width > _pageWidth || height > _pageHeight)
                    return false;

                for (var pageIndex = 0; pageIndex < _pages.Count; pageIndex++)
                {
                    if (TryAllocateOnPage(_pages[pageIndex], pageIndex, width, height, out allocation))
                        return true;
                }

                if (_pages.Count >= _maximumPages) return false;
                var page = new Page();
                _pages.Add(page);
                return TryAllocateOnPage(page, _pages.Count - 1, width, height, out allocation);
            }
        }

        public void Reset()
        {
            lock (_gate) _pages.Clear();
        }

        private bool TryAllocateOnPage(Page page, int pageIndex, int width, int height,
            out GlyphAtlasAllocation allocation)
        {
            foreach (var shelf in page.Shelves)
            {
                if (height > shelf.Height || shelf.NextX > _pageWidth - width) continue;
                allocation = new GlyphAtlasAllocation(pageIndex, shelf.NextX, shelf.Y, width, height);
                shelf.NextX += width;
                return true;
            }

            if (page.NextShelfY > _pageHeight - height)
            {
                allocation = null;
                return false;
            }

            var newShelf = new Shelf { Y = page.NextShelfY, Height = height, NextX = width };
            page.Shelves.Add(newShelf);
            page.NextShelfY += height;
            allocation = new GlyphAtlasAllocation(pageIndex, 0, newShelf.Y, width, height);
            return true;
        }
    }
}
