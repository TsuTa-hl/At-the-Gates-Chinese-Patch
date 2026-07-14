using AtG.Patch.Core.Build;

namespace AtG.ManagedRewrite;

public sealed record RuntimeRedirectJob(
    string Name,
    string SourcePath,
    string OutputPath,
    string RuntimeAssemblyPath,
    IReadOnlyList<CallRedirectSpec> Specs,
    IReadOnlyList<StringFieldFilterSpec> StringFieldFilters,
    int ExpectedRenderingRedirectCount,
    int ExpectedFontLoadRedirectCount,
    int ExpectedLifecycleRedirectCount,
    int ExpectedLayoutRedirectCount,
    int ExpectedLocalizationRedirectCount);

public sealed record RuntimeRedirectJobResult(
    string Name,
    string OutputPath,
    int RedirectedCount,
    bool CacheHit);

public static class RuntimeTextRedirectPlan
{
    private static readonly RedirectDefinition[] Definitions =
    [
        new("elftools", "ElfTools.dll", "ElfTools.original.dll", 17, 5, 14, 1, 0),
        new("common", "AtTheGatesCommon.dll", "AtTheGatesCommon.original.dll", 11, 26, 4, 0, 1),
        new("game", "At The Gates.exe", "AtTheGatesGame.original.exe", 6, 4, 44, 0, 0),
        new("ui", "AtTheGatesUI.dll", "AtTheGatesUI.original.dll", 0, 0, 12, 0, 0),
    ];

    public static IReadOnlyList<RuntimeRedirectJob> Create(string repositoryRoot, string runtimeAssemblyPath)
    {
        var root = Path.GetFullPath(repositoryRoot);
        var runtime = Path.GetFullPath(runtimeAssemblyPath);
        if (!File.Exists(runtime)) throw new FileNotFoundException("Runtime text assembly was not found.", runtime);
        var targetMethods = ManagedMethodCatalog.Read(runtime);
        var jobs = new List<RuntimeRedirectJob>();
        foreach (var definition in Definitions)
        {
            var managedInput = Path.Combine(root, ".cache", "managed-rewrite", definition.ManagedFile);
            var source = File.Exists(managedInput)
                ? managedInput
                : Path.Combine(root, "source", definition.OriginalFile);
            if (!File.Exists(source)) continue;
            var specs = BuildSpecs(ManagedCallCatalog.Read(source), targetMethods);
            var filters = BuildStringFieldFilters(definition, source, targetMethods);
            var expectedCount = definition.ExpectedRenderingCount + definition.ExpectedFontLoadCount +
                definition.ExpectedLifecycleCount + definition.ExpectedLayoutCount;
            if (specs.Count != expectedCount)
                throw new InvalidDataException(
                    $"Expected {expectedCount} SpriteFont redirects in {definition.Name}, found {specs.Count}.");
            jobs.Add(new RuntimeRedirectJob(
                definition.Name,
                source,
                Path.Combine(root, ".cache", "runtime-hook", definition.ManagedFile),
                runtime,
                specs,
                filters,
                definition.ExpectedRenderingCount,
                definition.ExpectedFontLoadCount,
                definition.ExpectedLifecycleCount,
                definition.ExpectedLayoutCount,
                definition.ExpectedLocalizationCount));
        }
        return jobs;
    }

    private static IReadOnlyList<CallRedirectSpec> BuildSpecs(
        IReadOnlyList<ManagedCallEntry> calls,
        IReadOnlyList<ManagedMethodEntry> targetMethods)
    {
        var specs = new List<CallRedirectSpec>();
        foreach (var call in calls)
        {
            var targetFullName = ResolveTargetFullName(call.TargetFullName);
            if (targetFullName is null) continue;
            var target = targetMethods.SingleOrDefault(method =>
                StringComparer.Ordinal.Equals(method.FullName, targetFullName))
                ?? throw new InvalidDataException($"Runtime target was not found: {targetFullName}");
            specs.Add(new CallRedirectSpec(
                call.TargetFullName,
                target.MetadataToken,
                1,
                call.CallerToken,
                call.IlOffset));
        }
        return specs;
    }

