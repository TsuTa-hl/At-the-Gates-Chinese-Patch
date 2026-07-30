using dnlib.DotNet;
using dnlib.DotNet.Emit;
using dnlib.DotNet.Writer;

namespace AtG.ManagedRewrite;

public sealed record TileTooltipRichTextPatchResult(int PatchedMethodCount, string OutputPath);

/// <summary>
/// Replaces the one plain <c>WrappingLabel</c> used for a tile's basic-detail
/// summary with a <c>RichTextLabel</c>. The original code assembles concept
/// tags such as <c>[Supply|SUPPLY]</c>, but sends that text directly to the
/// plain label, so the tags are shown literally. The replacement reuses the
/// game's TextFormatter and preserves the original link keys and hover cards.
/// </summary>
public static class TileTooltipRichTextPatcher
{
    private const string TileTooltipTypeName = "AtTheGatesUI.ns_InGame.TileTooltip";
    private const string TileTooltipMethodName = "BuildTooltip_TileInfo";
    private const string RichTextConstructorName =
        "System.Void ElfTools.Interfaces.Controls.RichTextLabel::.ctor(System.Int32,System.Int32,Microsoft.Xna.Framework.Graphics.SpriteFont,System.Nullable`1<Microsoft.Xna.Framework.Color>,System.Nullable`1<Microsoft.Xna.Framework.Color>)";
    private const string RichTextBuildName =
        "System.Void ElfTools.Interfaces.Controls.RichTextLabel::Build(System.Collections.Generic.List`1<ElfTools.Interfaces.Controls.TextChunk>)";
    private const string TextFormatterConstructorName =
        "System.Void AtTheGatesCommon.ns_Text.TextFormatter::.ctor(System.String,System.Boolean,Microsoft.Xna.Framework.Graphics.SpriteFont,System.Nullable`1<Microsoft.Xna.Framework.Color>,System.Nullable`1<Microsoft.Xna.Framework.Color>,System.String,System.String,System.Boolean,System.Boolean)";
    private const string TextFormatterProcessName =
        "System.Collections.Generic.List`1<ElfTools.Interfaces.Controls.TextChunk> AtTheGatesCommon.ns_Text.TextFormatter::Process()";
    private const string BaseLabelFontGetterName =
        "Microsoft.Xna.Framework.Graphics.SpriteFont ElfTools.Interfaces.Controls.BaseLabel::get_Font()";
    private const string WrappingLabelConstructorName =
        "System.Void ElfTools.Interfaces.Controls.WrappingLabel::.ctor(System.String,System.Int32,System.String,Microsoft.Xna.Framework.Graphics.SpriteFont,System.String)";

    public static TileTooltipRichTextPatchResult Patch(string sourceAssemblyPath, string outputAssemblyPath)
    {
        using var module = ModuleDefMD.Load(Path.GetFullPath(sourceAssemblyPath));
        var method = RequireMethod(module);
        var patched = IsPatched(method) ? 0 : PatchMethod(module, method);
        VerifyMethod(method);
        Write(module, outputAssemblyPath);
        return new TileTooltipRichTextPatchResult(patched, Path.GetFullPath(outputAssemblyPath));
    }

    public static void Verify(string assemblyPath)
    {
        using var module = ModuleDefMD.Load(Path.GetFullPath(assemblyPath));
        VerifyMethod(RequireMethod(module));
    }

