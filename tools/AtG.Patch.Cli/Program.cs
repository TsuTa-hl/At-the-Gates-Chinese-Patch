using System.Diagnostics;
using System.Text.Json;
using AtG.ManagedRewrite;
using AtG.Catalog;
using AtG.Patch.Core.Build;

if (args.Length == 0 || args[0] is "-h" or "--help" or "help")
{
    PrintUsage();
    return 0;
}

try
{
    return args[0] switch
    {
        "rewrite" => await RewriteAsync(args[1..]),
        "catalog" => CatalogCommand.Run(args[1..], Console.Out, Console.Error),
        "composite-catalog" => BuildCompositeCatalog(args[1..]),
        "known-texts-csv" => ExportKnownTextsCsv(args[1..]),
        "composite-csv" => ExportCompositeCsv(args[1..]),
        "todo-csv" => ExportTodoCsv(args[1..]),
        "calls" => ExportCalls(args[1..]),
        "methods" => ExportMethods(args[1..]),
        "runtime-rewrite" => await RewriteRuntimeCallsAsync(args[1..]),
        "runtime-map" => BuildRuntimeDisplayMap(args[1..]),
        "load-lifecycle" => PatchLoadLifecycle(args[1..]),
        _ => throw new ArgumentException($"Unknown command '{args[0]}'."),
    };
}
catch (Exception ex)
{
    Console.Error.WriteLine(ex.Message);
    return 1;
}

static async Task<int> RewriteAsync(string[] args)
{
    var repositoryRoot = GetOption(args, "--repo") ?? Directory.GetCurrentDirectory();
    repositoryRoot = Path.GetFullPath(repositoryRoot);
    var cachePath = GetOption(args, "--cache")
                    ?? Path.Combine(repositoryRoot, ".cache", "build-cache.json");
    var summaryPath = GetOption(args, "--summary");
    var jobs = RepositoryRewritePlan.Create(repositoryRoot);
    if (jobs.Count == 0)
        throw new InvalidOperationException("No managed rewrite source/map pairs were found.");

    var stopwatch = Stopwatch.StartNew();
    var results = await ManagedRewriteCoordinator.RunAsync(jobs, new BuildCache(cachePath));
    stopwatch.Stop();

    var summary = new
    {
        Command = "rewrite",
        RepositoryRoot = repositoryRoot,
        ElapsedMilliseconds = stopwatch.ElapsedMilliseconds,
        Jobs = results.Select(result => new
        {
            result.Name,
            result.OutputPath,
            result.RewrittenCount,
            result.CacheHit,
        }),
    };
    var json = JsonSerializer.Serialize(summary, new JsonSerializerOptions { WriteIndented = true });
    Console.WriteLine(json);
    if (summaryPath is not null)
    {
        summaryPath = Path.GetFullPath(summaryPath);
        Directory.CreateDirectory(Path.GetDirectoryName(summaryPath)!);
        File.WriteAllText(summaryPath, json);
    }

    return 0;
}

static string? GetOption(string[] args, string name)
{
    for (var index = 0; index < args.Length; index++)
    {
        if (!StringComparer.OrdinalIgnoreCase.Equals(args[index], name))
            continue;
        if (index + 1 >= args.Length)
            throw new ArgumentException($"Option '{name}' requires a value.");
        return args[index + 1];
    }

    return null;
}

static int ExportCalls(string[] args)
{
    var assembly = GetOption(args, "--assembly")
                   ?? throw new ArgumentException("--assembly is required.");
    var contains = GetOption(args, "--contains");
    var calls = ManagedCallCatalog.Read(assembly)
        .Where(call => contains is null || call.TargetFullName.Contains(contains, StringComparison.OrdinalIgnoreCase))
        .ToArray();
    Console.WriteLine(JsonSerializer.Serialize(calls, new JsonSerializerOptions { WriteIndented = true }));
    return 0;
}

