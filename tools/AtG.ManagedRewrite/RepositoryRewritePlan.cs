namespace AtG.ManagedRewrite;

public static class RepositoryRewritePlan
{
    private static readonly RewriteDefinition[] Definitions =
    [
        new("ui", "AtTheGatesUI.original.dll", "hardcoded-ui-il-rewrite.json", "AtTheGatesUI.dll"),
        new("common", "AtTheGatesCommon.original.dll", "hardcoded-common-il-rewrite.json", "AtTheGatesCommon.dll"),
        new("game", "AtTheGatesGame.original.exe", "hardcoded-game-il-rewrite.json", "At The Gates.exe"),
        new("elftools", "ElfTools.original.dll", "hardcoded-elftools-il-rewrite.json", "ElfTools.dll"),
    ];

    public static IReadOnlyList<RewriteJob> Create(string repositoryRoot)
    {
        var root = Path.GetFullPath(repositoryRoot);
        var sourceDirectory = Path.Combine(root, "source");
        var translationDirectory = Path.Combine(root, "translations");
        var outputDirectory = Path.Combine(root, ".cache", "managed-rewrite");

        return Definitions
            .Select(definition => new RewriteJob(
                definition.Name,
                Path.Combine(sourceDirectory, definition.SourceFile),
                Path.Combine(outputDirectory, definition.OutputFile),
                Path.Combine(translationDirectory, definition.MapFile)))
            .Where(job => File.Exists(job.SourcePath) && File.Exists(job.MapPath))
            .ToArray();
    }

    private sealed record RewriteDefinition(
        string Name,
        string SourceFile,
        string MapFile,
        string OutputFile);
}
