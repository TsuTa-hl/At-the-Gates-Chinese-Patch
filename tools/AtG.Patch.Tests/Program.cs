using AtG.Patch.Core.Build;
using AtG.ManagedRewrite;
using dnlib.DotNet;
using dnlib.DotNet.Emit;

var tests = new (string Name, Action Body)[]
{
    ("Content hash is stable across input ordering", ContentHashIsStable),
    ("Content hash changes with file content", ContentHashChanges),
    ("Build cache validates all declared outputs", BuildCacheValidatesOutputs),
    ("Build cache records parallel stages atomically", BuildCacheRecordsParallelStages),
    ("Managed rewriter replaces one exact ldstr", ManagedRewriterReplacesExactString),
    ("Rewrite map loads exact context", RewriteMapLoadsExactContext),
    ("Rewrite coordinator caches completed jobs", RewriteCoordinatorCachesJobs),
    ("Repository rewrite plan discovers all available assemblies", RepositoryRewritePlanDiscoversAssemblies),
    ("Managed rewriter redirects an instance call to a static shim", ManagedRewriterRedirectsCall),
    ("Managed rewriter registers a returned value with exact metadata", ManagedRewriterRegistersReturnedValue),
    ("Managed rewriter redirects a constructed generic call", ManagedRewriterRedirectsConstructedGenericCall),
    ("Managed rewriter filters one string field at method entry", ManagedRewriterFiltersStringField),
    ("Runtime display map preserves all valid concept keys", RuntimeDisplayMapPreservesConceptKeys),
    ("Runtime display map imports approved single concept tags", RuntimeDisplayMapImportsConceptTags),
    ("Load lifecycle patch releases only IdSpriteBatch owned resources", LoadLifecyclePatchReleasesOwnedResources),
    ("Load lifecycle patch clears stale world roots before loading", LoadLifecyclePatchClearsStaleWorldRoots),
};

var failures = 0;
foreach (var test in tests)
{
    try
    {
        test.Body();
        Console.WriteLine($"PASS {test.Name}");
    }
    catch (Exception ex)
    {
        failures++;
        Console.Error.WriteLine($"FAIL {test.Name}: {ex.Message}");
    }
}

return failures == 0 ? 0 : 1;

static void ContentHashIsStable()
{
    using var temp = new TempDirectory();
    var a = temp.Write("a.txt", "alpha");
    var b = temp.Write("b.txt", "beta");
    var first = ContentHasher.HashFiles(new[] { a, b }, "v1");
    var second = ContentHasher.HashFiles(new[] { b, a }, "v1");
    Assert.Equal(first, second);
}

static void ContentHashChanges()
{
    using var temp = new TempDirectory();
    var path = temp.Write("input.txt", "before");
    var before = ContentHasher.HashFiles(new[] { path }, "v1");
    File.WriteAllText(path, "after");
    var after = ContentHasher.HashFiles(new[] { path }, "v1");
    Assert.NotEqual(before, after);
}

static void BuildCacheValidatesOutputs()
{
    using var temp = new TempDirectory();
    var cachePath = Path.Combine(temp.Path, "cache.json");
    var output = temp.Write("output.bin", "patched");
    var cache = new BuildCache(cachePath);
    cache.Record("ui", "abc123", new[] { output });
    Assert.True(cache.IsCurrent("ui", "abc123", new[] { output }));
    File.Delete(output);
    Assert.False(cache.IsCurrent("ui", "abc123", new[] { output }));
}

static void BuildCacheRecordsParallelStages()
{
    using var temp = new TempDirectory();
    var cachePath = Path.Combine(temp.Path, "cache.json");
    var cache = new BuildCache(cachePath);
    var outputs = Enumerable.Range(0, 64)
        .Select(index => temp.Write($"outputs/{index}.bin", index.ToString()))
        .ToArray();

    Parallel.For(0, outputs.Length, index =>
        cache.Record($"stage-{index}", $"hash-{index}", [outputs[index]]));

    var reloaded = new BuildCache(cachePath);
    for (var index = 0; index < outputs.Length; index++)
        Assert.True(reloaded.IsCurrent($"stage-{index}", $"hash-{index}", [outputs[index]]));
}

