using System.Globalization;
using dnlib.DotNet;
using dnlib.DotNet.Emit;
using dnlib.DotNet.Writer;

namespace AtG.ManagedRewrite;

public sealed record ReturnValueRegistrationSpec(
    string CallerMethodToken,
    string TargetMethodToken,
    string Name,
    float Size,
    bool Bold,
    int ExpectedReturnCount);

public sealed record ReturnValueRegistrationResult(int RegisteredCount, string OutputPath);

public static class ManagedReturnValueRegistrar
{
    public static ReturnValueRegistrationResult Register(
        string sourceAssemblyPath,
        string outputAssemblyPath,
        string targetAssemblyPath,
        IReadOnlyList<ReturnValueRegistrationSpec> specs)
    {
        using var sourceModule = ModuleDefMD.Load(Path.GetFullPath(sourceAssemblyPath));
        using var targetModule = ModuleDefMD.Load(Path.GetFullPath(targetAssemblyPath));
        var importer = new Importer(sourceModule, ImporterOptions.TryToUseDefs);
        var registered = 0;

        foreach (var spec in specs)
        {
            var callerToken = ParseToken(spec.CallerMethodToken);
            var targetToken = ParseToken(spec.TargetMethodToken);
            var caller = sourceModule.GetTypes().SelectMany(type => type.Methods)
                .SingleOrDefault(method => method.MDToken.Raw == callerToken)
                ?? throw new InvalidDataException(
                    $"Caller method token {spec.CallerMethodToken} was not found in '{sourceAssemblyPath}'.");
            var target = targetModule.GetTypes().SelectMany(type => type.Methods)
                .SingleOrDefault(method => method.MDToken.Raw == targetToken)
                ?? throw new InvalidDataException(
                    $"Target method token {spec.TargetMethodToken} was not found in '{targetAssemblyPath}'.");
            ValidateSignatures(caller, target);

            var returns = caller.Body.Instructions
                .Where(instruction => instruction.OpCode.Code == Code.Ret)
                .ToArray();
            if (returns.Length != spec.ExpectedReturnCount)
                throw new InvalidDataException(
                    $"Expected {spec.ExpectedReturnCount} return points in '{caller.FullName}', found {returns.Length}.");

            var importedTarget = importer.Import(target);
            foreach (var ret in returns)
            {
                var index = caller.Body.Instructions.IndexOf(ret);
                caller.Body.Instructions.Insert(index++, Instruction.Create(OpCodes.Ldstr, spec.Name));
                caller.Body.Instructions.Insert(index++, Instruction.Create(OpCodes.Ldc_R4, spec.Size));
                caller.Body.Instructions.Insert(index++, Instruction.Create(spec.Bold ? OpCodes.Ldc_I4_1 : OpCodes.Ldc_I4_0));
                caller.Body.Instructions.Insert(index, Instruction.Create(OpCodes.Call, importedTarget));
                registered++;
            }
            caller.Body.UpdateInstructionOffsets();
        }

        var output = Path.GetFullPath(outputAssemblyPath);
        Directory.CreateDirectory(Path.GetDirectoryName(output)!);
        var writerOptions = new ModuleWriterOptions(sourceModule)
        {
            Logger = DummyLogger.NoThrowInstance,
        };
        writerOptions.MetadataOptions.Flags = MetadataFlags.PreserveAll;
        sourceModule.Write(output, writerOptions);
        return new ReturnValueRegistrationResult(registered, output);
    }

    private static void ValidateSignatures(MethodDef caller, MethodDef target)
    {
        if (!caller.HasBody || caller.MethodSig is null || caller.MethodSig.RetType.ElementType == ElementType.Void)
            throw new InvalidDataException($"Caller must return a value: {caller.FullName}");
        if (!target.IsStatic || target.MethodSig is null || target.MethodSig.Params.Count != 4)
            throw new InvalidDataException($"Registration target must be a four-argument static method: {target.FullName}");
        if (!StringComparer.Ordinal.Equals(caller.MethodSig.RetType.FullName, target.MethodSig.Params[0].FullName) ||
            !StringComparer.Ordinal.Equals(caller.MethodSig.RetType.FullName, target.MethodSig.RetType.FullName) ||
            target.MethodSig.Params[1].ElementType != ElementType.String ||
            target.MethodSig.Params[2].ElementType != ElementType.R4 ||
            target.MethodSig.Params[3].ElementType != ElementType.Boolean)
            throw new InvalidDataException(
                $"Registration target is not stack compatible with '{caller.FullName}': {target.FullName}");
    }

    private static uint ParseToken(string token)
    {
        var text = token.StartsWith("0x", StringComparison.OrdinalIgnoreCase) ? token[2..] : token;
        return uint.Parse(text, NumberStyles.HexNumber, CultureInfo.InvariantCulture);
    }
}
