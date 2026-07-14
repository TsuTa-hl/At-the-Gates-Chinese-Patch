param(
    [string]$GameExePath = "$PSScriptRoot\..\patch\At The Gates.exe",
    [string]$ElfToolsPath = "$PSScriptRoot\..\patch\ElfTools.dll",
    [string]$DnlibPath = "$PSScriptRoot\..\.tools\nuget-cache\dnlib\4.5.0\lib\net45\dnlib.dll"
)

$ErrorActionPreference = "Stop"

function Assert-AtG {
    param([bool]$Condition, [string]$Message)
    if (!$Condition) { throw $Message }
}

Assert-AtG (Test-Path -LiteralPath $GameExePath -PathType Leaf) "Patched game executable not found: $GameExePath"
Assert-AtG (Test-Path -LiteralPath $ElfToolsPath -PathType Leaf) "Patched ElfTools assembly not found: $ElfToolsPath"
Assert-AtG (Test-Path -LiteralPath $DnlibPath -PathType Leaf) "dnlib not found: $DnlibPath"

$verifierCode = @"
using System;
using System.IO;
using System.Linq;
using dnlib.DotNet;
using dnlib.DotNet.Emit;

public static class AtGGameLoadMemoryPatchVerifier {
    private static bool IsLargeAddressAware(string path) {
        var bytes = File.ReadAllBytes(path);
        if (bytes.Length < 0x40) return false;
        var peHeader = BitConverter.ToInt32(bytes, 0x3c);
        if (peHeader < 0 || peHeader + 24 > bytes.Length) return false;
        var characteristics = BitConverter.ToUInt16(bytes, peHeader + 22);
        return (characteristics & 0x20) != 0;
    }

    private static int FindCall(System.Collections.Generic.IList<Instruction> instructions, string text) {
        for (var index = 0; index < instructions.Count; index++) {
            var instruction = instructions[index];
            if ((instruction.OpCode == OpCodes.Call || instruction.OpCode == OpCodes.Callvirt) &&
                instruction.Operand != null && instruction.Operand.ToString().Contains(text)) return index;
        }
        return -1;
    }

    private static bool HasNullStaticStore(
        System.Collections.Generic.IList<Instruction> instructions,
        string fieldName) {
        for (var index = 1; index < instructions.Count; index++) {
            if (instructions[index].OpCode != OpCodes.Stsfld || instructions[index].Operand == null ||
                !instructions[index].Operand.ToString().Contains(fieldName)) continue;
            return instructions[index - 1].OpCode == OpCodes.Ldnull;
        }
        return false;
    }