static void ManagedRewriterReplacesExactString()
{
    using var temp = new TempDirectory();
    var source = typeof(RewriteFixture).Assembly.Location;
    var output = System.IO.Path.Combine(temp.Path, "patched.dll");
    var entry = LdstrCatalog.Read(source).Single(x => x.Value == RewriteFixture.Value());
    var result = ManagedAssemblyRewriter.Rewrite(source, output,
    [
        new StringRewriteSpec(entry.MethodToken, entry.IlOffset, entry.Value, "rewrite-fixture-translated"),
    ]);

    Assert.Equal(1, result.RewrittenCount);
    Assert.True(File.Exists(output));
    Assert.True(LdstrCatalog.Read(output).Any(x => x.Value == "rewrite-fixture-translated"));
    Assert.False(LdstrCatalog.Read(output).Any(x =>
        x.MethodToken == entry.MethodToken && x.IlOffset == entry.IlOffset && x.Value == entry.Value));
}

static void RewriteMapLoadsExactContext()
{
    using var temp = new TempDirectory();
    var path = temp.Write("map.json", """
        [
          {
            "MethodToken": "0x06000001",
            "ILOffset": 12,
            "Original": "before",
            "Translation": "之后"
          }
        ]
        """);
    var specs = RewriteMap.Load(path);
    Assert.Equal(1, specs.Count);
    Assert.Equal("0x06000001", specs[0].MethodToken);
    Assert.Equal(12, specs[0].IlOffset);
    Assert.Equal("before", specs[0].Original);
    Assert.Equal("之后", specs[0].Translation);
}

static void RewriteCoordinatorCachesJobs()
{
    using var temp = new TempDirectory();
    var source = typeof(RewriteFixture).Assembly.Location;
    var entry = LdstrCatalog.Read(source).Single(x => x.Value == RewriteFixture.Value());
    var map = temp.Write("map.json", $$"""
        [{
          "MethodToken": "{{entry.MethodToken}}",
          "ILOffset": {{entry.IlOffset}},
          "Original": "{{entry.Value}}",
          "Translation": "协调器译文"
        }]
        """);
    var output = System.IO.Path.Combine(temp.Path, "output.dll");
    var cache = new BuildCache(System.IO.Path.Combine(temp.Path, "build-cache.json"));
    var job = new RewriteJob("fixture", source, output, map);

    var first = ManagedRewriteCoordinator.RunAsync([job], cache).GetAwaiter().GetResult();
    var second = ManagedRewriteCoordinator.RunAsync([job], cache).GetAwaiter().GetResult();

    Assert.Equal(1, first.Single().RewrittenCount);
    Assert.False(first.Single().CacheHit);
    Assert.True(second.Single().CacheHit);
}

static void RepositoryRewritePlanDiscoversAssemblies()
{
    using var temp = new TempDirectory();
    temp.Write("source/AtTheGatesUI.original.dll", "fixture");
    temp.Write("translations/hardcoded-ui-il-rewrite.json", "[]");
    temp.Write("source/ElfTools.original.dll", "fixture");
    temp.Write("translations/hardcoded-elftools-il-rewrite.json", "[]");

    var jobs = RepositoryRewritePlan.Create(temp.Path);

    Assert.Equal(2, jobs.Count);
    Assert.Equal("ui", jobs[0].Name);
    Assert.Equal("elftools", jobs[1].Name);
    Assert.True(jobs.All(job => job.OutputPath.StartsWith(
        Path.Combine(temp.Path, ".cache", "managed-rewrite"),
        StringComparison.OrdinalIgnoreCase)));
}

