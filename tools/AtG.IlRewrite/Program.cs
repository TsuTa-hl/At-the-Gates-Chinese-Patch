using System.Text.Json;
using System.Text.Json.Serialization;
using dnlib.DotNet;
using dnlib.DotNet.Emit;

try
{
var options = CommandLineOptions.Parse(args);
var specs = RewriteSpec.Load(options.MapPath);
if (specs.Count == 0)
{
    Directory.CreateDirectory(Path.GetDirectoryName(options.OutputPath) ?? ".");
    File.Copy(options.SourcePath, options.OutputPath, overwrite: true);
    Console.WriteLine($"No IL rewrite entries found. Copied source DLL unchanged: {options.OutputPath}");
    return 0;
}

var module = ModuleDefMD.Load(options.SourcePath);
var rewritten = 0;

foreach (var spec in specs)
{
    spec.Validate();
    var method = ResolveMethod(module, spec.MethodToken!);
    if (method.Body is null)
    {
        throw new InvalidOperationException($"Method {spec.MethodToken} has no body.");
    }

    var instruction = method.Body.Instructions.FirstOrDefault(i =>
        i.OpCode == OpCodes.Ldstr &&
        i.Offset == spec.ILOffset);
    if (instruction is null)
    {
        throw new InvalidOperationException(
            $"No ldstr instruction found at IL offset {spec.ILOffset} in method {spec.MethodToken}.");
    }

    var actual = instruction.Operand as string;
    if (!StringComparer.Ordinal.Equals(actual, spec.Original))
    {
        throw new InvalidOperationException(
            $"Original mismatch at method {spec.MethodToken}, IL offset {spec.ILOffset}. " +
            $"Expected '{spec.Original}', actual '{actual}'.");
    }

    instruction.Operand = spec.Translation ?? string.Empty;
    rewritten++;
    Console.WriteLine(
        $"IL rewrite '{spec.Original}' -> '{spec.Translation}' " +
        $"({spec.MethodToken} IL_{spec.ILOffset:x4}).");
}

Directory.CreateDirectory(Path.GetDirectoryName(options.OutputPath) ?? ".");
module.Write(options.OutputPath);
Console.WriteLine($"Built IL rewrite patch: {options.OutputPath} ({rewritten} ldstr instruction(s)).");
return 0;
}
catch (Exception ex)
{
    Console.Error.WriteLine($"ERROR: {ex.Message}");
    return 1;
}

static MethodDef ResolveMethod(ModuleDefMD module, string methodTokenText)
{
    var token = ParseToken(methodTokenText);
    if ((token & 0xff000000) != 0x06000000)
    {
        throw new InvalidOperationException($"MethodToken must be a MethodDef token: {methodTokenText}");
    }

    var resolved = module.ResolveToken(token);
    if (resolved is not MethodDef method)
    {
        throw new InvalidOperationException($"Method token not found: {methodTokenText}");
    }

    return method;
}

static uint ParseToken(string text)
{
    if (string.IsNullOrWhiteSpace(text))
    {
        throw new InvalidOperationException("Token text is empty.");
    }

    text = text.Trim();
    if (text.StartsWith("0x", StringComparison.OrdinalIgnoreCase))
    {
        return Convert.ToUInt32(text[2..], 16);
    }

    return Convert.ToUInt32(text);
}

sealed class CommandLineOptions
{
    public required string SourcePath { get; init; }
    public required string OutputPath { get; init; }
    public required string MapPath { get; init; }

    public static CommandLineOptions Parse(string[] args)
    {
        string? source = null;
        string? output = null;
        string? map = null;

        for (var i = 0; i < args.Length; i++)
        {
            var arg = args[i];
            if (i + 1 >= args.Length)
            {
                throw new InvalidOperationException($"Missing value for argument '{arg}'.");
            }

            switch (arg)
            {
                case "--source":
                    source = args[++i];
                    break;
                case "--output":
                    output = args[++i];
                    break;
                case "--map":
                    map = args[++i];
                    break;
                default:
                    throw new InvalidOperationException($"Unknown argument '{arg}'.");
            }
        }

        if (string.IsNullOrWhiteSpace(source) ||
            string.IsNullOrWhiteSpace(output) ||
            string.IsNullOrWhiteSpace(map))
        {
            throw new InvalidOperationException("Usage: AtG.IlRewrite --source <dll> --output <dll> --map <json>");
        }

        return new CommandLineOptions
        {
            SourcePath = source,
            OutputPath = output,
            MapPath = map
        };
    }
}

sealed class RewriteSpec
{
    public string? Original { get; init; }
    public string? Translation { get; init; }
    public string? MethodToken { get; init; }
    public int ILOffset { get; init; }

    [JsonExtensionData]
    public Dictionary<string, JsonElement>? Extra { get; init; }

    public void Validate()
    {
        if (Original is null)
        {
            throw new InvalidOperationException("Rewrite entry is missing Original.");
        }
        if (Translation is null)
        {
            throw new InvalidOperationException($"Rewrite entry '{Original}' is missing Translation.");
        }
        if (string.IsNullOrWhiteSpace(MethodToken))
        {
            throw new InvalidOperationException($"Rewrite entry '{Original}' is missing MethodToken.");
        }
    }

    public static IReadOnlyList<RewriteSpec> Load(string path)
    {
        var json = File.ReadAllText(path);
        var serializerOptions = new JsonSerializerOptions
        {
            PropertyNameCaseInsensitive = true,
            ReadCommentHandling = JsonCommentHandling.Skip,
            AllowTrailingCommas = true
        };

        using var document = JsonDocument.Parse(json, new JsonDocumentOptions
        {
            CommentHandling = JsonCommentHandling.Skip,
            AllowTrailingCommas = true
        });

        if (document.RootElement.ValueKind == JsonValueKind.Array)
        {
            var specs = JsonSerializer.Deserialize<List<RewriteSpec>>(json, serializerOptions);
            return specs ?? [];
        }

        if (document.RootElement.ValueKind == JsonValueKind.Object)
        {
            var spec = JsonSerializer.Deserialize<RewriteSpec>(json, serializerOptions);
            return spec is null ? [] : [spec];
        }

        throw new InvalidOperationException("Rewrite map must be a JSON array or object.");
    }
}