    public static string VerifyGame(string path) {
        if (!IsLargeAddressAware(path))
            return "Patched x86 game executable is not large-address aware.";
        using (var module = ModuleDefMD.Load(path)) {
            if (module.GetAssemblyRefs().Any(reference =>
                    reference.Name == "System.Private.CoreLib"))
                return "Patched .NET Framework game unexpectedly references System.Private.CoreLib.";
            var appType = module.GetTypes().FirstOrDefault(t =>
                t.FullName == "AtTheGatesGame.ns_UIControllers.ATGApplication");
            if (appType == null) return "ATGApplication type not found.";

            var loadWorld = appType.Methods.FirstOrDefault(m => m.Name == "LoadWorld");
            if (loadWorld == null || loadWorld.Body == null) return "LoadWorld method body not found.";
            var worldInstructions = loadWorld.Body.Instructions;
            var initIndex = FindCall(worldInstructions, "WorldCore::Init_Load_First(");
            var loadDataIndex = FindCall(worldInstructions, "WorldCore::LoadData(");
            var firstCollectIndex = FindCall(worldInstructions, "System.GC::Collect(");
            var waitIndex = FindCall(worldInstructions, "System.GC::WaitForPendingFinalizers(");
            var lastCollectIndex = -1;
            for (var index = worldInstructions.Count - 1; index >= 0; index--) {
                if ((worldInstructions[index].OpCode == OpCodes.Call || worldInstructions[index].OpCode == OpCodes.Callvirt) &&
                    worldInstructions[index].Operand != null &&
                    worldInstructions[index].Operand.ToString().Contains("System.GC::Collect(")) {
                    lastCollectIndex = index;
                    break;
                }
            }
            if (!(initIndex >= 0 && initIndex < firstCollectIndex && firstCollectIndex < waitIndex &&
                  waitIndex < lastCollectIndex && lastCollectIndex < loadDataIndex))
                return "Forced collection is not between Init_Load_First and LoadData.";

            var loadStep = appType.Methods.FirstOrDefault(m => m.Name == "LoadGame_Step2");
            if (loadStep == null || loadStep.Body == null) return "LoadGame_Step2 method body not found.";
            var instructions = loadStep.Body.Instructions;
            var createIndex = FindCall(instructions, "ATGApplication::CreateWorldScreen(");
            var loadFileIndex = FindCall(instructions, "ATGApplication::LoadFromFile(");
            var disposeIndex = FindCall(instructions, "IdSpriteBatch::Dispose(System.Boolean)");
            var clearBatchIndex = FindCall(instructions, "ATGGAME::set_IdSpriteBatch(");
            var clearRootsIndex = FindCall(instructions, "DebugConsole::AtGClearWorldReferences()");
            if (!(createIndex >= 0 && createIndex < disposeIndex && disposeIndex < clearBatchIndex &&
                  clearBatchIndex < clearRootsIndex && clearRootsIndex < loadFileIndex))
                return "Old-world teardown is not before LoadFromFile.";

            var debugConsole = module.GetTypes().FirstOrDefault(t =>
                t.FullName == "AtTheGatesGame.DebugConsoleNS.DebugConsole");
            var clearRoots = debugConsole == null ? null : debugConsole.Methods.FirstOrDefault(m =>
                m.Name == "AtGClearWorldReferences");
            if (clearRoots == null || clearRoots.Body == null || !clearRoots.IsPublic || !clearRoots.IsStatic)
                return "Public static DebugConsole.AtGClearWorldReferences helper not found.";
            var clearInstructions = clearRoots.Body.Instructions;
            var fields = new[] { "::WSC", "::Human", "::MouseoverTile", "::SelectedObject" };
            foreach (var field in fields)
                if (!HasNullStaticStore(clearInstructions, field))
                    return "Missing old-world static root clear: " + field + ".";
            return "";
        }
    }

    public static string VerifyElfTools(string path) {
        using (var module = ModuleDefMD.Load(path)) {
            var type = module.GetTypes().FirstOrDefault(t =>
                t.FullName == "ElfTools.Graphics.ElfSpriteBatch.IdBatch.IdSpriteBatch");
            var method = type == null ? null : type.Methods.FirstOrDefault(m =>
                m.Name == "Dispose" && m.MethodSig != null && m.MethodSig.Params.Count == 1);
            if (method == null || method.Body == null) return "IdSpriteBatch.Dispose(bool) not found.";
            var text = string.Join("\n", method.Body.Instructions.Select(i => i.ToString()));
            if (!text.Contains("indexBuf")) return "IdSpriteBatch owned index buffer is not released.";
            if (text.Contains("_defaultEffect")) return "IdSpriteBatch teardown still releases the shared default effect.";
            var disposeCalls = method.Body.Instructions.Count(i =>
                (i.OpCode == OpCodes.Call || i.OpCode == OpCodes.Callvirt) && i.Operand != null &&
                i.Operand.ToString().Contains("GraphicsResource::Dispose()"));
            if (disposeCalls != 1) return "Expected exactly one owned GraphicsResource.Dispose call, found " + disposeCalls + ".";
            return "";
        }
    }
}
"@

Add-Type -Path $DnlibPath
Add-Type -ReferencedAssemblies $DnlibPath -TypeDefinition $verifierCode

$failure = [AtGGameLoadMemoryPatchVerifier]::VerifyGame((Resolve-Path -LiteralPath $GameExePath))
Assert-AtG ([string]::IsNullOrWhiteSpace($failure)) $failure
$failure = [AtGGameLoadMemoryPatchVerifier]::VerifyElfTools((Resolve-Path -LiteralPath $ElfToolsPath))
Assert-AtG ([string]::IsNullOrWhiteSpace($failure)) $failure

Write-Host "Game load lifecycle patch validation passed."
