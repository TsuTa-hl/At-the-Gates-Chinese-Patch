namespace AtG.RuntimeText
{
    public sealed class GlyphCacheDiagnostics
    {
        internal GlyphCacheDiagnostics(int glyphCount, int atlasPageCount, bool isFaulted,
            long currentRgbaBytes, long peakRgbaBytes, long budgetRejectionCount)
        {
            GlyphCount = glyphCount;
            AtlasPageCount = atlasPageCount;
            IsFaulted = isFaulted;
            CurrentRgbaBytes = currentRgbaBytes;
            PeakRgbaBytes = peakRgbaBytes;
            BudgetRejectionCount = budgetRejectionCount;
        }

        public int GlyphCount { get; private set; }
        public int GlyphTextureCount { get { return GlyphCount; } }
        public int AtlasPageCount { get; private set; }
        public bool IsFaulted { get; private set; }
        public long CurrentRgbaBytes { get; private set; }
        public long PeakRgbaBytes { get; private set; }
        public long BudgetRejectionCount { get; private set; }
    }
}
