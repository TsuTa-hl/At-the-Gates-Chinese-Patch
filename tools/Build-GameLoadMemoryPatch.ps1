param(
    [Parameter(Mandatory = $true)]
    [string]$InputExe,

    [Parameter(Mandatory = $true)]
    [string]$OutputExe,

    [string]$DnlibPath
)

$ErrorActionPreference = "Stop"

function Invoke-AtGFileReplacementWithRetry {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination,
        [int]$MaxAttempts = 5
    )

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            [System.IO.File]::Copy($Source, $Destination, $true)
            return
        }
        catch [System.IO.IOException] {
            if ($attempt -ge $MaxAttempts) { throw }
            $delayMs = [Math]::Min(2000, 250 * [Math]::Pow(2, $attempt - 1))
            Write-Warning ("Game patch output is temporarily mapped; retrying replacement attempt {0}/{1} after {2} ms." -f ($attempt + 1), $MaxAttempts, $delayMs)
            [GC]::Collect()
            [GC]::WaitForPendingFinalizers()
            Start-Sleep -Milliseconds $delayMs
        }
    }
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($DnlibPath)) {
    $DnlibPath = Join-Path $scriptRoot "..\.tools\nuget-cache\dnlib\4.5.0\lib\net45\dnlib.dll"
}

if (!(Test-Path -LiteralPath $InputExe -PathType Leaf)) {
    throw "Input executable not found: $InputExe"
}
if (!(Test-Path -LiteralPath $DnlibPath -PathType Leaf)) {
    throw "dnlib not found: $DnlibPath"
}

$patcherCode = @"
using System;
using System.IO;
using System.Linq;
using dnlib.DotNet;
using dnlib.DotNet.Emit;
using dnlib.DotNet.Writer;

public static class AtGGameLoadMemoryPatcher {
    public static void Patch(string inputPath, string outputPath) {
        ModuleDefMD module = null;
        try {
            module = ModuleDefMD.Load(inputPath);
            var appType = module.GetTypes().FirstOrDefault(t =>
                t.FullName == "AtTheGatesGame.ns_UIControllers.ATGApplication");
            if (appType == null) {
                throw new InvalidOperationException("ATGApplication type not found.");
            }

            var method = appType.Methods.FirstOrDefault(m => m.Name == "LoadWorld");
            if (method == null || method.Body == null) {
                throw new InvalidOperationException("LoadWorld method body not found.");
            }

            var collect = module.Import(typeof(GC).GetMethod("Collect", Type.EmptyTypes));
            var waitForPendingFinalizers = module.Import(typeof(GC).GetMethod("WaitForPendingFinalizers", Type.EmptyTypes));

            var instructions = method.Body.Instructions;
            var initLoadFirstIndex = -1;
            for (var i = 0; i < instructions.Count; i++) {
                if (instructions[i].OpCode != OpCodes.Callvirt || instructions[i].Operand == null) {
                    continue;
                }

                var calledMethod = instructions[i].Operand as IMethod;
                if (calledMethod != null &&
                    calledMethod.Name == "Init_Load_First" &&
                    calledMethod.DeclaringType.FullName == "AtTheGatesGame.ns_GameCode.WorldCore") {
                    initLoadFirstIndex = i;
                    break;
                }
            }

            if (initLoadFirstIndex < 0) {
                throw new InvalidOperationException("WorldCore.Init_Load_First call not found in LoadWorld.");
            }

            var insertAt = initLoadFirstIndex + 1;
            if (insertAt < instructions.Count && instructions[insertAt].OpCode == OpCodes.Nop) {
                insertAt++;
            }

            var patch = new[] {
                Instruction.Create(OpCodes.Call, collect),
                Instruction.Create(OpCodes.Call, waitForPendingFinalizers),
                Instruction.Create(OpCodes.Call, collect)
            };

            for (var i = 0; i < patch.Length; i++) {
                instructions.Insert(insertAt + i, patch[i]);
            }

            method.Body.SimplifyBranches();
            method.Body.OptimizeBranches();

            var outputDirectory = Path.GetDirectoryName(outputPath);
            if (!string.IsNullOrEmpty(outputDirectory)) {
                Directory.CreateDirectory(outputDirectory);
            }

            var writerOptions = new ModuleWriterOptions(module);
            writerOptions.MetadataOptions.Flags = MetadataFlags.PreserveAll;
            module.Write(outputPath, writerOptions);
        }
        finally {
            if (module != null) {
                module.Dispose();
            }
        }
    }
}
"@

Add-Type -Path $DnlibPath
Add-Type -ReferencedAssemblies $DnlibPath -TypeDefinition $patcherCode

$resolvedInput = (Resolve-Path -LiteralPath $InputExe).Path
$resolvedOutput = [System.IO.Path]::GetFullPath($OutputExe)

if ([System.IO.Path]::GetFullPath($resolvedInput) -ieq [System.IO.Path]::GetFullPath($resolvedOutput)) {
    $tempOutput = [System.IO.Path]::Combine(
        [System.IO.Path]::GetDirectoryName($resolvedOutput),
        ([System.IO.Path]::GetFileName($resolvedOutput) + ".memorypatch.tmp"))
    if (Test-Path -LiteralPath $tempOutput) {
        Remove-Item -LiteralPath $tempOutput -Force
    }
    [AtGGameLoadMemoryPatcher]::Patch($resolvedInput, $tempOutput)
    Invoke-AtGFileReplacementWithRetry -Source $tempOutput -Destination $resolvedOutput
    Remove-Item -LiteralPath $tempOutput -Force
}
else {
    [AtGGameLoadMemoryPatcher]::Patch($resolvedInput, $resolvedOutput)
}

Write-Host "Built game load memory patch: $OutputExe"