static void ManagedRewriterRedirectsCall()
{
    using var temp = new TempDirectory();
    var source = typeof(CallRedirectFixture).Assembly.Location;
    var output = Path.Combine(temp.Path, "redirected.dll");
    var calls = ManagedCallCatalog.Read(source);
    var sourceCall = calls.Single(call =>
        call.CallerType.EndsWith(nameof(CallRedirectFixture), StringComparison.Ordinal) &&
        call.CallerMethod == nameof(CallRedirectFixture.Invoke) &&
        call.TargetFullName.Contains("System.String::Trim()", StringComparison.Ordinal));
    var target = ManagedMethodCatalog.Read(source).Single(method =>
        method.DeclaringType.EndsWith(nameof(CallRedirectTarget), StringComparison.Ordinal) &&
        method.Name == nameof(CallRedirectTarget.Trim));

    var result = ManagedCallRedirector.Redirect(source, output, source,
    [
        new CallRedirectSpec(sourceCall.TargetFullName, target.MetadataToken, 1,
            sourceCall.CallerToken, sourceCall.IlOffset),
    ]);

    Assert.Equal(1, result.RedirectedCount);
    var redirected = ManagedCallCatalog.Read(output).Single(call =>
        call.CallerType.EndsWith(nameof(CallRedirectFixture), StringComparison.Ordinal) &&
        call.CallerMethod == nameof(CallRedirectFixture.Invoke));
    Assert.True(redirected.TargetFullName.Contains(nameof(CallRedirectTarget), StringComparison.Ordinal));
    Assert.Equal("call", redirected.OpCode);
}

static void ManagedRewriterRegistersReturnedValue()
{
    using var temp = new TempDirectory();
    var source = typeof(ReturnRegistrationFixture).Assembly.Location;
    var output = Path.Combine(temp.Path, "registered.dll");
    var caller = ManagedMethodCatalog.Read(source).Single(method =>
        method.DeclaringType.EndsWith(nameof(ReturnRegistrationFixture), StringComparison.Ordinal) &&
        method.Name == nameof(ReturnRegistrationFixture.Get));
    var target = ManagedMethodCatalog.Read(source).Single(method =>
        method.DeclaringType.EndsWith(nameof(ReturnRegistrationTarget), StringComparison.Ordinal) &&
        method.Name == nameof(ReturnRegistrationTarget.RegisterAndReturn));

    var result = ManagedReturnValueRegistrar.Register(source, output, source,
    [
        new ReturnValueRegistrationSpec(caller.MetadataToken, target.MetadataToken,
            "SegoeUI_15_Bold", 15f, true, 1),
    ]);

    Assert.Equal(1, result.RegisteredCount);
    var outputCaller = ManagedMethodCatalog.Read(output).Single(method =>
        method.DeclaringType.EndsWith(nameof(ReturnRegistrationFixture), StringComparison.Ordinal) &&
        method.Name == nameof(ReturnRegistrationFixture.Get));
    Assert.Equal(caller.MetadataToken, outputCaller.MetadataToken);
    var call = ManagedCallCatalog.Read(output).Single(entry =>
        entry.CallerType.EndsWith(nameof(ReturnRegistrationFixture), StringComparison.Ordinal) &&
        entry.CallerMethod == nameof(ReturnRegistrationFixture.Get));
    if (!call.TargetFullName.Contains(nameof(ReturnRegistrationTarget), StringComparison.Ordinal))
        throw new InvalidOperationException($"Registration call targets '{call.TargetFullName}'.");
    var strings = LdstrCatalog.Read(output);
    if (!strings.Any(entry => entry.TypeFullName.EndsWith(nameof(ReturnRegistrationFixture), StringComparison.Ordinal) &&
        entry.MethodName == nameof(ReturnRegistrationFixture.Get) && entry.Value == "SegoeUI_15_Bold"))
        throw new InvalidOperationException($"Injected font name was not found in caller {caller.MetadataToken}. " +
            string.Join("; ", strings.Where(entry => entry.Value == "SegoeUI_15_Bold")
                .Select(entry => $"{entry.TypeFullName}.{entry.MethodName} {entry.MethodToken}")));
}