static int ExportMethods(string[] args)
{
    var assembly = GetOption(args, "--assembly")
                   ?? throw new ArgumentException("--assembly is required.");
    var contains = GetOption(args, "--contains");
    var methods = ManagedMethodCatalog.Read(assembly)
        .Where(method => contains is null || method.FullName.Contains(contains, StringComparison.OrdinalIgnoreCase))
        .ToArray();
    Console.WriteLine(JsonSerializer.Serialize(methods, new JsonSerializerOptions { WriteIndented = true }));
    return 0;
}

static int BuildCompositeCatalog(string[] args)
{
    var repositoryRoot = Path.GetFullPath(GetOption(args, "--repo") ?? Directory.GetCurrentDirectory());
    var rulesPath = GetOption(args, "--rules");
    var result = CompositeTextCatalog.Build(repositoryRoot, rulesPath);
    Console.WriteLine(JsonSerializer.Serialize(result, new JsonSerializerOptions { WriteIndented = true }));
    return 0;
}

static int ExportCompositeCsv(string[] args)
{
    var repositoryRoot = Path.GetFullPath(GetOption(args, "--repo") ?? Directory.GetCurrentDirectory());
    var databasePath = Path.GetFullPath(GetOption(args, "--database")
        ?? Path.Combine(repositoryRoot, ".cache", "atg-catalog.sqlite"));
    var rulesPath = Path.GetFullPath(GetOption(args, "--rules")
        ?? Path.Combine(repositoryRoot, "translations", "composite-text-rules.json"));
    var csvPath = Path.GetFullPath(GetOption(args, "--csv")
        ?? throw new ArgumentException("composite-csv requires --csv."));
    var result = ReviewViewCsvExporter.ExportComposite(databasePath, rulesPath, csvPath);
    Console.WriteLine(JsonSerializer.Serialize(result, new JsonSerializerOptions { WriteIndented = true }));
    return 0;
}

static int ExportKnownTextsCsv(string[] args)
{
    var repositoryRoot = Path.GetFullPath(GetOption(args, "--repo") ?? Directory.GetCurrentDirectory());
    var databasePath = Path.GetFullPath(GetOption(args, "--database")
        ?? Path.Combine(repositoryRoot, ".cache", "atg-catalog.sqlite"));
    var rulesPath = Path.GetFullPath(GetOption(args, "--rules")
        ?? Path.Combine(repositoryRoot, "translations", "composite-text-rules.json"));
    var csvPath = Path.GetFullPath(GetOption(args, "--csv")
        ?? throw new ArgumentException("known-texts-csv requires --csv."));
    var result = ReviewViewCsvExporter.ExportKnownTexts(databasePath, rulesPath, csvPath);
    Console.WriteLine(JsonSerializer.Serialize(result, new JsonSerializerOptions { WriteIndented = true }));
    return 0;
}

static int ExportTodoCsv(string[] args)
{
    var repositoryRoot = Path.GetFullPath(GetOption(args, "--repo") ?? Directory.GetCurrentDirectory());
    var databasePath = Path.GetFullPath(GetOption(args, "--database")
        ?? Path.Combine(repositoryRoot, ".cache", "atg-catalog.sqlite"));
    var rulesPath = Path.GetFullPath(GetOption(args, "--rules")
        ?? Path.Combine(repositoryRoot, "translations", "composite-text-rules.json"));
    var csvPath = Path.GetFullPath(GetOption(args, "--csv")
        ?? throw new ArgumentException("todo-csv requires --csv."));
    var result = ReviewViewCsvExporter.ExportTodo(databasePath, rulesPath, csvPath);
    Console.WriteLine(JsonSerializer.Serialize(result, new JsonSerializerOptions { WriteIndented = true }));
    return 0;
}

