#nullable enable
using System.Reflection;
using System.Runtime.ExceptionServices;

namespace AtG.Testing;

/// <summary>
/// Discovers the no-argument test methods retained in the former top-level
/// runners.  Xunit owns discovery and invocation; the excluded legacy runner
/// blocks are no longer executable test entry points.
/// </summary>
public static class LegacyRunnerXunitBridge
{
    public static IEnumerable<object[]> DiscoverCases(Assembly assembly)
    {
        var program = assembly.GetType("Program")
            ?? throw new InvalidOperationException("Could not locate the top-level test method container.");

        return program
            .GetMethods(BindingFlags.NonPublic | BindingFlags.Static)
            .Where(method => method.Name.Contains(">g__", StringComparison.Ordinal) &&
                             method.GetParameters().Length == 0 &&
                             (method.ReturnType == typeof(void) || method.ReturnType == typeof(Task)))
            .OrderBy(method => method.MetadataToken)
            .Select(method => new object[] { DisplayName(method), method.MetadataToken })
            .ToArray();
    }

    public static async Task InvokeAsync(Assembly assembly, int metadataToken)
    {
        MethodInfo method;
        try
        {
            method = assembly.ManifestModule.ResolveMethod(metadataToken) as MethodInfo
                ?? throw new InvalidOperationException(
                    $"Discovered test method token {metadataToken} did not resolve to a method.");
        }
        catch (Exception ex)
        {
            throw new InvalidOperationException($"Could not resolve discovered test method token {metadataToken}.", ex);
        }

        try
        {
            var result = method.Invoke(null, null);
            if (result is Task task)
            {
                await task.ConfigureAwait(false);
            }
        }
        catch (TargetInvocationException ex)
        {
            ExceptionDispatchInfo.Capture(ex.InnerException ?? ex).Throw();
            throw;
        }
    }

    private static string DisplayName(MethodInfo method)
    {
        var name = method.Name;
        var marker = name.IndexOf(">g__", StringComparison.Ordinal);
        if (marker < 0)
        {
            return name;
        }

        var start = marker + 4;
        var end = name.IndexOf('|', start);
        return end > start ? name[start..end] : name[start..];
    }
}