    private static IReadOnlyList<StringFieldFilterSpec> BuildStringFieldFilters(
        RedirectDefinition definition,
        string sourceAssemblyPath,
        IReadOnlyList<ManagedMethodEntry> targetMethods)
    {
        if (definition.ExpectedLocalizationCount == 0) return [];
        var sourceMethods = ManagedMethodCatalog.Read(sourceAssemblyPath);
        var caller = sourceMethods.Single(method => method.FullName ==
            "System.Collections.Generic.List`1<ElfTools.Interfaces.Controls.TextChunk> AtTheGatesCommon.ns_Text.TextFormatter::Process()");
        var target = targetMethods.Single(method => method.FullName ==
            "System.String AtG.RuntimeText.DisplayStringLocalizer::LocalizeRichText(System.String)");
        return
        [
            new StringFieldFilterSpec(caller.MetadataToken,
                "System.String AtTheGatesCommon.ns_Text.TextFormatter::RawText",
                target.MetadataToken, 1),
        ];
    }

    private static string? ResolveTargetFullName(string source)
    {
        if (source == "Microsoft.Xna.Framework.Vector2 Microsoft.Xna.Framework.Graphics.SpriteFont::MeasureString(System.String)")
            return "Microsoft.Xna.Framework.Vector2 AtG.RuntimeText.TextRenderer::MeasureString(Microsoft.Xna.Framework.Graphics.SpriteFont,System.String)";
        if (source == "Microsoft.Xna.Framework.Vector2 Microsoft.Xna.Framework.Graphics.SpriteFont::MeasureString(System.Text.StringBuilder)")
            return "Microsoft.Xna.Framework.Vector2 AtG.RuntimeText.TextRenderer::MeasureString(Microsoft.Xna.Framework.Graphics.SpriteFont,System.Text.StringBuilder)";
        if (source == "System.Void Microsoft.Xna.Framework.Graphics.SpriteBatch::DrawString(Microsoft.Xna.Framework.Graphics.SpriteFont,System.String,Microsoft.Xna.Framework.Vector2,Microsoft.Xna.Framework.Color)")
            return "System.Void AtG.RuntimeText.TextRenderer::DrawString(Microsoft.Xna.Framework.Graphics.SpriteBatch,Microsoft.Xna.Framework.Graphics.SpriteFont,System.String,Microsoft.Xna.Framework.Vector2,Microsoft.Xna.Framework.Color)";
        if (source == "System.Void Microsoft.Xna.Framework.Graphics.SpriteBatch::DrawString(Microsoft.Xna.Framework.Graphics.SpriteFont,System.String,Microsoft.Xna.Framework.Vector2,Microsoft.Xna.Framework.Color,System.Single,Microsoft.Xna.Framework.Vector2,System.Single,Microsoft.Xna.Framework.Graphics.SpriteEffects,System.Single)")
            return "System.Void AtG.RuntimeText.TextRenderer::DrawString(Microsoft.Xna.Framework.Graphics.SpriteBatch,Microsoft.Xna.Framework.Graphics.SpriteFont,System.String,Microsoft.Xna.Framework.Vector2,Microsoft.Xna.Framework.Color,System.Single,Microsoft.Xna.Framework.Vector2,System.Single,Microsoft.Xna.Framework.Graphics.SpriteEffects,System.Single)";
        if (source == "Microsoft.Xna.Framework.Graphics.SpriteFont Microsoft.Xna.Framework.Content.ContentManager::Load<Microsoft.Xna.Framework.Graphics.SpriteFont>(System.String)")
            return "Microsoft.Xna.Framework.Graphics.SpriteFont AtG.RuntimeText.FontRegistry::Load(Microsoft.Xna.Framework.Content.ContentManager,System.String)";
        if (source == "System.Void Microsoft.Xna.Framework.Graphics.SpriteBatch::Begin()")
            return "System.Void AtG.RuntimeText.SpriteBatchLifecycle::Begin(Microsoft.Xna.Framework.Graphics.SpriteBatch)";
        if (source == "System.Void Microsoft.Xna.Framework.Graphics.SpriteBatch::Begin(Microsoft.Xna.Framework.Graphics.SpriteSortMode,Microsoft.Xna.Framework.Graphics.BlendState,Microsoft.Xna.Framework.Graphics.SamplerState,Microsoft.Xna.Framework.Graphics.DepthStencilState,Microsoft.Xna.Framework.Graphics.RasterizerState)")
            return "System.Void AtG.RuntimeText.SpriteBatchLifecycle::Begin(Microsoft.Xna.Framework.Graphics.SpriteBatch,Microsoft.Xna.Framework.Graphics.SpriteSortMode,Microsoft.Xna.Framework.Graphics.BlendState,Microsoft.Xna.Framework.Graphics.SamplerState,Microsoft.Xna.Framework.Graphics.DepthStencilState,Microsoft.Xna.Framework.Graphics.RasterizerState)";
        if (source == "System.Void Microsoft.Xna.Framework.Graphics.SpriteBatch::Begin(Microsoft.Xna.Framework.Graphics.SpriteSortMode,Microsoft.Xna.Framework.Graphics.BlendState,Microsoft.Xna.Framework.Graphics.SamplerState,Microsoft.Xna.Framework.Graphics.DepthStencilState,Microsoft.Xna.Framework.Graphics.RasterizerState,Microsoft.Xna.Framework.Graphics.Effect)")
            return "System.Void AtG.RuntimeText.SpriteBatchLifecycle::Begin(Microsoft.Xna.Framework.Graphics.SpriteBatch,Microsoft.Xna.Framework.Graphics.SpriteSortMode,Microsoft.Xna.Framework.Graphics.BlendState,Microsoft.Xna.Framework.Graphics.SamplerState,Microsoft.Xna.Framework.Graphics.DepthStencilState,Microsoft.Xna.Framework.Graphics.RasterizerState,Microsoft.Xna.Framework.Graphics.Effect)";
        if (source == "System.Void Microsoft.Xna.Framework.Graphics.SpriteBatch::End()")
            return "System.Void AtG.RuntimeText.SpriteBatchLifecycle::End(Microsoft.Xna.Framework.Graphics.SpriteBatch)";
        if (source == "System.Void ElfTools.Interfaces.Controls.RichTextLabel/TextChunkProcessor::ProcessChunk_Normal_Word()")
            return "System.Void AtG.RuntimeText.CjkWordWrapBridge::ProcessWord(System.Object)";
        return null;
    }