static void ManagedRewriterRedirectsConstructedGenericCall()
{
    using var temp = new TempDirectory();
    var source = typeof(GenericCallFixture).Assembly.Location;
    var output = Path.Combine(temp.Path, "generic-redirected.dll");
    var sourceCall = ManagedCallCatalog.Read(source).Single(call =>
        call.CallerType.EndsWith(nameof(GenericCallFixture), StringComparison.Ordinal) &&
        call.CallerMethod == nameof(GenericCallFixture.Invoke) &&
        call.TargetFullName.Contains("Identity<System.String>", StringComparison.Ordinal));
    var target = ManagedMethodCatalog.Read(source).Single(method =>
        method.DeclaringType.EndsWith(nameof(GenericCallTarget), StringComparison.Ordinal) &&
        method.Name == nameof(GenericCallTarget.Pass));

    var result = ManagedCallRedirector.Redirect(source, output, source,
    [
        new CallRedirectSpec(sourceCall.TargetFullName, target.MetadataToken, 1,
            sourceCall.CallerToken, sourceCall.IlOffset),
    ]);

    Assert.Equal(1, result.RedirectedCount);
}

static void ManagedRewriterFiltersStringField()
{
    using var temp = new TempDirectory();
    var source = typeof(FieldFilterFixture).Assembly.Location;
    var output = Path.Combine(temp.Path, "field-filtered.dll");
    var caller = ManagedMethodCatalog.Read(source).Single(method =>
        method.DeclaringType.EndsWith(nameof(FieldFilterFixture), StringComparison.Ordinal) &&
        method.Name == nameof(FieldFilterFixture.Process));
    var target = ManagedMethodCatalog.Read(source).Single(method =>
        method.DeclaringType.EndsWith(nameof(FieldFilterTarget), StringComparison.Ordinal) &&
        method.Name == nameof(FieldFilterTarget.Filter));
    var fieldName = "System.String " + typeof(FieldFilterFixture).FullName + "::RawText";

    var result = ManagedStringFieldFilterInjector.Inject(source, output, source,
    [
        new StringFieldFilterSpec(caller.MetadataToken, fieldName, target.MetadataToken, 1),
    ]);

    Assert.Equal(1, result.InjectedCount);
    var injected = ManagedCallCatalog.Read(output).Single(call =>
        call.CallerType.EndsWith(nameof(FieldFilterFixture), StringComparison.Ordinal) &&
        call.CallerMethod == nameof(FieldFilterFixture.Process));
    Assert.True(injected.TargetFullName.Contains(nameof(FieldFilterTarget), StringComparison.Ordinal));
}

static void RuntimeDisplayMapPreservesConceptKeys()
{
    using var temp = new TempDirectory();
    var map = temp.Write("runtime-display.json", """
        {
          "Exact": [{ "Original": "Close", "Translation": "\u5173\u95ed" }],
          "PlainText": [{ "Original": "Train ", "Translation": "\u8bad\u7ec3" }],
          "PlainTextFragments": [{ "Original": "engage in ", "Translation": "\u5377\u5165" }],
          "ConceptDisplay": [{ "ConceptKey": "CLAN", "Original": "Clan", "Translation": "\u6c0f\u65cf" }]
        }
        """);
    var output = Path.Combine(temp.Path, "AtG.RuntimeText.tsv");

    var result = RuntimeDisplayMapBuilder.Build(
        typeof(RuntimeMapConceptFixture).Assembly.Location,
        typeof(RuntimeMapConceptFixture).FullName!, map, output);

    Assert.True(result.ConceptKeyCount >= 2);
    var lines = File.ReadAllLines(output);
    Assert.True(lines.Any(line => line == "K\t" + RuntimeMapConceptFixture.Encode("CLAN")));
    Assert.True(lines.Any(line => line == "K\t" + RuntimeMapConceptFixture.Encode("TURN")));
    Assert.True(lines.Any(line => line == "C\t" + RuntimeMapConceptFixture.Encode("CLAN") + "\t" +
        RuntimeMapConceptFixture.Encode("Clan") + "\t" + RuntimeMapConceptFixture.Encode("\u6c0f\u65cf")));
    Assert.Equal(1, result.PlainTextFragmentCount);
    Assert.True(lines.Any(line => line == "F\t" + RuntimeMapConceptFixture.Encode("engage in ") + "\t" +
        RuntimeMapConceptFixture.Encode("\u5377\u5165")));
}

