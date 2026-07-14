using dnlib.DotNet;
using dnlib.DotNet.Emit;
using dnlib.DotNet.Writer;

namespace AtG.ManagedRewrite;

public sealed record GameLoadResourcePatchResult(
    int OwnedResourceDisposeBodies,
    int LoadTeardownBlocks,
    int ForcedCollectionBlocks,
    string OutputPath);

public static class GameLoadResourceLifecyclePatcher
{
    private const string IdSpriteBatchTypeName =
        "ElfTools.Graphics.ElfSpriteBatch.IdBatch.IdSpriteBatch";
    private const string ApplicationTypeName =
        "AtTheGatesGame.ns_UIControllers.ATGApplication";
    private const string GameGlobalsTypeName =
        "AtTheGatesGame.ns_GameCode.ATGGAME";
    private const string DebugConsoleTypeName =
        "AtTheGatesGame.DebugConsoleNS.DebugConsole";

    public static GameLoadResourcePatchResult PatchElfTools(
        string sourceAssemblyPath,
        string outputAssemblyPath)
    {
        using var module = ModuleDefMD.Load(Path.GetFullPath(sourceAssemblyPath));
        var type = RequireType(module, IdSpriteBatchTypeName);
        var dispose = type.Methods.SingleOrDefault(method =>
            method.Name == "Dispose" && method.MethodSig?.Params.Count == 1 &&
            method.MethodSig.Params[0].FullName == "System.Boolean")
            ?? throw new InvalidDataException("IdSpriteBatch.Dispose(bool) was not found.");
        var indexBuffer = type.Fields.SingleOrDefault(field => field.Name == "indexBuf")
            ?? throw new InvalidDataException("IdSpriteBatch.indexBuf was not found.");
        var isDisposed = type.Fields.SingleOrDefault(field => field.Name == "isDisposed")
            ?? throw new InvalidDataException("IdSpriteBatch.isDisposed was not found.");
        var graphicsDispose = dispose.Body?.Instructions
            .Select(instruction => instruction.Operand)
            .OfType<IMethod>()
            .FirstOrDefault(method => method.FullName ==
                "System.Void Microsoft.Xna.Framework.Graphics.GraphicsResource::Dispose()")
            ?? throw new InvalidDataException("GraphicsResource.Dispose reference was not found.");

        dispose.Body = BuildOwnedResourceDisposeBody(indexBuffer, isDisposed, graphicsDispose);
        Write(module, outputAssemblyPath);
        return new GameLoadResourcePatchResult(1, 0, 0, Path.GetFullPath(outputAssemblyPath));
    }

    public static GameLoadResourcePatchResult PatchGame(
        string sourceAssemblyPath,
        string outputAssemblyPath)
    {
        using var module = ModuleDefMD.Load(Path.GetFullPath(sourceAssemblyPath));
        var application = RequireType(module, ApplicationTypeName);
        var globals = RequireType(module, GameGlobalsTypeName);
        var debugConsole = RequireType(module, DebugConsoleTypeName);

        var teardownBlocks = PatchLoadTeardown(module, application, globals, debugConsole);
        var collectionBlocks = PatchForcedCollection(module, application);

        Write(module, outputAssemblyPath);
        EnableLargeAddressAware(outputAssemblyPath);
        return new GameLoadResourcePatchResult(
            0, teardownBlocks, collectionBlocks, Path.GetFullPath(outputAssemblyPath));
    }

    private static CilBody BuildOwnedResourceDisposeBody(
        FieldDef indexBuffer,
        FieldDef isDisposed,
        IMethod graphicsDispose)
    {
        var body = new CilBody { InitLocals = false, MaxStack = 2 };
        var markDisposed = Instruction.Create(OpCodes.Ldarg_0);

        body.Instructions.Add(Instruction.Create(OpCodes.Ldarg_0));
        body.Instructions.Add(Instruction.Create(OpCodes.Ldfld, isDisposed));
        body.Instructions.Add(Instruction.Create(OpCodes.Brtrue_S, markDisposed));
        body.Instructions.Add(Instruction.Create(OpCodes.Ldarg_0));
        body.Instructions.Add(Instruction.Create(OpCodes.Ldfld, indexBuffer));
        body.Instructions.Add(Instruction.Create(OpCodes.Brfalse_S, markDisposed));
        body.Instructions.Add(Instruction.Create(OpCodes.Ldarg_0));
        body.Instructions.Add(Instruction.Create(OpCodes.Ldfld, indexBuffer));
        body.Instructions.Add(Instruction.Create(OpCodes.Callvirt, graphicsDispose));
        body.Instructions.Add(Instruction.Create(OpCodes.Ldarg_0));
        body.Instructions.Add(Instruction.Create(OpCodes.Ldnull));
        body.Instructions.Add(Instruction.Create(OpCodes.Stfld, indexBuffer));
        body.Instructions.Add(markDisposed);
        body.Instructions.Add(Instruction.Create(OpCodes.Ldc_I4_1));
        body.Instructions.Add(Instruction.Create(OpCodes.Stfld, isDisposed));
        body.Instructions.Add(Instruction.Create(OpCodes.Ret));
        return body;
    }