    private sealed record RedirectDefinition(
        string Name,
        string ManagedFile,
        string OriginalFile,
        int ExpectedRenderingCount,
        int ExpectedFontLoadCount,
        int ExpectedLifecycleCount,
        int ExpectedLayoutCount,
        int ExpectedLocalizationCount);
}

public static class RuntimeTextRedirectCoordinator
{
    public static async Task<IReadOnlyList<RuntimeRedirectJobResult>> RunAsync(
        IReadOnlyList<RuntimeRedirectJob> jobs,
        BuildCache cache,
        CancellationToken cancellationToken = default)
    {
        return await Task.WhenAll(jobs.Select(job => Task.Run(() =>
        {
            cancellationToken.ThrowIfCancellationRequested();
            var hash = ContentHasher.HashFiles([job.SourcePath, job.RuntimeAssemblyPath],
                "runtime-text-redirect-v2|" + string.Join("|", job.Specs.Select(spec =>
                    spec.CallerMethodToken + ":" + spec.IlOffset + ":" + spec.SourceTargetFullName)) +
                "|filters=" + string.Join("|", job.StringFieldFilters.Select(spec =>
                    spec.CallerMethodToken + ":" + spec.FieldFullName + ":" + spec.TargetMethodToken)));
            var stage = "runtime-hook-" + job.Name;
            if (cache.IsCurrent(stage, hash, [job.OutputPath]))
            {
                RuntimeTextRedirectVerifier.Verify(job.OutputPath,
                    job.ExpectedRenderingRedirectCount, job.ExpectedFontLoadRedirectCount,
                    job.ExpectedLifecycleRedirectCount, job.ExpectedLayoutRedirectCount,
                    job.ExpectedLocalizationRedirectCount);
                return new RuntimeRedirectJobResult(job.Name, job.OutputPath,
                    job.Specs.Count + job.StringFieldFilters.Count, true);
            }
            var callOutput = job.StringFieldFilters.Count == 0
                ? job.OutputPath
                : job.OutputPath + ".calls.tmp";
            var result = ManagedCallRedirector.Redirect(job.SourcePath, callOutput,
                job.RuntimeAssemblyPath, job.Specs);
            var injected = 0;
            if (job.StringFieldFilters.Count > 0)
            {
                injected = ManagedStringFieldFilterInjector.Inject(callOutput, job.OutputPath,
                    job.RuntimeAssemblyPath, job.StringFieldFilters).InjectedCount;
                File.Delete(callOutput);
            }
            RuntimeTextRedirectVerifier.Verify(job.OutputPath,
                job.ExpectedRenderingRedirectCount, job.ExpectedFontLoadRedirectCount,
                job.ExpectedLifecycleRedirectCount, job.ExpectedLayoutRedirectCount,
                job.ExpectedLocalizationRedirectCount);
            cache.Record(stage, hash, [job.OutputPath]);
            return new RuntimeRedirectJobResult(job.Name, job.OutputPath,
                result.RedirectedCount + injected, false);
        }, cancellationToken)));
    }
}

