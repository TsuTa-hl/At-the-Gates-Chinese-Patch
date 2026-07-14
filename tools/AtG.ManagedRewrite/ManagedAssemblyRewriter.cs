using dnlib.DotNet;
using dnlib.DotNet.Emit;
using dnlib.DotNet.Writer;

namespace AtG.ManagedRewrite;

public static class ManagedAssemblyRewriter
{
    public static RewriteResult Rewrite(
        string sourcePath,
        string outputPath,
        IReadOnlyCollection<StringRewriteSpec> specs)
    {
        sourcePath = Path.GetFullPath(sourcePath);
        outputPath = Path.GetFullPath(outputPath);
        using var module = ModuleDefMD.Load(sourcePath);
        var rewritten = 0;

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

        Directory.CreateDirectory(Path.GetDirectoryName(outputPath)!);
        var writerOptions = new ModuleWriterOptions(module)
        {
            Logger = DummyLogger.NoThrowInstance,
        };
        writerOptions.MetadataOptions.Flags = MetadataFlags.PreserveAll;
        module.Write(outputPath, writerOptions);
        return new RewriteResult(rewritten, outputPath);
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