    private static int PatchLoadTeardown(
        ModuleDef module,
        TypeDef application,
        TypeDef globals,
        TypeDef debugConsole)
    {
        var method = application.Methods.SingleOrDefault(candidate =>
            candidate.Name == "LoadGame_Step2" && candidate.HasBody)
            ?? throw new InvalidDataException("ATGApplication.LoadGame_Step2 was not found.");
        if (method.Body.Instructions.Any(instruction =>
                instruction.Operand is IMethod called &&
                called.FullName.Contains("DebugConsole::AtGClearWorldReferences()",
                    StringComparison.Ordinal)))
            return 0;

        var createWorldScreen = FindCall(method,
            "ATGApplication::CreateWorldScreen()");
        var loadFromFile = FindCall(method,
            "ATGApplication::LoadFromFile(System.String)");
        if (createWorldScreen is null || loadFromFile is null ||
            method.Body.Instructions.IndexOf(createWorldScreen) >=
            method.Body.Instructions.IndexOf(loadFromFile))
            throw new InvalidDataException(
                "Expected CreateWorldScreen before LoadFromFile in LoadGame_Step2.");

        var idSpriteBatchField = globals.Fields.SingleOrDefault(field =>
            field.Name == "<IdSpriteBatch>k__BackingField")
            ?? throw new InvalidDataException("ATGGAME.IdSpriteBatch backing field was not found.");
        var getIdSpriteBatch = globals.Methods.SingleOrDefault(candidate =>
            candidate.Name == "get_IdSpriteBatch")
            ?? throw new InvalidDataException("ATGGAME.get_IdSpriteBatch was not found.");
        var setIdSpriteBatch = globals.Methods.SingleOrDefault(candidate =>
            candidate.Name == "set_IdSpriteBatch")
            ?? throw new InvalidDataException("ATGGAME.set_IdSpriteBatch was not found.");
        var idSpriteBatchType = idSpriteBatchField.FieldType.ToTypeDefOrRef()
            ?? throw new InvalidDataException("IdSpriteBatch type reference was not found.");
        var disposeReference = new MemberRefUser(
            module,
            "Dispose",
            MethodSig.CreateInstance(module.CorLibTypes.Void, module.CorLibTypes.Boolean),
            idSpriteBatchType);
        var staleFields = new[] { "WSC", "Human", "MouseoverTile", "SelectedObject" }
            .Select(name => debugConsole.Fields.SingleOrDefault(field => field.Name == name)
                ?? throw new InvalidDataException($"DebugConsole.{name} was not found."))
            .ToArray();
        var clearWorldReferences = GetOrCreateDebugConsoleClearMethod(
            module, debugConsole, staleFields);

        var oldBatch = new Local(idSpriteBatchField.FieldType);
        method.Body.Variables.Add(oldBatch);
        method.Body.InitLocals = true;
        var skipDispose = Instruction.Create(OpCodes.Nop);
        var patch = new List<Instruction>
        {
            Instruction.Create(OpCodes.Call, getIdSpriteBatch),
            Instruction.Create(OpCodes.Stloc, oldBatch),
            Instruction.Create(OpCodes.Ldloc, oldBatch),
            Instruction.Create(OpCodes.Brfalse_S, skipDispose),
            Instruction.Create(OpCodes.Ldloc, oldBatch),
            Instruction.Create(OpCodes.Ldc_I4_1),
            Instruction.Create(OpCodes.Callvirt, disposeReference),
            skipDispose,
            Instruction.Create(OpCodes.Ldnull),
            Instruction.Create(OpCodes.Call, setIdSpriteBatch),
            Instruction.Create(OpCodes.Call, clearWorldReferences),
        };

        var insertAt = method.Body.Instructions.IndexOf(createWorldScreen) + 1;
        for (var index = 0; index < patch.Count; index++)
            method.Body.Instructions.Insert(insertAt + index, patch[index]);
        method.Body.SimplifyBranches();
        method.Body.OptimizeBranches();
        return 1;
    }

    private static MethodDef GetOrCreateDebugConsoleClearMethod(
        ModuleDef module,
        TypeDef debugConsole,
        IReadOnlyList<FieldDef> staleFields)
    {
        var existing = debugConsole.Methods.SingleOrDefault(candidate =>
            candidate.Name == "AtGClearWorldReferences");
        if (existing is not null) return existing;

        var method = new MethodDefUser(
            "AtGClearWorldReferences",
            MethodSig.CreateStatic(module.CorLibTypes.Void),
            MethodImplAttributes.IL | MethodImplAttributes.Managed,
            MethodAttributes.Public | MethodAttributes.Static | MethodAttributes.HideBySig)
        {
            Body = new CilBody { MaxStack = 1 },
        };
        foreach (var field in staleFields)
        {
            method.Body.Instructions.Add(Instruction.Create(OpCodes.Ldnull));
            method.Body.Instructions.Add(Instruction.Create(OpCodes.Stsfld, field));
        }
        method.Body.Instructions.Add(Instruction.Create(OpCodes.Ret));
        debugConsole.Methods.Add(method);
        return method;
    }