public static class RuntimeTextRedirectVerifier
{
    public static void Verify(
        string assemblyPath,
        int expectedRenderingRedirectCount,
        int expectedFontLoadRedirectCount,
        int expectedLifecycleRedirectCount,
        int expectedLayoutRedirectCount,
        int expectedLocalizationRedirectCount)
    {
        var calls = ManagedCallCatalog.Read(assemblyPath);
        var renderingCalls = calls.Count(call =>
            call.TargetFullName.Contains(" AtG.RuntimeText.TextRenderer::", StringComparison.Ordinal));
        var fontLoadCalls = calls.Count(call =>
            call.TargetFullName.Contains(" AtG.RuntimeText.FontRegistry::Load(", StringComparison.Ordinal));
        var lifecycleCalls = calls.Count(call =>
            call.TargetFullName.Contains(" AtG.RuntimeText.SpriteBatchLifecycle::", StringComparison.Ordinal));
        var layoutCalls = calls.Count(call =>
            call.TargetFullName.Contains(" AtG.RuntimeText.CjkWordWrapBridge::", StringComparison.Ordinal));
        var localizationCalls = calls.Count(call =>
            call.TargetFullName.Contains(" AtG.RuntimeText.DisplayStringLocalizer::LocalizeRichText(", StringComparison.Ordinal));
        var originalRenderingCalls = calls.Count(call =>
            call.TargetFullName.Contains("Microsoft.Xna.Framework.Graphics.SpriteFont::MeasureString", StringComparison.Ordinal) ||
            call.TargetFullName.Contains("Microsoft.Xna.Framework.Graphics.SpriteBatch::DrawString", StringComparison.Ordinal));
        var originalFontLoadCalls = calls.Count(call =>
            call.TargetFullName == "Microsoft.Xna.Framework.Graphics.SpriteFont Microsoft.Xna.Framework.Content.ContentManager::Load<Microsoft.Xna.Framework.Graphics.SpriteFont>(System.String)");
        var originalLifecycleCalls = calls.Count(call =>
            call.TargetFullName.StartsWith("System.Void Microsoft.Xna.Framework.Graphics.SpriteBatch::Begin(", StringComparison.Ordinal) ||
            call.TargetFullName == "System.Void Microsoft.Xna.Framework.Graphics.SpriteBatch::End()");
        var originalLayoutCalls = calls.Count(call =>
            call.TargetFullName == "System.Void ElfTools.Interfaces.Controls.RichTextLabel/TextChunkProcessor::ProcessChunk_Normal_Word()");
        if (renderingCalls != expectedRenderingRedirectCount ||
            fontLoadCalls != expectedFontLoadRedirectCount ||
            lifecycleCalls != expectedLifecycleRedirectCount ||
            layoutCalls != expectedLayoutRedirectCount ||
            localizationCalls != expectedLocalizationRedirectCount ||
            originalRenderingCalls != 0 || originalFontLoadCalls != 0 || originalLifecycleCalls != 0 ||
            originalLayoutCalls != 0)
            throw new InvalidDataException(
                $"Runtime redirect verification failed for '{assemblyPath}': " +
                $"rendering={renderingCalls}/{expectedRenderingRedirectCount}, " +
                $"font-load={fontLoadCalls}/{expectedFontLoadRedirectCount}, " +
                $"lifecycle={lifecycleCalls}/{expectedLifecycleRedirectCount}, " +
                $"layout={layoutCalls}/{expectedLayoutRedirectCount}, " +
                $"localization={localizationCalls}/{expectedLocalizationRedirectCount}, " +
                $"original-rendering={originalRenderingCalls}, original-font-load={originalFontLoadCalls}, " +
                $"original-lifecycle={originalLifecycleCalls}, original-layout={originalLayoutCalls}.");
    }
}