static async Task<int> RewriteRuntimeCallsAsync(string[] args)
{
    var repositoryRoot = Path.GetFullPath(GetOption(args, "--repo") ?? Directory.GetCurrentDirectory());
    var runtimeAssembly = GetOption(args, "--runtime-assembly")
                          ?? Path.Combine(repositoryRoot, "tools", "AtG.RuntimeText", "bin", "Release", "net40", "AtG.RuntimeText.dll");
    var cachePath = GetOption(args, "--cache")
                    ?? Path.Combine(repositoryRoot, ".cache", "build-cache.json");
    var jobs = RuntimeTextRedirectPlan.Create(repositoryRoot, runtimeAssembly);
    var results = await RuntimeTextRedirectCoordinator.RunAsync(jobs, new BuildCache(cachePath));
    var total = results.Sum(result => result.RedirectedCount);
    var frameBoundaryHooks = results.Sum(result => result.FrameBoundaryHookCount);
    var warmsetStartupHooks = results.Sum(result => result.WarmsetStartupHookCount);
    var startupGraphicsHooks = results.Sum(result => result.StartupGraphicsHookCount);
    if (total != 145) throw new InvalidDataException($"Expected 145 runtime text redirects, got {total}.");
    if (frameBoundaryHooks != 1)
        throw new InvalidDataException(
            $"Expected one runtime frame-boundary hook, got {frameBoundaryHooks}.");
    if (warmsetStartupHooks != 1)
        throw new InvalidDataException(
            $"Expected one runtime warmset startup hook, got {warmsetStartupHooks}.");
    if (startupGraphicsHooks != 1)
        throw new InvalidDataException(
            $"Expected one runtime startup graphics hook, got {startupGraphicsHooks}.");
    var summary = new
    {
        Command = "runtime-rewrite",
        RedirectedCount = total,
        RenderingRedirectCount = jobs.Sum(job => job.ExpectedRenderingRedirectCount),
        FontLoadRedirectCount = jobs.Sum(job => job.ExpectedFontLoadRedirectCount),
        LifecycleRedirectCount = jobs.Sum(job => job.ExpectedLifecycleRedirectCount),
        LayoutRedirectCount = jobs.Sum(job => job.ExpectedLayoutRedirectCount),
        LocalizationRedirectCount = jobs.Sum(job => job.ExpectedLocalizationRedirectCount),
        FrameBoundaryHookCount = frameBoundaryHooks,
        WarmsetStartupHookCount = warmsetStartupHooks,
        StartupGraphicsHookCount = startupGraphicsHooks,
        Jobs = results,
    };
    var json = JsonSerializer.Serialize(summary, new JsonSerializerOptions { WriteIndented = true });
    Console.WriteLine(json);
    var summaryPath = Path.Combine(repositoryRoot, ".cache", "runtime-hook-summary.json");
    File.WriteAllText(summaryPath, json);
    return 0;
}

static int BuildRuntimeDisplayMap(string[] args)
{
    var repositoryRoot = Path.GetFullPath(GetOption(args, "--repo") ?? Directory.GetCurrentDirectory());
    var commonAssembly = GetOption(args, "--common-assembly")
        ?? Path.Combine(repositoryRoot, "source", "AtTheGatesCommon.original.dll");
    var mapPath = GetOption(args, "--map")
        ?? Path.Combine(repositoryRoot, "translations", "runtime-display-strings.json");
    var outputPath = GetOption(args, "--output")
        ?? Path.Combine(repositoryRoot, "patch", "Content", "Text", "AtG.RuntimeText.tsv");
    var result = RuntimeDisplayMapBuilder.Build(commonAssembly,
        "AtTheGatesCommon.ns_UI.Concepts", mapPath, outputPath);
    Console.WriteLine(JsonSerializer.Serialize(result,
        new JsonSerializerOptions { WriteIndented = true }));
    return 0;
}

