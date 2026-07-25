using System.Globalization;
using dnlib.DotNet;
using dnlib.DotNet.Emit;
using dnlib.DotNet.Writer;

namespace AtG.ManagedRewrite;

public sealed record MethodEntryHookSpec(
    string CallerMethodToken,
    string TargetMethodToken,
    int ExpectedCount,
    bool PassCallerInstance = false);

public sealed record MethodEntryHookResult(int InjectedCount, string OutputPath);

public static class ManagedMethodEntryInjector
{
    public static MethodEntryHookResult Inject(
        string sourceAssemblyPath,
        string outputAssemblyPath,
        string targetAssemblyPath,
        IReadOnlyList<MethodEntryHookSpec> specs)
    {
        using var sourceModule = ModuleDefMD.Load(Path.GetFullPath(sourceAssemblyPath));
        using var targetModule = ModuleDefMD.Load(Path.GetFullPath(targetAssemblyPath));
        var importer = new Importer(sourceModule, ImporterOptions.TryToUseDefs);
        var injected = 0;

        foreach (var spec in specs)
        {
            var callerToken = ParseToken(spec.CallerMethodToken);
            var targetToken = ParseToken(spec.TargetMethodToken);
            var caller = sourceModule.GetTypes().SelectMany(type => type.Methods)
                .SingleOrDefault(method => method.MDToken.Raw == callerToken && method.HasBody);
            var target = targetModule.GetTypes().SelectMany(type => type.Methods)
                .SingleOrDefault(method => method.MDToken.Raw == targetToken);
            var matches = caller is null || target is null ? 0 : 1;
            if (matches != spec.ExpectedCount)
                throw new InvalidDataException(
                    $"Expected {spec.ExpectedCount} method-entry hook target(s), found {matches}: " +
                    $"caller={spec.CallerMethodToken}, target={spec.TargetMethodToken}.");
            if (matches == 0) continue;

            Validate(caller!, target!, spec.PassCallerInstance);
            var importedTarget = importer.Import(target!);
            if (spec.PassCallerInstance)
            {
                caller!.Body.Instructions.Insert(0, Instruction.Create(OpCodes.Ldarg_0));
                caller.Body.Instructions.Insert(1, Instruction.Create(OpCodes.Call, importedTarget));
            }
            else caller!.Body.Instructions.Insert(0, Instruction.Create(OpCodes.Call, importedTarget));
            caller.Body.UpdateInstructionOffsets();
            injected++;
        }

        var output = Path.GetFullPath(outputAssemblyPath);
        Directory.CreateDirectory(Path.GetDirectoryName(output)!);
        var writerOptions = new ModuleWriterOptions(sourceModule)
        {
            Logger = DummyLogger.NoThrowInstance,
        };
        writerOptions.MetadataOptions.Flags = MetadataFlags.PreserveAll;
        sourceModule.Write(output, writerOptions);
        return new MethodEntryHookResult(injected, output);
    }

    private static void Validate(MethodDef caller, MethodDef target, bool passCallerInstance)
    {
        if (!caller.HasBody || caller.Body.Instructions.Count == 0)
            throw new InvalidDataException($"Method-entry hook caller must have a body: {caller.FullName}");
        var signature = target.MethodSig;
        var expectedParameters = passCallerInstance ? 1 : 0;
        if (!target.IsStatic || signature is null || signature.Params.Count != expectedParameters ||
            signature.RetType.ElementType != ElementType.Void ||
            (passCallerInstance && (caller.IsStatic ||
                signature.Params[0].ElementType != ElementType.Object)))
            throw new InvalidDataException(
                $"Method-entry hook target has an incompatible signature: {target.FullName}");
    }

    private static uint ParseToken(string token)
    {
        var text = token.StartsWith("0x", StringComparison.OrdinalIgnoreCase) ? token[2..] : token;
        return uint.Parse(text, NumberStyles.HexNumber, CultureInfo.InvariantCulture);
    }
}