    private static int PatchMethod(ModuleDef module, MethodDef method)
    {
        var instructions = method.Body?.Instructions
            ?? throw new InvalidDataException($"{method.FullName} has no method body.");
        var richConstructor = FindMethodReference(module, RichTextConstructorName);
        var richBuild = FindMethodReference(module, RichTextBuildName);
        var formatterConstructor = FindMethodReference(module, TextFormatterConstructorName);
        var formatterProcess = FindMethodReference(module, TextFormatterProcessName);
        var fontGetter = FindMethodReference(module, BaseLabelFontGetterName);
        var wrappingIndex = FindWrappingLabelConstruction(instructions);
        var wrappingConstructor = (IMethod)instructions[wrappingIndex].Operand;
        if (!StringComparer.Ordinal.Equals(wrappingConstructor.FullName, WrappingLabelConstructorName))
            throw new InvalidDataException("Tile basic-info label constructor no longer matches the expected shape.");
        if (wrappingIndex < 6)
            throw new InvalidDataException("Tile basic-info label constructor has no complete argument sequence.");

        var start = wrappingIndex - 6;
        var sourceText = instructions[start];
        var sourceToString = instructions[start + 1];
        var widthLoad = instructions[start + 2];
        var hasBuilder = TryGetLocal(method, sourceText, out var textBuilder);
        var hasToString = sourceToString.OpCode.Code is Code.Call or Code.Callvirt &&
            sourceToString.Operand is IMethod sourceToStringMethod &&
            StringComparer.Ordinal.Equals(sourceToStringMethod.FullName,
                "System.String System.Object::ToString()");
        var tooltipWidth = widthLoad.Operand as IField;
        var hasWidth = widthLoad.OpCode.Code == Code.Ldsfld && tooltipWidth is not null;
        if (!hasBuilder || !hasToString || !hasWidth)
            throw new InvalidDataException(
                $"Tile basic-info label arguments no longer match the expected StringBuilder/width shape: " +
                $"builder={hasBuilder}; toString={hasToString} ('{sourceToString.Operand}'); width={hasWidth} ('{widthLoad.Operand}').");

        EnsureNoExternalControlFlowTarget(method, start + 1, wrappingIndex);
        var store = instructions[wrappingIndex + 1];
        if (!TryGetLocal(method, store, out var label))
            throw new InvalidDataException("Tile basic-info label is not stored in a local variable.");

        label.Type = richConstructor.DeclaringType.ToTypeSig();
        var colorType = richConstructor.MethodSig?.Params[3]
            ?? throw new InvalidDataException("RichTextLabel constructor is missing its text-color parameter.");
        var firstEmptyColor = new Local(colorType);
        var secondEmptyColor = new Local(colorType);
        method.Body!.Variables.Add(firstEmptyColor);
        method.Body.Variables.Add(secondEmptyColor);
        method.Body.InitLocals = true;

        sourceText.OpCode = OpCodes.Ldsfld;
        sourceText.Operand = tooltipWidth!;
        for (var index = 0; index < 6; index++)
            instructions.RemoveAt(start + 1);
        var constructorTail = new[]
        {
            Instruction.Create(OpCodes.Ldc_I4_0),
            Instruction.Create(OpCodes.Ldnull),
            Instruction.Create(OpCodes.Ldloca, firstEmptyColor),
            Instruction.Create(OpCodes.Initobj, colorType.ToTypeDefOrRef()),
            Instruction.Create(OpCodes.Ldloc, firstEmptyColor),
            Instruction.Create(OpCodes.Ldloca, secondEmptyColor),
            Instruction.Create(OpCodes.Initobj, colorType.ToTypeDefOrRef()),
            Instruction.Create(OpCodes.Ldloc, secondEmptyColor),
            Instruction.Create(OpCodes.Newobj, richConstructor),
        };
        for (var index = 0; index < constructorTail.Length; index++)
            instructions.Insert(start + 1 + index, constructorTail[index]);

        var storeIndex = instructions.IndexOf(store);
        var formatter = new[]
        {
            Instruction.Create(OpCodes.Ldloc, label),
            Instruction.Create(OpCodes.Ldloc, textBuilder),
            Instruction.Create(OpCodes.Callvirt, sourceToString.Operand as IMethod
                ?? throw new InvalidDataException("Tile detail StringBuilder.ToString reference was lost.")),
            Instruction.Create(OpCodes.Ldc_I4_1),
            Instruction.Create(OpCodes.Ldloc, label),
            Instruction.Create(OpCodes.Callvirt, fontGetter),
            Instruction.Create(OpCodes.Ldloca, firstEmptyColor),
            Instruction.Create(OpCodes.Initobj, colorType.ToTypeDefOrRef()),
            Instruction.Create(OpCodes.Ldloc, firstEmptyColor),
            Instruction.Create(OpCodes.Ldloca, secondEmptyColor),
            Instruction.Create(OpCodes.Initobj, colorType.ToTypeDefOrRef()),
            Instruction.Create(OpCodes.Ldloc, secondEmptyColor),
            Instruction.Create(OpCodes.Ldnull),
            Instruction.Create(OpCodes.Ldnull),
            Instruction.Create(OpCodes.Ldc_I4_0),
            Instruction.Create(OpCodes.Ldc_I4_0),
            Instruction.Create(OpCodes.Newobj, formatterConstructor),
            Instruction.Create(OpCodes.Call, formatterProcess),
            Instruction.Create(OpCodes.Callvirt, richBuild),
        };
        for (var index = 0; index < formatter.Length; index++)
            instructions.Insert(storeIndex + 1 + index, formatter[index]);

        method.Body.SimplifyBranches();
        method.Body.OptimizeBranches();
        return 1;
    }

    private static bool IsPatched(MethodDef method) => method.Body is not null &&
        method.Body.Instructions.Any(instruction => instruction.Operand is IMethod called &&
            StringComparer.Ordinal.Equals(called.FullName, RichTextBuildName)) &&
        !method.Body.Instructions.Any(instruction => instruction.Operand is IMethod called &&
            StringComparer.Ordinal.Equals(called.FullName, WrappingLabelConstructorName));

