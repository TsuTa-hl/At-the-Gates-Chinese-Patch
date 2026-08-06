using System.Globalization;
using dnlib.DotNet;
using dnlib.DotNet.Emit;
using dnlib.DotNet.Writer;

namespace AtG.ManagedRewrite;

/// <summary>
/// Describes a filter for one explicit source-method argument. The filter is
/// inserted at method entry, so every use of the supplied argument within that
/// method observes the localized value.
/// </summary>
public sealed record MethodArgumentFilterSpec(
    string CallerMethodToken,
    int ParameterIndex,
    string TargetMethodToken,
    int ExpectedCount);

public sealed record MethodArgumentFilterResult(int InjectedCount, string OutputPath);

/// <summary>
/// Routes a selected method argument through a static localizer.  The localizer
/// may either return a replacement of the same type (for strings) or mutate a
/// reference argument in place (for StringBuilder).
/// </summary>
public static class ManagedMethodArgumentFilterInjector
{
    public static MethodArgumentFilterResult Inject(
        string sourceAssemblyPath,
        string outputAssemblyPath,
        string targetAssemblyPath,
        IReadOnlyList<MethodArgumentFilterSpec> specs)
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
                    $"Expected {spec.ExpectedCount} method-argument filter target(s), found {matches}: " +
                    $"caller={spec.CallerMethodToken}, parameter={spec.ParameterIndex}, " +
                    $"target={spec.TargetMethodToken}.");
            if (matches == 0) continue;

            Validate(caller!, target!, spec.ParameterIndex, out var returnsReplacement);
            var argumentSlot = spec.ParameterIndex + (caller!.MethodSig!.HasThis ? 1 : 0);
            var parameter = caller.Parameters[argumentSlot];
            var importedTarget = importer.Import(target!);
            var instructions = caller.Body.Instructions;
            var insertAt = 0;
            instructions.Insert(insertAt++, Instruction.Create(OpCodes.Ldarg, parameter));
            instructions.Insert(insertAt++, Instruction.Create(OpCodes.Call, importedTarget));
            if (returnsReplacement)
                instructions.Insert(insertAt, Instruction.Create(OpCodes.Starg, parameter));
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
        return new MethodArgumentFilterResult(injected, output);
    }

    private static void Validate(
        MethodDef caller,
        MethodDef target,
        int parameterIndex,
        out bool returnsReplacement)
    {
        var callerSignature = caller.MethodSig;
        var targetSignature = target.MethodSig;
        if (callerSignature is null || parameterIndex < 0 || parameterIndex >= callerSignature.Params.Count)
            throw new InvalidDataException(
                $"Method-argument filter parameter index is invalid: {caller.FullName}, {parameterIndex}.");
        if (!target.IsStatic || targetSignature is null || targetSignature.Params.Count != 1)
            throw new InvalidDataException(
                $"Method-argument filter target must be static with one parameter: {target.FullName}");

        var sourceType = callerSignature.Params[parameterIndex];
        if (!StringComparer.Ordinal.Equals(sourceType.FullName, targetSignature.Params[0].FullName))
            throw new InvalidDataException(
                $"Method-argument filter parameter type does not match target: " +
                $"{caller.FullName} -> {target.FullName}");

        if (targetSignature.RetType.ElementType == ElementType.Void)
        {
            returnsReplacement = false;
            return;
        }
        if (StringComparer.Ordinal.Equals(sourceType.FullName, targetSignature.RetType.FullName))
        {
            returnsReplacement = true;
            return;
        }
        throw new InvalidDataException(
            $"Method-argument filter target must return void or the original parameter type: {target.FullName}");
    }

    private static uint ParseToken(string token)
    {
        var text = token.StartsWith("0x", StringComparison.OrdinalIgnoreCase) ? token[2..] : token;
        return uint.Parse(text, NumberStyles.HexNumber, CultureInfo.InvariantCulture);
    }
}
