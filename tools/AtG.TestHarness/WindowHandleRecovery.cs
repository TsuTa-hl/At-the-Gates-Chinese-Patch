namespace AtG.TestHarness;

public static class WindowHandleRecovery
{
    public static IntPtr Select(
        IntPtr current,
        Func<IntPtr, bool> isValid,
        Func<IntPtr> findReplacement)
    {
        if (current != IntPtr.Zero && isValid(current)) return current;
        var replacement = findReplacement();
        if (replacement == IntPtr.Zero || !isValid(replacement))
            throw new InvalidOperationException("No usable game window is currently available.");
        return replacement;
    }
}
