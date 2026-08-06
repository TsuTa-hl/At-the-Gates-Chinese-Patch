using System.Globalization;
using dnlib.DotNet;
using dnlib.DotNet.Emit;
using dnlib.DotNet.Writer;

namespace AtG.ManagedRewrite;

public sealed record StringReturnFilterSpec(
    string CallerMethodToken,
    string TargetMethodToken,
    int ExpectedCount);

public sealed record StringReturnFilterResult(int InjectedCount, string OutputPath);

/// <summary>
/// Routes the return value of selected string-producing methods through a static
/// string-to-string localizer.  This covers runtime text paths which construct a
/// <see cref="string"/> and append it directly, without passing through the
/// TextFormatter raw-text field hook.
/// </summary>
public static class ManagedStringReturnFilterInjector
{
    public static StringReturnFilterResult Inject(
        string sourceAssemblyPath,
        string outputAssemblyPath,
        string targetAssemblyPath,
        IReadOnlyList<StringReturnFilterSpec> specs)
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
            var targetToken = ParseToken(spec.TargetMethodToken);
            var target = targetModule.GetTypes().SelectMany(type => type.Methods)
                .SingleOrDefault(method => method.MDToken.Raw == targetToken);

            var matches = caller is null || target is null
                ? 0
                : caller.Body.Instructions.Count(instruction => instruction.OpCode == OpCodes.Ret);
            if (matches != spec.ExpectedCount)
                throw new InvalidDataException(
                    $"Expected {spec.ExpectedCount} string-return filter target(s), found {matches}: " +
                    $"caller={spec.CallerMethodToken}, target={spec.TargetMethodToken}.");
            if (matches == 0) continue;

            Validate(caller!, target!);
            var importedTarget = importer.Import(target!);
            var returns = caller!.Body.Instructions
                .Where(instruction => instruction.OpCode == OpCodes.Ret)
                .ToArray();
            foreach (var returnInstruction in returns)
            {
                // Rewrite the existing ret into the call, then append a new ret.
                // Any branch that targeted the original ret still targets the
                // localization call, so no return path can bypass localization.
                returnInstruction.OpCode = OpCodes.Call;
                returnInstruction.Operand = importedTarget;
                var index = caller.Body.Instructions.IndexOf(returnInstruction);
                caller.Body.Instructions.Insert(index + 1, Instruction.Create(OpCodes.Ret));
                injected++;
            }
        }

        var output = Path.GetFullPath(outputAssemblyPath);
        Directory.CreateDirectory(Path.GetDirectoryName(output)!);
        var writerOptions = new ModuleWriterOptions(sourceModule)
        {
            Logger = DummyLogger.NoThrowInstance,
        };
        writerOptions.MetadataOptions.Flags = MetadataFlags.PreserveAll;
        sourceModule.Write(output, writerOptions);
        return new StringReturnFilterResult(injected, output);
    }

    private static void Validate(MethodDef caller, MethodDef target)
    {
        if (caller.MethodSig?.RetType.FullName != "System.String")
            throw new InvalidDataException($"String-return filter caller must return string: {caller.FullName}");
        var signature = target.MethodSig;
        if (!target.IsStatic || signature is null || signature.Params.Count != 1 ||
            signature.Params[0].FullName != "System.String" ||
            signature.RetType.FullName != "System.String")
            throw new InvalidDataException(
                $"String-return filter target must be static string(string): {target.FullName}");
    }

    private static uint ParseToken(string token)
    {
        var text = token.StartsWith("0x", StringComparison.OrdinalIgnoreCase) ? token[2..] : token;
        return uint.Parse(text, NumberStyles.HexNumber, CultureInfo.InvariantCulture);
    }
}
