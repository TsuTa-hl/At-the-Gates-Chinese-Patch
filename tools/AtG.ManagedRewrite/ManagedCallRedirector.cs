using System.Globalization;
using dnlib.DotNet;
using dnlib.DotNet.Emit;
using dnlib.DotNet.Writer;

namespace AtG.ManagedRewrite;

public sealed record CallRedirectSpec(
    string SourceTargetFullName,
    string TargetMethodToken,
    int ExpectedCount,
    string? CallerMethodToken = null,
    int? IlOffset = null);

public sealed record CallRedirectResult(int RedirectedCount, string OutputPath);

public static class ManagedCallRedirector
{
    public static CallRedirectResult Redirect(
        string sourceAssemblyPath,
        string outputAssemblyPath,
        string targetAssemblyPath,
        IReadOnlyList<CallRedirectSpec> specs)
    {
        using var sourceModule = ModuleDefMD.Load(Path.GetFullPath(sourceAssemblyPath));
        using var targetModule = ModuleDefMD.Load(Path.GetFullPath(targetAssemblyPath));
        var importer = new Importer(sourceModule, ImporterOptions.TryToUseDefs);
        var redirected = 0;

        foreach (var spec in specs)
        {
            var targetToken = ParseToken(spec.TargetMethodToken);
            var targetMethod = targetModule.GetTypes()
                .SelectMany(type => type.Methods)
                .SingleOrDefault(method => method.MDToken.Raw == targetToken)
                ?? throw new InvalidDataException(
                    $"Target method token {spec.TargetMethodToken} was not found in '{targetAssemblyPath}'.");
            if (!targetMethod.IsStatic)
                throw new InvalidDataException($"Redirect target must be static: {targetMethod.FullName}");
            var importedTarget = importer.Import(targetMethod);
            var callerToken = spec.CallerMethodToken is null ? (uint?)null : ParseToken(spec.CallerMethodToken);
            var matches = sourceModule.GetTypes()
                .SelectMany(type => type.Methods)
                .Where(method => method.HasBody &&
                    (callerToken is null || method.MDToken.Raw == callerToken.Value))
                .SelectMany(method => method.Body.Instructions)
                .Where(instruction =>
                    (spec.IlOffset is null || instruction.Offset == spec.IlOffset.Value) &&
                    instruction.OpCode.Code is Code.Call or Code.Callvirt &&
                    instruction.Operand is IMethod called &&
                    StringComparer.Ordinal.Equals(called.FullName, spec.SourceTargetFullName))
                .ToArray();
            if (matches.Length != spec.ExpectedCount)
                throw new InvalidDataException(
                    $"Expected {spec.ExpectedCount} calls to '{spec.SourceTargetFullName}', found {matches.Length}.");

            foreach (var instruction in matches)
            {
                ValidateStackCompatibility((IMethod)instruction.Operand, targetMethod);
                instruction.OpCode = OpCodes.Call;
                instruction.Operand = importedTarget;
                redirected++;
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
        return new CallRedirectResult(redirected, output);
    }

    private static void ValidateStackCompatibility(IMethod source, MethodDef target)
    {
        var sourceSignature = source.MethodSig
            ?? throw new InvalidDataException($"Source call has no method signature: {source.FullName}");
        var targetSignature = target.MethodSig
            ?? throw new InvalidDataException($"Target call has no method signature: {target.FullName}");
        var sourceInputCount = sourceSignature.Params.Count + (sourceSignature.HasThis ? 1 : 0);
        var targetInputCount = targetSignature.Params.Count + (targetSignature.HasThis ? 1 : 0);
        var sourceReturnType = ResolveReturnTypeFullName(source, sourceSignature.RetType);
        if (sourceInputCount != targetInputCount ||
            !StringComparer.Ordinal.Equals(sourceReturnType, targetSignature.RetType.FullName))
            throw new InvalidDataException(
                $"Redirect signatures are not stack compatible: '{source.FullName}' -> '{target.FullName}'. " +
                $"inputs={sourceInputCount}/{targetInputCount}, " +
                $"returns='{sourceReturnType}'/'{targetSignature.RetType.FullName}', " +
                $"source-has-this={sourceSignature.HasThis}, target-has-this={targetSignature.HasThis}.");
    }

    private static string ResolveReturnTypeFullName(IMethod source, TypeSig returnType)
    {
        if (source is MethodSpec methodSpec &&
            returnType is GenericMVar methodVariable &&
            methodSpec.GenericInstMethodSig is { } genericSignature &&
            methodVariable.Number < genericSignature.GenericArguments.Count)
            return genericSignature.GenericArguments[(int)methodVariable.Number].FullName;
        return returnType.FullName;
    }

    private static uint ParseToken(string token)
    {
        var text = token.StartsWith("0x", StringComparison.OrdinalIgnoreCase) ? token[2..] : token;
        return uint.Parse(text, NumberStyles.HexNumber, CultureInfo.InvariantCulture);
    }
}