    private static void VerifyMethod(MethodDef method)
    {
        if (method.Body is null) throw new InvalidDataException($"{method.FullName} has no method body.");
        var calls = method.Body.Instructions.Select(instruction => instruction.Operand).OfType<IMethod>()
            .Select(method => method.FullName).ToArray();
        if (!calls.Contains(RichTextConstructorName, StringComparer.Ordinal) ||
            !calls.Contains(RichTextBuildName, StringComparer.Ordinal) ||
            !calls.Contains(TextFormatterConstructorName, StringComparer.Ordinal) ||
            !calls.Contains(TextFormatterProcessName, StringComparer.Ordinal) ||
            calls.Contains(WrappingLabelConstructorName, StringComparer.Ordinal))
            throw new InvalidDataException(
                "Tile basic-info rich-text patch is incomplete: expected RichTextLabel + TextFormatter and no plain WrappingLabel constructor.");
    }

    private static int FindWrappingLabelConstruction(IList<Instruction> instructions)
    {
        var matches = instructions
            .Select((instruction, index) => (instruction, index))
            .Where(item => item.instruction.OpCode.Code == Code.Newobj &&
                item.instruction.Operand is IMethod called &&
                StringComparer.Ordinal.Equals(called.FullName, WrappingLabelConstructorName))
            .Select(item => item.index)
            .ToArray();
        return matches.Length == 1
            ? matches[0]
            : throw new InvalidDataException(
                $"Expected one plain tile basic-info WrappingLabel construction, found {matches.Length}.");
    }

    private static void EnsureNoExternalControlFlowTarget(MethodDef method, int firstRemoved, int lastRemoved)
    {
        var removed = method.Body!.Instructions.Skip(firstRemoved).Take(lastRemoved - firstRemoved + 1)
            .ToHashSet();
        foreach (var instruction in method.Body.Instructions)
        {
            if (instruction.Operand is Instruction target && removed.Contains(target))
                throw new InvalidDataException("Tile basic-info patch would remove a branch target.");
            if (instruction.Operand is IList<Instruction> targets && targets.Any(removed.Contains))
                throw new InvalidDataException("Tile basic-info patch would remove a switch target.");
        }
    }

    private static bool TryGetLocal(MethodDef method, Instruction instruction, out Local local)
    {
        local = null!;
        if (instruction.Operand is Local explicitLocal)
        {
            local = explicitLocal;
            return instruction.OpCode.Code is Code.Ldloc or Code.Ldloc_S or Code.Stloc or Code.Stloc_S;
        }

        var index = instruction.OpCode.Code switch
        {
            Code.Ldloc_0 or Code.Stloc_0 => 0,
            Code.Ldloc_1 or Code.Stloc_1 => 1,
            Code.Ldloc_2 or Code.Stloc_2 => 2,
            Code.Ldloc_3 or Code.Stloc_3 => 3,
            _ => -1,
        };
        if (index < 0 || method.Body is null || index >= method.Body.Variables.Count)
            return false;
        local = method.Body.Variables[index];
        return true;
    }

    private static MethodDef RequireMethod(ModuleDef module)
    {
        var type = module.GetTypes().SingleOrDefault(candidate => candidate.FullName == TileTooltipTypeName)
            ?? throw new InvalidDataException($"{TileTooltipTypeName} was not found.");
        return type.Methods.SingleOrDefault(candidate =>
                   candidate.Name == TileTooltipMethodName && candidate.HasBody)
               ?? throw new InvalidDataException(
                   $"{TileTooltipTypeName}::{TileTooltipMethodName} was not found.");
    }

    private static IMethod FindMethodReference(ModuleDef module, string fullName) =>
        module.GetTypes().SelectMany(type => type.Methods)
            .Where(method => method.HasBody)
            .SelectMany(method => method.Body!.Instructions)
            .Select(instruction => instruction.Operand)
            .OfType<IMethod>()
            .FirstOrDefault(method => StringComparer.Ordinal.Equals(method.FullName, fullName))
        ?? throw new InvalidDataException($"Required method reference was not found: {fullName}");

    private static void Write(ModuleDef module, string outputAssemblyPath)
    {
        var output = Path.GetFullPath(outputAssemblyPath);
        Directory.CreateDirectory(Path.GetDirectoryName(output)!);
        var options = new ModuleWriterOptions(module) { Logger = DummyLogger.NoThrowInstance };
        options.MetadataOptions.Flags = MetadataFlags.PreserveAll;
        module.Write(output, options);
    }
}
