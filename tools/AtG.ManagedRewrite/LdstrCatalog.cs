using dnlib.DotNet;
using dnlib.DotNet.Emit;

namespace AtG.ManagedRewrite;

public static class LdstrCatalog
{
    public static IReadOnlyList<LdstrEntry> Read(string assemblyPath)
    {
        using var module = ModuleDefMD.Load(Path.GetFullPath(assemblyPath));
        var entries = new List<LdstrEntry>();
        foreach (var type in module.GetTypes())
        foreach (var method in type.Methods)
        {
            if (method.Body is null) continue;
            foreach (var instruction in method.Body.Instructions)
            {
                if (instruction.OpCode != OpCodes.Ldstr || instruction.Operand is not string value) continue;
                entries.Add(new LdstrEntry(
                    $"0x{method.MDToken.Raw:x8}",
                    checked((int)instruction.Offset),
                    type.FullName,
                    method.Name,
                    value));
            }
        }
        return entries;
    }
}
