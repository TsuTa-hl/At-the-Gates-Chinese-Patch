using dnlib.DotNet;
using dnlib.DotNet.Emit;

namespace AtG.ManagedRewrite;

/// <summary>
/// Reads the registration table built by <c>ns_UI.Concepts::.cctor</c> without
/// loading the game. Concept descriptions are not ordinary XML text: the game
/// creates them from literal and concatenated operands while its static
/// constructor runs. Keeping this small, deterministic IL evaluator here gives
/// the localization build one authoritative inventory for that display path.
/// </summary>
public static class ConceptTooltipCatalog
{
    // A handful of registrations load their concept key through a static field
    // initialized outside the constructor's linear execution path. dnlib
    // therefore cannot recover the field value while evaluating .cctor alone.
    // Keep the binding at the registration call site, not as a text match: the
    // offset is stable source metadata and lets the catalog retain a complete
    // one-to-one inventory of the registered tooltip entry points.
    private static readonly IReadOnlyDictionary<string, string> RegistrationKeyAliases =
        new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["IL_0578"] = "FOOD",
            ["IL_05fa"] = "BANDIT",
            ["IL_0ba4"] = "ATTACK",
            ["IL_0c50"] = "DEFEND",
            ["IL_0cbd"] = "MORALE",
            ["IL_0d00"] = "RETREAT",
            ["IL_1006"] = "FORAGE",
            ["IL_10a3"] = "ENCAMP",
            ["IL_114f"] = "SIEGE",
            ["IL_11a2"] = "PACKED",
        };

    public static ConceptTooltipCatalogResult Read(string assemblyPath,
        string conceptsTypeFullName = "AtTheGatesCommon.ns_UI.Concepts")
    {
        var fullAssemblyPath = Path.GetFullPath(assemblyPath);
        using var module = ModuleDefMD.Load(fullAssemblyPath);
        var concepts = module.Find(conceptsTypeFullName, isReflectionName: false)
            ?? throw new InvalidDataException(
                $"Concept type '{conceptsTypeFullName}' was not found in '{fullAssemblyPath}'.");
        var initializer = concepts.FindStaticConstructor()
            ?? throw new InvalidDataException(
                $"Concept type '{conceptsTypeFullName}' has no static constructor.");
        if (initializer.Body is null)
            throw new InvalidDataException(
                $"Concept type '{conceptsTypeFullName}' static constructor has no method body.");

        var evaluator = new Evaluator(concepts, initializer);
        return evaluator.Evaluate(fullAssemblyPath);
    }

    private sealed class Evaluator(TypeDef concepts, MethodDef initializer)
    {
        private readonly TypeDef _concepts = concepts;
        private readonly MethodDef _initializer = initializer;
        private readonly Dictionary<string, Value> _fields = new(StringComparer.Ordinal);
        private readonly Dictionary<int, Value> _locals = new();
        private readonly List<Value> _stack = [];
        private readonly List<ConceptTooltipEntry> _entries = [];

        public ConceptTooltipCatalogResult Evaluate(string assemblyPath)
        {
            foreach (var instruction in _initializer.Body!.Instructions)
                Execute(instruction);

            if (_entries.Count == 0)
                throw new InvalidDataException(
                    $"No Concepts.c registrations were discovered in 0x{_initializer.MDToken.Raw:x8}.");

            return new ConceptTooltipCatalogResult(
                assemblyPath,
                _concepts.FullName,
                $"0x{_initializer.MDToken.Raw:x8}",
                _entries.OrderBy(entry => entry.Key, StringComparer.Ordinal).ToArray());
        }

        private void Execute(Instruction instruction)
        {
            switch (instruction.OpCode.Code)
            {
                case Code.Nop:
                case Code.Break:
                    return;
                case Code.Ldstr:
                    Push(Value.Text((string)instruction.Operand!, $"IL_{instruction.Offset:x4}"));
                    return;
                case Code.Ldnull:
                    Push(Value.Unknown("null"));
                    return;
                case Code.Ldc_I4_M1: Push(Value.Integer(-1)); return;
                case Code.Ldc_I4_0: Push(Value.Integer(0)); return;
                case Code.Ldc_I4_1: Push(Value.Integer(1)); return;
                case Code.Ldc_I4_2: Push(Value.Integer(2)); return;
                case Code.Ldc_I4_3: Push(Value.Integer(3)); return;
                case Code.Ldc_I4_4: Push(Value.Integer(4)); return;
                case Code.Ldc_I4_5: Push(Value.Integer(5)); return;
                case Code.Ldc_I4_6: Push(Value.Integer(6)); return;
                case Code.Ldc_I4_7: Push(Value.Integer(7)); return;
                case Code.Ldc_I4_8: Push(Value.Integer(8)); return;
                case Code.Ldc_I4_S: Push(Value.Integer((sbyte)instruction.Operand!)); return;
                case Code.Ldc_I4: Push(Value.Integer((int)instruction.Operand!)); return;
                case Code.Dup:
                    Push(Peek());
                    return;
                case Code.Pop:
                    Pop();
                    return;
                case Code.Newarr:
                    var length = Pop();
                    Push(Value.Array(length.IntegerValue));
                    return;
                case Code.Newobj:
                    var constructor = (IMethod)instruction.Operand!;
                    var constructorParameterCount = constructor.MethodSig?.Params.Count
                        ?? throw new InvalidDataException($"Missing constructor signature for '{constructor}'.");
                    PopArguments(constructorParameterCount);
                    Push(Value.Unknown($"new:{constructor.DeclaringType?.FullName ?? constructor.FullName}"));
                    return;
                case Code.Stelem_Ref:
                    var element = Pop();
                    var index = Pop();
                    var array = Pop();
                    Push(array.WithElement(index.IntegerValue, element));
                    return;
                case Code.Ldsfld:
                case Code.Ldsflda:
                    var referencedField = (IField)instruction.Operand!;
                    Push(_fields.TryGetValue(FieldIdentity(referencedField), out var field)
                        ? field
                        : IsFontIcon(referencedField)
                            ? Value.Dynamic($"font-icon:{referencedField.Name}")
                            : Value.Unknown($"field:{FieldIdentity(referencedField)}"));
                    return;
                case Code.Stsfld:
                    _fields[FieldIdentity((IField)instruction.Operand!)] = Pop();
                    return;
                case Code.Ldloc_0: Push(Local(0)); return;
                case Code.Ldloc_1: Push(Local(1)); return;
                case Code.Ldloc_2: Push(Local(2)); return;
                case Code.Ldloc_3: Push(Local(3)); return;
                case Code.Ldloc:
                case Code.Ldloc_S:
                    Push(Local(LocalIndex(instruction.Operand!)));
                    return;
                case Code.Stloc_0: _locals[0] = Pop(); return;
                case Code.Stloc_1: _locals[1] = Pop(); return;
                case Code.Stloc_2: _locals[2] = Pop(); return;
                case Code.Stloc_3: _locals[3] = Pop(); return;
                case Code.Stloc:
                case Code.Stloc_S:
                    _locals[LocalIndex(instruction.Operand!)] = Pop();
                    return;
                case Code.Box:
                case Code.Castclass:
                case Code.Isinst:
                case Code.Unbox_Any:
                    // These are type-only operations for the registration table.
                    return;
                case Code.Call:
                case Code.Callvirt:
                    Invoke((IMethod)instruction.Operand!, instruction);
                    return;
                case Code.Ret:
                    return;
                default:
                    throw Unsupported(instruction);
            }
        }

        private void Invoke(IMethod method, Instruction instruction)
        {
            var parameterCount = method.MethodSig?.Params.Count
                ?? throw new InvalidDataException($"Missing signature for '{method}'.");
            var arguments = PopArguments(parameterCount);
            var declaringType = method.DeclaringType?.FullName ?? "";
            var instance = method.MethodSig?.HasThis == true ? Pop() : null;

            if (declaringType == "System.String" && method.Name == "Concat")
            {
                Push(Value.Concat(arguments));
                return;
            }

            if (declaringType == "System.String" && method.Name == "Format")
            {
                Push(Value.Format(arguments));
                return;
            }

            // The SOCIAL concept joins two localized literals around one
            // FontIcons glyph. It is a display-only symbol, not English text,
            // so preserve it as a complete dynamic operand rather than losing
            // the registration through an unknown Char.ToString call.
            if (declaringType == "System.Char" && method.Name == "ToString" &&
                instance is not null && instance.IsDynamic)
            {
                Push(instance);
                return;
            }

            if (IsConceptRegistration(method))
            {
                if (arguments.Length != 3)
                    throw new InvalidDataException(
                        $"Unexpected Concepts.c argument count {arguments.Length} at IL_{instruction.Offset:x4}.");
                var key = arguments[0];
                var label = arguments[1];
                var description = arguments[2];
                var registrationOffset = $"IL_{instruction.Offset:x4}";
                _entries.Add(new ConceptTooltipEntry(
                    RegistrationKeyAliases.TryGetValue(registrationOffset, out var knownKey)
                        ? knownKey
                        : InferConceptKey(key, instruction.Offset),
                    label.StringValue,
                    description.StringValue,
                    registrationOffset,
                    DescribeComposition(description),
                    key.IsComplete && label.IsComplete && description.IsComplete,
                    description.IsTextKeyReference,
                    description.Parts));
                return;
            }

            if (method.MethodSig?.RetType.ElementType == ElementType.Void)
                return;

            // Concept getters are used only while descriptions are being joined.
            // Preserve a symbolic operand so an unsupported conversion is reported
            // with the affected key instead of silently omitting it.
            Push(Value.Unknown($"call:{method.FullName}"));
        }

        private static bool IsConceptRegistration(IMethod method) =>
            method.Name == "c" &&
            string.Equals(method.DeclaringType?.FullName,
                "AtTheGatesCommon.ns_UI.Concepts", StringComparison.Ordinal);

        private static bool IsFontIcon(IField field) =>
            string.Equals(field.DeclaringType?.FullName,
                "AtTheGatesCommon.ns_UI.FontIcons", StringComparison.Ordinal);

        private static string InferConceptKey(Value value, uint offset)
        {
            if (!string.IsNullOrWhiteSpace(value.StringValue) &&
                value.StringValue.StartsWith("field:", StringComparison.Ordinal))
            {
                var candidate = value.StringValue[(value.StringValue.LastIndexOf("::", StringComparison.Ordinal) + 2)..];
                if (candidate.Length > 0 && candidate.All(character =>
                        char.IsUpper(character) || char.IsDigit(character) || character is '-' or '_'))
                    return candidate.Replace('_', '-');
            }
            return value.StringValue ?? $"<unknown-key@IL_{offset:x4}>";
        }

        private static string DescribeComposition(Value description)
        {
            if (description.IsTextKeyReference) return "XmlTextKey";
            return description.Parts.Count switch
            {
                0 => "Unknown",
                1 => "Literal",
                _ => "Concat",
            };
        }

        private Value[] PopArguments(int count)
        {
            var values = new Value[count];
            for (var index = count - 1; index >= 0; index--)
                values[index] = Pop();
            return values;
        }

        private Value Local(int index) => _locals.TryGetValue(index, out var value)
            ? value : Value.Unknown($"local:{index}");

        private Value Peek() => _stack.Count == 0
            ? throw new InvalidDataException("Concept registration evaluator stack underflow.")
            : _stack[^1];

        private Value Pop()
        {
            var value = Peek();
            _stack.RemoveAt(_stack.Count - 1);
            return value;
        }

        private void Push(Value value) => _stack.Add(value);

        private InvalidDataException Unsupported(Instruction instruction) =>
            new($"Unsupported Concepts.c static-constructor opcode {instruction.OpCode.Code} at IL_{instruction.Offset:x4} in 0x{_initializer.MDToken.Raw:x8}.");

        private static string FieldIdentity(IField field) => field.FullName;

        private static int LocalIndex(object operand) => operand switch
        {
            Local local => local.Index,
            ushort index => index,
            byte index => index,
            _ => throw new InvalidDataException($"Unsupported local operand '{operand}'."),
        };
    }

    private sealed record Value(
        string? StringValue,
        int? IntegerValue,
        IReadOnlyList<Value>? ArrayValue,
        IReadOnlyList<ConceptTooltipPart> Parts,
        bool IsComplete,
        bool IsTextKeyReference,
        bool IsDynamic = false)
    {
        public static Value Text(string value, string offset) => new(value, null, null,
            [new ConceptTooltipPart(offset, value)], true,
            value.StartsWith("TEXT.", StringComparison.Ordinal));
        public static Value Integer(int value) => new(null, value, null, [], true, false);
        public static Value Array(int? length) => new(null, null,
            length is >= 0 ? Enumerable.Repeat(Unknown("array-slot"), length.Value).ToArray() : null,
            [], length is >= 0, false);
        public static Value Concept(string key) => new(null, null, null,
            [new ConceptTooltipPart("<generated>", $"<concept:{key}>")], true, false);
        public static Value Dynamic(string identifier) => new($"{{{identifier}}}", null, null,
            [new ConceptTooltipPart("<dynamic>", $"{{{identifier}}}")], true, false, true);
        public static Value Unknown(string reason) => new(reason, null, null,
            [new ConceptTooltipPart("<unknown>", $"<{reason}>")], false, false);

        public Value WithElement(int? index, Value value)
        {
            if (ArrayValue is null || index is null || index < 0 || index >= ArrayValue.Count)
                return Unknown("array-write");
            var copy = ArrayValue.ToArray();
            copy[index.Value] = value;
            return this with { ArrayValue = copy, IsComplete = value.IsComplete && IsComplete };
        }

        public static Value Concat(IReadOnlyList<Value> values)
        {
            if (values.Count == 1 && values[0].ArrayValue is { } array)
                values = array;
            var complete = values.All(value => value.StringValue is not null && value.IsComplete);
            if (!complete)
                return Unknown("concat");
            var text = string.Concat(values.Select(value => value.StringValue));
            return new Value(text, null, null,
                values.SelectMany(value => value.Parts).ToArray(), true,
                text.StartsWith("TEXT.", StringComparison.Ordinal),
                values.Any(value => value.IsDynamic));
        }

        public static Value Format(IReadOnlyList<Value> values)
        {
            if (values.Count == 0 || values[0].StringValue is null)
                return Unknown("format");
            var arguments = values.Skip(1).Select(value => value.StringValue is not null
                ? (object)value.StringValue
                : value.IntegerValue).ToArray();
            if (arguments.Any(argument => argument is null)) return Unknown("format-argument");
            var text = string.Format(System.Globalization.CultureInfo.InvariantCulture,
                values[0].StringValue!, arguments);
            return new Value(text, null, null,
                values.SelectMany(value => value.Parts).ToArray(), true,
                text.StartsWith("TEXT.", StringComparison.Ordinal));
        }
    }
}

public sealed record ConceptTooltipCatalogResult(
    string AssemblyPath,
    string TypeFullName,
    string StaticConstructorToken,
    IReadOnlyList<ConceptTooltipEntry> Entries);

public sealed record ConceptTooltipEntry(
    string Key,
    string? Label,
    string? Description,
    string RegistrationOffset,
    string Composition,
    bool IsComplete,
    bool IsXmlTextKeyReference,
    IReadOnlyList<ConceptTooltipPart> Parts);

public sealed record ConceptTooltipPart(string IlOffset, string Value);
