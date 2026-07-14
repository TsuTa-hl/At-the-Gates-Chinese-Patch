using dnlib.DotNet;
using dnlib.DotNet.Emit;

namespace AtG.ManagedRewrite;

public sealed record ManagedCallEntry(
    string CallerType,
    string CallerMethod,
    string CallerToken,
    int IlOffset,
    string OpCode,
    string TargetFullName);

public static class ManagedCallCatalog
{
    public static IReadOnlyList<ManagedCallEntry> Read(string assemblyPath)
    {
        using var module = ModuleDefMD.Load(Path.GetFullPath(assemblyPath));
        return module.GetTypes()
            .SelectMany(type => type.Methods
                .Where(method => method.HasBody)
                .SelectMany(method => method.Body.Instructions
                    .Where(instruction =>
                        instruction.OpCode.Code is Code.Call or Code.Callvirt &&
                        instruction.Operand is IMethod)
                    .Select(instruction => new ManagedCallEntry(
                        type.FullName,
                        method.Name,
                        $"0x{method.MDToken.Raw:X8}",
                        checked((int)instruction.Offset),
                        instruction.OpCode.Name,
                        ((IMethod)instruction.Operand).FullName))))
            .ToArray();
    }
}

public sealed record ManagedMethodEntry(
    string DeclaringType,
    string Name,
    string MetadataToken,
    string FullName);

public static class ManagedMethodCatalog
{
    public static IReadOnlyList<ManagedMethodEntry> Read(string assemblyPath)
    {
        using var module = ModuleDefMD.Load(Path.GetFullPath(assemblyPath));
        return module.GetTypes()
            .SelectMany(type => type.Methods.Select(method => new ManagedMethodEntry(
                type.FullName,
                method.Name,
                $"0x{method.MDToken.Raw:X8}",
                method.FullName)))
            .ToArray();
    }
}
