using dnlib.DotNet;
using dnlib.DotNet.Emit;
using dnlib.DotNet.Writer;

namespace AtG.ManagedRewrite;

public static class ManagedAssemblyRewriter
{
    private const string HumanReadableModDynamicPercentOperation =
        "HumanReadableModDynamicPercent";

    public static RewriteResult Rewrite(
        string sourcePath,
        string outputPath,
        IReadOnlyCollection<StringRewriteSpec> specs)
    {
        sourcePath = Path.GetFullPath(sourcePath);
        outputPath = Path.GetFullPath(outputPath);
        using var module = ModuleDefMD.Load(sourcePath);
        var rewritten = 0;

        // Resolve and rewrite every ldstr against the original method offsets before
        // applying any structural operation.  A structural rewrite can move later
        // instructions, while map entries intentionally address the original DLL.
        foreach (var spec in specs)
        {
            var token = ParseMethodToken(spec.MethodToken);
            if (module.ResolveToken(token) is not MethodDef method || method.Body is null)
                throw new InvalidOperationException($"Method token was not found or has no body: {spec.MethodToken}.");

            var instruction = method.Body.Instructions.FirstOrDefault(x =>
                x.OpCode == OpCodes.Ldstr && x.Offset == spec.IlOffset);
            if (instruction is null)
                throw new InvalidOperationException(
                    $"No ldstr at {spec.MethodToken} IL_{spec.IlOffset:x4}.");
            if (!StringComparer.Ordinal.Equals(instruction.Operand as string, spec.Original))
                throw new InvalidOperationException(
                    $"Original mismatch at {spec.MethodToken} IL_{spec.IlOffset:x4}.");

            instruction.Operand = spec.Translation;
            rewritten++;
        }

        foreach (var spec in specs.Where(spec =>
                     StringComparer.Ordinal.Equals(spec.Operation,
                         HumanReadableModDynamicPercentOperation)))
        {
            ApplyHumanReadableModDynamicPercent(module, spec);
        }

        Directory.CreateDirectory(Path.GetDirectoryName(outputPath)!);
        var writerOptions = new ModuleWriterOptions(module)
        {
            Logger = DummyLogger.NoThrowInstance,
        };
        writerOptions.MetadataOptions.Flags = MetadataFlags.PreserveAll;
        module.Write(outputPath, writerOptions);
        return new RewriteResult(rewritten, outputPath);
    }

    private static void ApplyHumanReadableModDynamicPercent(
        ModuleDefMD module,
        StringRewriteSpec spec)
    {
        var token = ParseMethodToken(spec.MethodToken);
        if (module.ResolveToken(token) is not MethodDef method || method.Body is null)
            throw new InvalidOperationException(
                $"Method token was not found or has no body: {spec.MethodToken}.");

        // The original branch formats an integer percentage as a decimal multiplier:
        // arg0 / 100, optional decimal digits, then `x`.  The localization contract
        // is percentage-first, so retain the original integer and append `%` instead.
        var instructions = method.Body.Instructions;
        var suffix = instructions.FirstOrDefault(instruction =>
            instruction.OpCode == OpCodes.Ldstr && instruction.Offset == spec.IlOffset);
        if (suffix is null || !StringComparer.Ordinal.Equals(suffix.Operand as string, "%"))
            throw new InvalidOperationException(
                $"Dynamic percent suffix at {spec.MethodToken} IL_{spec.IlOffset:x4} was not rewritten to '%'.");

        var oldConcat = instructions.FirstOrDefault(instruction =>
            instruction.OpCode == OpCodes.Call && instruction.Offset == 263);
        if (oldConcat?.Operand is not IMethod concatObjectCall)
            throw new InvalidOperationException(
                $"HumanReadableMod object concat call was not found at IL_0107 in {spec.MethodToken}.");

        var firstInstruction = instructions.FirstOrDefault(instruction => instruction.Offset >= 253);
        var beforeSuffix = instructions.IndexOf(suffix);
        if (firstInstruction is null || beforeSuffix < 0)
            throw new InvalidOperationException(
                $"HumanReadableMod dynamic branch boundaries were not found for {spec.MethodToken}.");

        var firstDynamicIndex = instructions.IndexOf(firstInstruction);
        if (firstDynamicIndex >= beforeSuffix)
            throw new InvalidOperationException(
                $"HumanReadableMod dynamic branch ordering is invalid for {spec.MethodToken}.");

        // Drop only the divide/remainder/decimal-digit instructions.  The existing
        // suffix (`ldarg.1`, `%`, concat, starg, stloc, branch) is retained so its
        // exact method control-flow remains stable.
        var removedCount = beforeSuffix - firstDynamicIndex;
        for (var index = 0; index < removedCount; index++)
            instructions.RemoveAt(firstDynamicIndex);
        var replacement = new[]
        {
            Instruction.Create(OpCodes.Ldarg_1),
            Instruction.Create(OpCodes.Ldarg_0),
            Instruction.Create(OpCodes.Box, module.CorLibTypes.Int32.ToTypeDefOrRef()),
            Instruction.Create(OpCodes.Call, concatObjectCall),
            Instruction.Create(OpCodes.Starg, method.Parameters[1]),
            // The original suffix begins with ldarg.1 before concatenating `x`.
            // It is inside the removed decimal-formatting range, so restore the
            // receiver explicitly before the retained `%` suffix.
            Instruction.Create(OpCodes.Ldarg_1),
        };
        for (var index = 0; index < replacement.Length; index++)
            instructions.Insert(firstDynamicIndex + index, replacement[index]);

        var suffixIndex = instructions.IndexOf(suffix);
        if (suffixIndex <= firstDynamicIndex ||
            instructions[suffixIndex - 1].OpCode != OpCodes.Ldarg_1)
        {
            throw new InvalidOperationException(
                $"HumanReadableMod dynamic percent suffix lost its text receiver at " +
                $"{spec.MethodToken} IL_{spec.IlOffset:x4}.");
        }

        Console.WriteLine(
            $"Applied {HumanReadableModDynamicPercentOperation} " +
            $"({spec.MethodToken} IL_{spec.IlOffset:x4}).");
    }

    private static uint ParseMethodToken(string value)
    {
        value = value.Trim();
        var token = value.StartsWith("0x", StringComparison.OrdinalIgnoreCase)
            ? Convert.ToUInt32(value[2..], 16)
            : Convert.ToUInt32(value);
        if ((token & 0xff000000) != 0x06000000)
            throw new InvalidOperationException($"Not a MethodDef token: {value}.");
        return token;
    }
}