static int PatchLoadLifecycle(string[] args)
{
    var repositoryRoot = Path.GetFullPath(GetOption(args, "--repo") ?? Directory.GetCurrentDirectory());
    var rendererMode = GetOption(args, "--renderer-mode") ?? "DynamicCjk";
    if (rendererMode is not ("DynamicCjk" or "MergedFonts"))
        throw new ArgumentException($"Unknown renderer mode '{rendererMode}'.");

    var inputDirectory = rendererMode == "DynamicCjk"
        ? Path.Combine(repositoryRoot, ".cache", "runtime-hook")
        : Path.Combine(repositoryRoot, ".cache", "managed-rewrite");
    var gameInput = Path.GetFullPath(GetOption(args, "--game-input")
                                     ?? Path.Combine(inputDirectory, "At The Gates.exe"));
    var elfToolsInput = Path.GetFullPath(GetOption(args, "--elftools-input")
                                         ?? Path.Combine(inputDirectory, "ElfTools.dll"));
    var outputDirectory = Path.GetFullPath(GetOption(args, "--output-directory")
                                            ?? Path.Combine(repositoryRoot, ".cache", "load-lifecycle"));
    var gameOutput = Path.Combine(outputDirectory, "At The Gates.exe");
    var elfToolsOutput = Path.Combine(outputDirectory, "ElfTools.dll");
    var cachePath = GetOption(args, "--cache")
                    ?? Path.Combine(repositoryRoot, ".cache", "build-cache.json");
    var cache = new BuildCache(cachePath);
    var inputHash = ContentHasher.HashFiles([gameInput, elfToolsInput], "load-lifecycle-v4");
    var outputs = new[] { gameOutput, elfToolsOutput };
    var cacheHit = cache.IsCurrent("load-lifecycle", inputHash, outputs);

    GameLoadResourcePatchResult gameResult;
    GameLoadResourcePatchResult elfToolsResult;
    var stopwatch = Stopwatch.StartNew();
    if (cacheHit)
    {
        gameResult = new GameLoadResourcePatchResult(0, 0, 0, gameOutput);
        elfToolsResult = new GameLoadResourcePatchResult(0, 0, 0, elfToolsOutput);
    }
    else
    {
        Directory.CreateDirectory(outputDirectory);
        elfToolsResult = GameLoadResourceLifecyclePatcher.PatchElfTools(elfToolsInput, elfToolsOutput);
        gameResult = GameLoadResourceLifecyclePatcher.PatchGame(gameInput, gameOutput);
        cache.Record("load-lifecycle", inputHash, outputs);
    }
    stopwatch.Stop();

    var summary = new
    {
        Command = "load-lifecycle",
        RendererMode = rendererMode,
        CacheHit = cacheHit,
        ElapsedMilliseconds = stopwatch.ElapsedMilliseconds,
        Game = gameResult,
        ElfTools = elfToolsResult,
    };
    var json = JsonSerializer.Serialize(summary, new JsonSerializerOptions { WriteIndented = true });
    Console.WriteLine(json);
    var summaryPath = GetOption(args, "--summary");
    if (summaryPath is not null)
    {
        summaryPath = Path.GetFullPath(summaryPath);
        Directory.CreateDirectory(Path.GetDirectoryName(summaryPath)!);
        File.WriteAllText(summaryPath, json);
    }

    return 0;
}

static void PrintUsage()
{
    Console.WriteLine("AtG.Patch.Cli rewrite [--repo PATH] [--cache PATH] [--summary PATH]");
    Console.WriteLine("AtG.Patch.Cli catalog <import|export|rebuild|stats> [catalog options]");
    Console.WriteLine("AtG.Patch.Cli composite-catalog --repo PATH [--rules PATH]");
    Console.WriteLine("AtG.Patch.Cli known-texts-csv --repo PATH [--database PATH] [--rules PATH] --csv PATH");
    Console.WriteLine("AtG.Patch.Cli composite-csv --repo PATH [--database PATH] [--rules PATH] --csv PATH");
    Console.WriteLine("AtG.Patch.Cli todo-csv --repo PATH [--database PATH] [--rules PATH] --csv PATH");
    Console.WriteLine("AtG.Patch.Cli calls --assembly PATH [--contains TEXT]");
    Console.WriteLine("AtG.Patch.Cli methods --assembly PATH [--contains TEXT]");
    Console.WriteLine("AtG.Patch.Cli runtime-rewrite --repo PATH --runtime-assembly PATH");
    Console.WriteLine("AtG.Patch.Cli runtime-map --repo PATH [--map PATH] [--output PATH]");
    Console.WriteLine("AtG.Patch.Cli load-lifecycle --repo PATH --renderer-mode <DynamicCjk|MergedFonts>");
}
