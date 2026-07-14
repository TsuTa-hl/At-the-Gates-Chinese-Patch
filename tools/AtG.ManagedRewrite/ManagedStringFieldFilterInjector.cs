using System.Globalization;
using dnlib.DotNet;
using dnlib.DotNet.Emit;
using dnlib.DotNet.Writer;

namespace AtG.ManagedRewrite;

public sealed record StringFieldFilterSpec(
    string CallerMethodToken,
    string FieldFullName,
    string TargetMethodToken,
    int ExpectedCount);

public sealed record StringFieldFilterResult(int InjectedCount, string OutputPath);

public static class ManagedStringFieldFilterInjector
{
    public static StringFieldFilterResult Inject(
        string sourceAssemblyPath,
        string outputAssemblyPath,
        string targetAssemblyPath,
        IReadOnlyList<StringFieldFilterSpec> specs)
    {
        using var sourceModule = ModuleDefMD.Load(Path.GetFullPath(sourceAssemblyPath));
        using var targetModule = ModuleDefMD.Load(Path.GetFullPath(targetAssemblyPath));
        var importer = new Importer(sourceModule, ImporterOptions.TryToUseDefs);
        var injected = 0;

        foreach (var spec in specs)
        {
            var callerToken = ParseToken(spec.CallerMethodToken);
            var caller = sourceModule.GetTypes().SelectMany(type => type.Methods)
                .SingleOrDefault(method => method.MDToken.Raw == callerToken && method.HasBody);
            var field = sourceModule.GetTypes().SelectMany(type => type.Fields)
                .SingleOrDefault(candidate =>
                    StringComparer.Ordinal.Equals(candidate.FullName, spec.FieldFullName));
            var targetToken = ParseToken(spec.TargetMethodToken);
            var target = targetModule.GetTypes().SelectMany(type => type.Methods)
                .SingleOrDefault(method => method.MDToken.Raw == targetToken);

            var matches = caller is null || field is null || target is null ? 0 : 1;
            if (matches != spec.ExpectedCount)
                throw new InvalidDataException(
                    $"Expected {spec.ExpectedCount} string-field filter target(s), found {matches}: " +
                    $"caller={spec.CallerMethodToken}, field='{spec.FieldFullName}', target={spec.TargetMethodToken}.");
            if (matches == 0) continue;

            Validate(caller!, field!, target!);
            var importedTarget = importer.Import(target!);
            var first = caller!.Body.Instructions[0];
            var instructions = caller.Body.Instructions;
            var insertAt = instructions.IndexOf(first);
            instructions.Insert(insertAt++, Instruction.Create(OpCodes.Ldarg_0));
            instructions.Insert(insertAt++, Instruction.Create(OpCodes.Ldarg_0));
            instructions.Insert(insertAt++, Instruction.Create(OpCodes.Ldfld, field!));
            instructions.Insert(insertAt++, Instruction.Create(OpCodes.Call, importedTarget));
            instructions.Insert(insertAt, Instruction.Create(OpCodes.Stfld, field!));
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
        return new StringFieldFilterResult(injected, output);
    }

    private static void Validate(MethodDef caller, FieldDef field, MethodDef target)
    {
        if (!caller.MethodSig.HasThis)
            throw new InvalidDataException($"String-field filter caller must be an instance method: {caller.FullName}");
        if (field.IsStatic || field.FieldType.FullName != "System.String")
            throw new InvalidDataException($"String-field filter field must be an instance string: {field.FullName}");
        var signature = target.MethodSig;
        if (!target.IsStatic || signature is null || signature.Params.Count != 1 ||
            signature.Params[0].FullName != "System.String" ||
            signature.RetType.FullName != "System.String")
            throw new InvalidDataException(
                $"String-field filter target must be static string(string): {target.FullName}");
    }

    private static uint ParseToken(string token)
    {
        var text = token.StartsWith("0x", StringComparison.OrdinalIgnoreCase) ? token[2..] : token;
        return uint.Parse(text, NumberStyles.HexNumber, CultureInfo.InvariantCulture);
    }
}