    private static int PatchForcedCollection(ModuleDef module, TypeDef application)
    {
        var method = application.Methods.SingleOrDefault(candidate =>
            candidate.Name == "LoadWorld" && candidate.HasBody)
            ?? throw new InvalidDataException("ATGApplication.LoadWorld was not found.");
        var init = FindCall(method, "WorldCore::Init_Load_First()")
            ?? throw new InvalidDataException("WorldCore.Init_Load_First was not found in LoadWorld.");
        var loadData = FindCall(method, "WorldCore::LoadData(ElfTools.Serialize.Loader)")
            ?? throw new InvalidDataException("WorldCore.LoadData was not found in LoadWorld.");
        var initIndex = method.Body.Instructions.IndexOf(init);
        var loadDataIndex = method.Body.Instructions.IndexOf(loadData);
        var existingCollects = method.Body.Instructions
            .Skip(initIndex + 1)
            .Take(loadDataIndex - initIndex - 1)
            .Count(instruction => instruction.Operand is IMethod called &&
                called.FullName == "System.Void System.GC::Collect()");
        if (existingCollects >= 2) return 0;

        var gcType = module.CorLibTypes.GetTypeRef("System", "GC");
        var collect = new MemberRefUser(
            module,
            "Collect",
            MethodSig.CreateStatic(module.CorLibTypes.Void),
            gcType);
        var wait = new MemberRefUser(
            module,
            "WaitForPendingFinalizers",
            MethodSig.CreateStatic(module.CorLibTypes.Void),
            gcType);
        var insertAt = initIndex + 1;
        if (insertAt < method.Body.Instructions.Count &&
            method.Body.Instructions[insertAt].OpCode == OpCodes.Nop)
            insertAt++;
        var patch = new[]
        {
            Instruction.Create(OpCodes.Call, collect),
            Instruction.Create(OpCodes.Call, wait),
            Instruction.Create(OpCodes.Call, collect),
        };
        for (var index = 0; index < patch.Length; index++)
            method.Body.Instructions.Insert(insertAt + index, patch[index]);
        method.Body.SimplifyBranches();
        method.Body.OptimizeBranches();
        return 1;
    }

    private static TypeDef RequireType(ModuleDef module, string fullName) =>
        module.GetTypes().SingleOrDefault(type => type.FullName == fullName)
        ?? throw new InvalidDataException($"Type was not found: {fullName}");

    private static Instruction? FindCall(MethodDef method, string targetFragment) =>
        method.Body.Instructions.FirstOrDefault(instruction =>
            instruction.Operand is IMethod called &&
            called.FullName.Contains(targetFragment, StringComparison.Ordinal));

    private static void Write(ModuleDef module, string outputAssemblyPath)
    {
        var output = Path.GetFullPath(outputAssemblyPath);
        Directory.CreateDirectory(Path.GetDirectoryName(output)!);
        var options = new ModuleWriterOptions(module)
        {
            Logger = DummyLogger.NoThrowInstance,
        };
        options.MetadataOptions.Flags = MetadataFlags.PreserveAll;
        module.Write(output, options);
    }

    private static void EnableLargeAddressAware(string outputAssemblyPath)
    {
        const ushort largeAddressAware = 0x20;
        using var stream = new FileStream(
            Path.GetFullPath(outputAssemblyPath),
            FileMode.Open,
            FileAccess.ReadWrite,
            FileShare.Read);
        using var reader = new BinaryReader(stream, System.Text.Encoding.UTF8, leaveOpen: true);
        using var writer = new BinaryWriter(stream, System.Text.Encoding.UTF8, leaveOpen: true);

        if (stream.Length < 0x40)
            throw new InvalidDataException("Patched game output is too small to contain a PE header.");
        stream.Position = 0x3c;
        var peHeaderOffset = reader.ReadInt32();
        if (peHeaderOffset < 0 || peHeaderOffset + 24 > stream.Length)
            throw new InvalidDataException("Patched game output has an invalid PE header offset.");
        stream.Position = peHeaderOffset;
        if (reader.ReadUInt32() != 0x00004550)
            throw new InvalidDataException("Patched game output does not contain a PE signature.");

        stream.Position = peHeaderOffset + 22;
        var characteristics = reader.ReadUInt16();
        stream.Position = peHeaderOffset + 22;
        writer.Write((ushort)(characteristics | largeAddressAware));
    }
}
