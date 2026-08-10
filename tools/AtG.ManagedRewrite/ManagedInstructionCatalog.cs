using dnlib.DotNet;
using dnlib.DotNet.Emit;

namespace AtG.ManagedRewrite;

/// <summary>
/// Exports method instructions as data for source-catalog investigation. This
/// deliberately avoids loading the game and preserves original IL offsets,
/// which are the locators used by managed rewrite maps.
/// </summary>
public static class ManagedInstructionCatalog
{
    public static IReadOnlyList<ManagedInstructionEntry> Read(string assemblyPath,
        string? methodToken = null)
    {
        using var module = ModuleDefMD.Load(Path.GetFullPath(assemblyPath));
        return module.GetTypes()
            .SelectMany(type => type.Methods
                .Where(method => method.HasBody && (methodToken is null ||
                    string.Equals($"0x{method.MDToken.Raw:x8}", methodToken,
                        StringComparison.OrdinalIgnoreCase)))
                .SelectMany(method => method.Body.Instructions.Select(instruction =>
                    new ManagedInstructionEntry(
                        type.FullName,
                        method.Name,
                        $"0x{method.MDToken.Raw:x8}",
                        checked((int)instruction.Offset),
                        instruction.OpCode.Name,
                        FormatOperand(instruction.Operand))))
            )
            .ToArray();
    }

    private static string? FormatOperand(object? operand) => operand switch
    {
        null => null,
        string value => value,
        IMethod method => method.FullName,
        IField field => field.FullName,
        ITypeDefOrRef type => type.FullName,
        _ => operand.ToString(),
    };
}

public sealed record ManagedInstructionEntry(
    string TypeFullName,
    string MethodName,
    string MethodToken,
    int IlOffset,
    string OpCode,
    string? Operand);
