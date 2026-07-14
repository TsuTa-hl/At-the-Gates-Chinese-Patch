using System;

namespace AtG.RuntimeText
{
    internal enum GlyphAtlasResetAction
    {
        RetainLivePages,
        ReleaseAllPages,
        KeepFaulted,
    }

    internal static class GlyphAtlasResetDecision
    {
        public static GlyphAtlasResetAction Evaluate(int totalPages, int livePages)
        {
            if (totalPages < 0) throw new ArgumentOutOfRangeException("totalPages");
            if (livePages < 0 || livePages > totalPages)
                throw new ArgumentOutOfRangeException("livePages");
            if (livePages == totalPages && totalPages > 0)
                return GlyphAtlasResetAction.RetainLivePages;
            if (livePages == 0)
                return GlyphAtlasResetAction.ReleaseAllPages;
            return GlyphAtlasResetAction.KeepFaulted;
        }
    }
}
