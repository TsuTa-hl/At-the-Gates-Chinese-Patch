using AtG.Patch.Core.Build;

namespace AtG.ManagedRewrite;

public sealed record RewriteJob(string Name, string SourcePath, string OutputPath, string MapPath);

public sealed record RewriteJobResult(
    string Name,
    int RewrittenCount,
    bool CacheHit,
    string OutputPath,
    long DurationMs);

public static class ManagedRewriteCoordinator
{
    private const string CacheVersion = "managed-rewrite-v1-dnlib-4.5.0";

    public static async Task<IReadOnlyList<RewriteJobResult>> RunAsync(
        IReadOnlyCollection<RewriteJob> jobs,
        BuildCache cache,
        CancellationToken cancellationToken = default)
    {
        var tasks = jobs.Select(job => Task.Run(() => Run(job, cache), cancellationToken));
        return await Task.WhenAll(tasks).ConfigureAwait(false);
    }

    private static RewriteJobResult Run(RewriteJob job, BuildCache cache)
    {
        var stopwatch = System.Diagnostics.Stopwatch.StartNew();
        var source = Path.GetFullPath(job.SourcePath);
        var map = Path.GetFullPath(job.MapPath);
        var output = Path.GetFullPath(job.OutputPath);
        var hash = ContentHasher.HashFiles([source, map], CacheVersion);

        if (cache.IsCurrent(job.Name, hash, [output]))
        {
            stopwatch.Stop();
            return new RewriteJobResult(job.Name, 0, true, output, stopwatch.ElapsedMilliseconds);
        }

        var result = ManagedAssemblyRewriter.Rewrite(source, output, RewriteMap.Load(map));
        cache.Record(job.Name, hash, [output]);
        stopwatch.Stop();
        return new RewriteJobResult(job.Name, result.RewrittenCount, false, output, stopwatch.ElapsedMilliseconds);
    }
}