static void RuntimeDisplayMapImportsConceptTags()
{
    using var temp = new TempDirectory();
    temp.Write("approved-concepts.json", """
        {
          "[Clan|CLAN]": "[\u6c0f\u65cf|CLAN]",
          "[Turn|TURN]": "[\u56de\u5408|TURN]",
          "Click [Clan|CLAN]": "\u70b9\u51fb[\u6c0f\u65cf|CLAN]"
        }
        """);
    var map = temp.Write("runtime-display.json", """
        {
          "ConceptDisplaySources": ["approved-concepts.json"]
        }
        """);
    var output = Path.Combine(temp.Path, "AtG.RuntimeText.tsv");

    var result = RuntimeDisplayMapBuilder.Build(
        typeof(RuntimeMapConceptFixture).Assembly.Location,
        typeof(RuntimeMapConceptFixture).FullName!, map, output);

    Assert.Equal(2, result.ConceptDisplayCount);
    var lines = File.ReadAllLines(output);
    Assert.True(lines.Any(line => line == "C\t" + RuntimeMapConceptFixture.Encode("CLAN") + "\t" +
        RuntimeMapConceptFixture.Encode("Clan") + "\t" +
        RuntimeMapConceptFixture.Encode("\u6c0f\u65cf")));
    Assert.True(lines.Any(line => line == "C\t" + RuntimeMapConceptFixture.Encode("TURN") + "\t" +
        RuntimeMapConceptFixture.Encode("Turn") + "\t" +
        RuntimeMapConceptFixture.Encode("\u56de\u5408")));
}

static void LoadLifecyclePatchReleasesOwnedResources()
{
    using var temp = new TempDirectory();
    var repositoryRoot = FindRepositoryRoot();
    var source = Path.Combine(repositoryRoot, "source", "ElfTools.original.dll");
    var output = Path.Combine(temp.Path, "ElfTools.dll");

    GameLoadResourceLifecyclePatcher.PatchElfTools(source, output);

    using var module = ModuleDefMD.Load(output);
    var type = module.GetTypes().Single(candidate =>
        candidate.FullName == "ElfTools.Graphics.ElfSpriteBatch.IdBatch.IdSpriteBatch");
    var method = type.Methods.Single(candidate =>
        candidate.Name == "Dispose" && candidate.MethodSig?.Params.Count == 1);
    var instructions = method.Body?.Instructions
        ?? throw new InvalidOperationException("Patched IdSpriteBatch.Dispose body is missing.");

    Assert.True(instructions.Any(instruction =>
        instruction.Operand is IField field && field.Name == "indexBuf"));
    Assert.False(instructions.Any(instruction =>
        instruction.Operand is IField field && field.Name == "_defaultEffect"));
    Assert.Equal(1, instructions.Count(instruction =>
        instruction.Operand is IMethod called &&
        called.FullName == "System.Void Microsoft.Xna.Framework.Graphics.GraphicsResource::Dispose()"));
}

