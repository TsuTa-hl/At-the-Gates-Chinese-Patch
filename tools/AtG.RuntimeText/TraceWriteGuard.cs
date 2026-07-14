using System;

namespace AtG.RuntimeText
{
    internal static class TraceWriteGuard
    {
        public static void Try(Action write)
        {
            if (write == null) return;
            try { write(); }
            catch
            {
                // Diagnostics must never interrupt measurement, drawing, or fallback.
            }
        }
    }
}
