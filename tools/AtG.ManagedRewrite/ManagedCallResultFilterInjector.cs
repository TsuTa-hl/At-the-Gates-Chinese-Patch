using System.Globalization;
using dnlib.DotNet;
using dnlib.DotNet.Emit;
using dnlib.DotNet.Writer;

namespace AtG.ManagedRewrite;

/// <summary>
/// Identifies a single call whose returned string is consumed by a display
/// composition. The original call remains intact; a static string localizer is
/// inserted immediately afterwards.
/// </summary>
public sealed record CallResultFilterSpec(
    string CallerMethodToken,
    int IlOffset,
    string SourceTargetFullName,
    string TargetMethodToken,
    int ExpectedCount);

public sealed record CallResultFilterResult(int InjectedCount, string OutputPath);

/// <summary>
/// Applies a localizer only at an explicit caller and instruction offset. This
/// is suitable for UI display strings sourced from logic-sensitive properties,
/// where changing the underlying property would be unsafe.
/// </summary>
public static class ManagedCallResultFilterInjector
{
    public static CallResultFilterResult Inject(
        string sourceAssemblyPath,
        string outputAssemblyPath,
        string targetAssemblyPath,
        IReadOnlyList<CallResultFilterSpec> specs)
    {
        using var sourceModule = ModuleDefMD.Load(Path.GetFullPath(sourceAssemblyPath));
        using var targetModule = ModuleDefMD.Load(Path.GetFullPath(targetAssemblyPath));
        var importer = new Importer(sourceModule, ImporterOptions.TryToUseDefs);
        var injected = 0;

        foreach (var spec in specs)
        {
            var caller = FindSourceMethod(sourceModule, spec.CallerMethodToken);
            var target = FindTargetMethod(targetModule, spec.TargetMethodToken);
            var matches = caller is null || target is null
                ? Array.Empty<Instruction>()
                : caller.Body.Instructions
                    .Where(instruction => instruction.Offset == spec.IlOffset &&
                        instruction.OpCode.Code is Code.Call or Code.Callvirt &&
                        instruction.Operand is IMethod called &&
                        StringComparer.Ordinal.Equals(called.FullName, spec.SourceTargetFullName))
                    .ToArray();
            if (matches.Length != spec.ExpectedCount)
                throw new InvalidDataException(
                    $"Expected {spec.ExpectedCount} call-result filter target(s), found {matches.Length}: " +
                    $"caller={spec.CallerMethodToken}, offset={spec.IlOffset}, " +
                    $"source='{spec.SourceTargetFullName}', target={spec.TargetMethodToken}.");
            if (matches.Length == 0) continue;

            Validate((IMethod)matches[0].Operand, target!);
            var importedTarget = importer.Import(target!);
            foreach (var match in matches)
            {
                var index = caller!.Body.Instructions.IndexOf(match);
                caller.Body.Instructions.Insert(index + 1, Instruction.Create(OpCodes.Call, importedTarget));
                injected++;
            }
            caller!.Body.UpdateInstructionOffsets();
        }

        var output = Path.GetFullPath(outputAssemblyPath);
        Directory.CreateDirectory(Path.GetDirectoryName(output)!);
        var writerOptions = new ModuleWriterOptions(sourceModule)
        {
            Logger = DummyLogger.NoThrowInstance,
        };
        writerOptions.MetadataOptions.Flags = MetadataFlags.PreserveAll;
        sourceModule.Write(output, writerOptions);
        return new CallResultFilterResult(injected, output);
    }

    private static MethodDef? FindSourceMethod(ModuleDefMD module, string token)
    {
        var rawToken = ParseToken(token);
        return module.GetTypes().SelectMany(type => type.Methods)
            .SingleOrDefault(method => method.MDToken.Raw == rawToken && method.HasBody);
    }

    private static MethodDef? FindTargetMethod(ModuleDefMD module, string token)
    {
        var rawToken = ParseToken(token);
        return module.GetTypes().SelectMany(type => type.Methods)
            .SingleOrDefault(method => method.MDToken.Raw == rawToken);
    }

    private static void Validate(IMethod source, MethodDef target)
    {
        var sourceSignature = source.MethodSig;
        var targetSignature = target.MethodSig;
        if (sourceSignature?.RetType.FullName != "System.String")
            throw new InvalidDataException($"Call-result filter source must return string: {source.FullName}");
        if (!target.IsStatic || targetSignature is null || targetSignature.Params.Count != 1 ||
            targetSignature.Params[0].FullName != "System.String" ||
            targetSignature.RetType.FullName != "System.String")
            throw new InvalidDataException(
                $"Call-result filter target must be static string(string): {target.FullName}");
    }

    private static uint ParseToken(string token)
    {
        var text = token.StartsWith("0x", StringComparison.OrdinalIgnoreCase) ? token[2..] : token;
        return uint.Parse(text, NumberStyles.HexNumber, CultureInfo.InvariantCulture);
    }
}