static void LoadLifecyclePatchClearsStaleWorldRoots()
{
    using var temp = new TempDirectory();
    var repositoryRoot = FindRepositoryRoot();
    var source = Path.Combine(repositoryRoot, "source", "AtTheGatesGame.original.exe");
    var output = Path.Combine(temp.Path, "At The Gates.exe");

    GameLoadResourceLifecyclePatcher.PatchGame(source, output);

    if (!IsLargeAddressAware(output))
        throw new InvalidOperationException(
            "Patched x86 game executable must be large-address aware.");
    using var sourceModule = ModuleDefMD.Load(source);
    using var module = ModuleDefMD.Load(output);
    if (module.GetAssemblyRefs().Any(reference =>
            reference.Name == "System.Private.CoreLib"))
        throw new InvalidOperationException(
            "The .NET Framework game patch must not reference System.Private.CoreLib.");
    var application = module.GetTypes().Single(candidate =>
        candidate.FullName == "AtTheGatesGame.ns_UIControllers.ATGApplication");
    var method = application.Methods.Single(candidate => candidate.Name == "LoadGame_Step2");
    var instructions = method.Body?.Instructions
        ?? throw new InvalidOperationException("Patched LoadGame_Step2 body is missing.");

    var createIndex = FindCall(instructions, "ATGApplication::CreateWorldScreen()");
    var disposeIndex = FindCall(instructions, "IdSpriteBatch::Dispose(System.Boolean)");
    var clearRootsIndex = FindCall(instructions, "DebugConsole::AtGClearWorldReferences()");
    var loadIndex = FindCall(instructions, "ATGApplication::LoadFromFile(System.String)");
    if (!(createIndex >= 0 && disposeIndex > createIndex &&
          clearRootsIndex > disposeIndex && loadIndex > clearRootsIndex))
        throw new InvalidOperationException(
            $"Unexpected teardown order: create={createIndex}, dispose={disposeIndex}, " +
            $"clear={clearRootsIndex}, load={loadIndex}.");

    var debugConsole = module.GetTypes().Single(candidate =>
        candidate.FullName == "AtTheGatesGame.DebugConsoleNS.DebugConsole");
    var clearRoots = debugConsole.Methods.Single(candidate =>
        candidate.Name == "AtGClearWorldReferences");
    if (!clearRoots.IsPublic || !clearRoots.IsStatic)
        throw new InvalidOperationException(
            $"AtGClearWorldReferences must be public static; attributes={clearRoots.Attributes}.");
    var clearInstructions = clearRoots.Body?.Instructions
        ?? throw new InvalidOperationException("AtGClearWorldReferences body is missing.");
    var sourceApplication = sourceModule.GetTypes().Single(candidate =>
        candidate.FullName == "AtTheGatesGame.ns_UIControllers.ATGApplication");
    var sourceLoadGame = sourceApplication.Methods.Single(candidate =>
        candidate.Name == "LoadGame_Step2");
    var sourceInstructions = sourceLoadGame.Body?.Instructions
        ?? throw new InvalidOperationException("Original LoadGame_Step2 body is missing.");
    foreach (var fieldName in new[] { "WSC", "Human", "MouseoverTile", "SelectedObject" })
    {
        if (!HasNullStaticFieldStoreBetween(
                clearInstructions, fieldName, -1, clearInstructions.Count))
            throw new InvalidOperationException(
                $"AtGClearWorldReferences does not clear DebugConsole.{fieldName}.");
        var originalDirectStores = sourceInstructions.Count(instruction =>
            instruction.OpCode == OpCodes.Stsfld &&
            instruction.Operand is IField field && field.Name == fieldName);
        var patchedDirectStores = instructions.Count(instruction =>
            instruction.OpCode == OpCodes.Stsfld &&
            instruction.Operand is IField field && field.Name == fieldName);
        if (patchedDirectStores != originalDirectStores)
            throw new InvalidOperationException(
                $"LoadGame_Step2 changed direct DebugConsole.{fieldName} stores: " +
                $"original={originalDirectStores}, patched={patchedDirectStores}.");
    }

    var clearBatchIndex = FindCall(instructions, "ATGGAME::set_IdSpriteBatch(");
    if (!(clearBatchIndex > disposeIndex && clearBatchIndex < loadIndex))
        throw new InvalidOperationException(
            $"Unexpected IdSpriteBatch clear order: dispose={disposeIndex}, " +
            $"clearBatch={clearBatchIndex}, load={loadIndex}.");

    var loadWorld = application.Methods.Single(candidate => candidate.Name == "LoadWorld");
    var loadWorldInstructions = loadWorld.Body?.Instructions
        ?? throw new InvalidOperationException("Patched LoadWorld body is missing.");
    var initIndex = FindCall(loadWorldInstructions, "WorldCore::Init_Load_First()");
    var collectIndex = FindCall(loadWorldInstructions, "System.GC::Collect()");
    var loadDataIndex = FindCall(loadWorldInstructions, "WorldCore::LoadData(ElfTools.Serialize.Loader)");
    if (!(initIndex >= 0 && collectIndex > initIndex && loadDataIndex > collectIndex))
        throw new InvalidOperationException(
            $"Unexpected forced collection order: init={initIndex}, collect={collectIndex}, " +
            $"loadData={loadDataIndex}.");
}

static int FindCall(IList<Instruction> instructions, string targetFragment)
{
    for (var index = 0; index < instructions.Count; index++)
    {
        if (instructions[index].Operand is IMethod method &&
            method.FullName.Contains(targetFragment, StringComparison.Ordinal))
            return index;
    }
    return -1;
}

static bool HasNullStaticFieldStoreBetween(
    IList<Instruction> instructions,
    string fieldName,
    int startIndex,
    int endIndex)
{
    for (var index = Math.Max(startIndex + 1, 1); index < Math.Min(endIndex, instructions.Count); index++)
    {
        if (instructions[index].OpCode != OpCodes.Stsfld ||
            instructions[index].Operand is not IField field ||
            field.Name != fieldName)
            continue;
        if (instructions[index - 1].OpCode == OpCodes.Ldnull)
            return true;
    }
    return false;
}

static bool IsLargeAddressAware(string path)
{
    var bytes = File.ReadAllBytes(path);
    var peHeader = BitConverter.ToInt32(bytes, 0x3c);
    var characteristics = BitConverter.ToUInt16(bytes, peHeader + 22);
    return (characteristics & 0x20) != 0;
}

static string FindRepositoryRoot()
{
    var directory = new DirectoryInfo(AppContext.BaseDirectory);
    while (directory is not null)
    {
        if (File.Exists(Path.Combine(directory.FullName, "AtG.Patch.sln")))
            return directory.FullName;
        directory = directory.Parent;
    }
    throw new DirectoryNotFoundException("AtG.Patch.sln was not found above the test output directory.");
}

static class RewriteFixture
{
    public static string Value() => "rewrite-fixture-original";
}

static class CallRedirectFixture
{
    public static string Invoke(string value) => value.Trim();
}

static class CallRedirectTarget
{
    public static string Trim(string value) => value.Trim();
}

static class ReturnRegistrationFixture
{
    public static string Get() => "registered-value";
}

static class ReturnRegistrationTarget
{
    public static string RegisterAndReturn(string value, string name, float size, bool bold) => value;
}

static class GenericCallFixture
{
    public static string Invoke(string value) => Identity<string>(value);
    private static T Identity<T>(T value) => value;
}

static class GenericCallTarget
{
    public static string Pass(string value) => value;
}

sealed class FieldFilterFixture
{
    public string RawText = "before";
    public string Process() => RawText;
}

static class FieldFilterTarget
{
    public static string Filter(string value) => "filtered:" + value;
}

static class RuntimeMapConceptFixture
{
    public static readonly string[] Values = ["[Clan|CLAN]", "TURN"];
    public static string Encode(string value) =>
        Convert.ToBase64String(System.Text.Encoding.UTF8.GetBytes(value));
}

static class Assert
{
    public static void True(bool value)
    {
        if (!value) throw new InvalidOperationException("Expected true.");
    }

    public static void False(bool value) => True(!value);

    public static void Equal<T>(T expected, T actual)
    {
        if (!EqualityComparer<T>.Default.Equals(expected, actual))
            throw new InvalidOperationException($"Expected '{expected}', actual '{actual}'.");
    }

    public static void NotEqual<T>(T left, T right)
    {
        if (EqualityComparer<T>.Default.Equals(left, right))
            throw new InvalidOperationException($"Expected values to differ, both were '{left}'.");
    }
}

sealed class TempDirectory : IDisposable
{
    public string Path { get; } = System.IO.Path.Combine(
        System.IO.Path.GetTempPath(), "atg-patch-tests", Guid.NewGuid().ToString("N"));

    public TempDirectory() => Directory.CreateDirectory(Path);

    public string Write(string relativePath, string content)
    {
        var path = System.IO.Path.Combine(Path, relativePath);
        Directory.CreateDirectory(System.IO.Path.GetDirectoryName(path)!);
        File.WriteAllText(path, content);
        return path;
    }

    public void Dispose()
    {
        if (Directory.Exists(Path)) Directory.Delete(Path, recursive: true);
    }
}
