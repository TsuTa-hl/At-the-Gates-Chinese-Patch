using System.Diagnostics;
using System.Text.Json;
using Xunit;

namespace AtG.ScriptIntegration.Tests;

[CollectionDefinition(Name, DisableParallelization = true)]
public sealed class PowerShellScriptCollection
{
    public const string Name = "PowerShell script integration";
}

[Collection(PowerShellScriptCollection.Name)]
public sealed class PowerShellScriptTests
{
    private static readonly TimeSpan StaticScriptTimeout = TimeSpan.FromMinutes(5);
    private static readonly TimeSpan CatalogAuditScriptTimeout = TimeSpan.FromMinutes(8);
    private static readonly TimeSpan SmokeScriptTimeout = TimeSpan.FromMinutes(3);

    public static IEnumerable<object[]> StaticAssertions() =>
        LoadSuite().SelectedStaticAssertions.Select(path => new object[] { path });

    [Theory]
    [MemberData(nameof(StaticAssertions))]
    public async Task StaticAssertionPasses(string scriptRelativePath)
    {
        var result = await RunPowerShellScriptAsync(scriptRelativePath, GetTimeout(scriptRelativePath));
        Assert.True(result.ExitCode == 0, result.DescribeFailure(scriptRelativePath));
        Console.WriteLine($"{scriptRelativePath} passed in {result.DurationMs} ms.");
    }

    [Fact]
    public void EveryPowerShellTestScriptIsClassified()
    {
        var root = FindRepositoryRoot();
        var suite = LoadSuite();
        var classified = suite.AllTests
            .Select(test => test.Script)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        var discovered = Directory.EnumerateFiles(Path.Combine(root, "tools"), "Test-*.ps1", SearchOption.TopDirectoryOnly)
            .Select(Path.GetFileName)
            .OfType<string>()
            .ToHashSet(StringComparer.OrdinalIgnoreCase);

        var unclassified = discovered.Except(classified, StringComparer.OrdinalIgnoreCase).OrderBy(value => value).ToArray();
        var missing = classified.Except(discovered, StringComparer.OrdinalIgnoreCase).OrderBy(value => value).ToArray();

        Assert.True(unclassified.Length == 0, "Unclassified PowerShell test scripts: " + string.Join(", ", unclassified));
        Assert.True(missing.Length == 0, "PowerShell test suite references missing scripts: " + string.Join(", ", missing));
    }

    [Fact]
    public async Task RealGameSmokePassesWhenGateSuppliesGamePath()
    {
        var gamePath = Environment.GetEnvironmentVariable("ATG_GAME_PATH");
        if (string.IsNullOrWhiteSpace(gamePath))
        {
            return;
        }

        var smokeTests = LoadSuite().SelectedSmokeAssertions;
        Assert.True(smokeTests.Count == 1,
            "The selected verification profile must include exactly one main-menu smoke assertion.");
        var scriptRelativePath = smokeTests[0];
        var result = await RunPowerShellScriptAsync(scriptRelativePath, SmokeScriptTimeout,
            "-GamePath", gamePath);
        Assert.True(result.ExitCode == 0, result.DescribeFailure(scriptRelativePath));
        Console.WriteLine($"{scriptRelativePath} passed in {result.DurationMs} ms.");
    }

    private static TimeSpan GetTimeout(string scriptRelativePath) =>
        scriptRelativePath is "Test-InterfaceLocalizationProgress.ps1" or
            "Test-KnownTextReviewExport.ps1" or "Test-LocalizationTodoList.ps1"
            ? CatalogAuditScriptTimeout
            : StaticScriptTimeout;

    private static async Task<ProcessResult> RunPowerShellScriptAsync(
        string scriptRelativePath,
        TimeSpan timeout,
        params string[] arguments)
    {
        var root = FindRepositoryRoot();
        var scriptPath = Path.Combine(root, "tools", scriptRelativePath);
        Assert.True(File.Exists(scriptPath), "PowerShell test script not found: " + scriptPath);

        var startInfo = new ProcessStartInfo
        {
            FileName = Environment.GetEnvironmentVariable("ATG_POWERSHELL_PATH") ?? "powershell.exe",
            WorkingDirectory = root,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
        };
        startInfo.ArgumentList.Add("-NoLogo");
        startInfo.ArgumentList.Add("-NoProfile");
        startInfo.ArgumentList.Add("-ExecutionPolicy");
        startInfo.ArgumentList.Add("Bypass");
        startInfo.ArgumentList.Add("-File");
        startInfo.ArgumentList.Add(scriptPath);
        foreach (var argument in arguments)
        {
            startInfo.ArgumentList.Add(argument);
        }

        using var process = new Process { StartInfo = startInfo };
        Assert.True(process.Start(), "Could not start PowerShell for " + scriptRelativePath);
        var stopwatch = Stopwatch.StartNew();
        var stdoutTask = process.StandardOutput.ReadToEndAsync();
        var stderrTask = process.StandardError.ReadToEndAsync();
        using var cancellation = new CancellationTokenSource(timeout);

        try
        {
            await process.WaitForExitAsync(cancellation.Token);
        }
        catch (OperationCanceledException)
        {
            if (!process.HasExited)
            {
                process.Kill(entireProcessTree: true);
            }

            await process.WaitForExitAsync();
            stopwatch.Stop();
            return new ProcessResult(-1, await stdoutTask, await stderrTask, TimedOut: true,
                stopwatch.ElapsedMilliseconds);
        }

        stopwatch.Stop();
        return new ProcessResult(process.ExitCode, await stdoutTask, await stderrTask, TimedOut: false,
            stopwatch.ElapsedMilliseconds);
    }

    private static ScriptSuite LoadSuite()
    {
        var path = Path.Combine(FindRepositoryRoot(), "tools", "power-shell-test-suite.json");
        using var document = JsonDocument.Parse(File.ReadAllText(path));
        var root = document.RootElement;
        var schemaVersion = root.GetProperty("SchemaVersion").GetInt32();
        Assert.True(schemaVersion == 2, "Unsupported PowerShell test suite schema: " + schemaVersion);

        var allTests = root.GetProperty("Tests").EnumerateArray()
            .Select(ReadScriptDefinition)
            .ToArray();
        ValidateSuite(allTests);

        var profile = Environment.GetEnvironmentVariable("ATG_VERIFICATION_PROFILE") ?? "Release";
        Assert.True(profile is "Localization" or "Release",
            "Unsupported ATG_VERIFICATION_PROFILE: " + profile);
        var requestedIds = ReadDelimitedEnvironment("ATG_VERIFICATION_SELECTED_TEST_IDS");
        var categories = ReadDelimitedEnvironment("ATG_VERIFICATION_CHANGED_PATH_CATEGORIES");
        if (categories.Count == 0)
        {
            categories.Add("core");
        }
        var documentationOnly = profile == "Localization" && categories.Count > 0 &&
            categories.All(category => string.Equals(category, "documentation", StringComparison.OrdinalIgnoreCase));

        var knownIds = allTests.Select(test => test.Id).ToHashSet(StringComparer.OrdinalIgnoreCase);
        var unknownIds = requestedIds.Where(id => !knownIds.Contains(id)).OrderBy(id => id).ToArray();
        Assert.True(unknownIds.Length == 0,
            "ATG_VERIFICATION_SELECTED_TEST_IDS contains unknown test IDs: " + string.Join(", ", unknownIds));

        var selected = allTests.Where(test => IsSelected(test, profile, requestedIds, categories, documentationOnly)).ToArray();
        return new ScriptSuite(
            allTests,
            selected.Where(test => test.Kind == "Static").Select(test => test.Script).ToArray(),
            selected.Where(test => test.Kind == "Smoke").Select(test => test.Script).ToArray());
    }

    private static ScriptDefinition ReadScriptDefinition(JsonElement value)
    {
        var id = ReadRequiredString(value, "Id");
        var script = ReadRequiredString(value, "Script");
        var kind = ReadRequiredString(value, "Kind");
        var profiles = ReadRequiredStrings(value, "Profiles");
        var triggers = ReadRequiredStrings(value, "Triggers");
        _ = ReadRequiredStrings(value, "EnvironmentPrerequisites");
        var alwaysForLocalization = value.TryGetProperty("AlwaysForLocalization", out var alwaysValue) &&
            alwaysValue.ValueKind == JsonValueKind.True;
        return new ScriptDefinition(id, script, kind, profiles, triggers, alwaysForLocalization);
    }

    private static string ReadRequiredString(JsonElement value, string propertyName)
    {
        Assert.True(value.TryGetProperty(propertyName, out var property) &&
            property.ValueKind == JsonValueKind.String && !string.IsNullOrWhiteSpace(property.GetString()),
            "Verification suite item is missing non-empty " + propertyName + ".");
        return property.GetString()!;
    }

    private static IReadOnlyList<string> ReadRequiredStrings(JsonElement value, string propertyName)
    {
        Assert.True(value.TryGetProperty(propertyName, out var property) && property.ValueKind == JsonValueKind.Array,
            "Verification suite item is missing array " + propertyName + ".");
        var strings = property.EnumerateArray()
            .Where(item => item.ValueKind == JsonValueKind.String && !string.IsNullOrWhiteSpace(item.GetString()))
            .Select(item => item.GetString()!)
            .ToArray();
        Assert.True(strings.Length > 0 || propertyName == "EnvironmentPrerequisites",
            "Verification suite item has empty " + propertyName + ".");
        return strings;
    }

    private static void ValidateSuite(IReadOnlyList<ScriptDefinition> tests)
    {
        Assert.True(tests.Count > 0, "PowerShell verification suite is empty.");
        Assert.True(tests.Select(test => test.Id).Distinct(StringComparer.OrdinalIgnoreCase).Count() == tests.Count,
            "PowerShell verification suite has duplicate test IDs.");
        Assert.True(tests.Select(test => test.Script).Distinct(StringComparer.OrdinalIgnoreCase).Count() == tests.Count,
            "PowerShell verification suite has duplicate script classifications.");
        Assert.True(tests.All(test => Path.GetFileName(test.Script) == test.Script),
            "PowerShell verification scripts must be repository tools filenames, not paths.");
        Assert.True(tests.All(test => test.Kind is "Static" or "Smoke"),
            "PowerShell verification suite contains an unsupported script kind.");
        Assert.True(tests.All(test => test.Profiles.Contains("Release", StringComparer.Ordinal)),
            "Release must cover every PowerShell verification script.");
        Assert.True(tests.Count(test => test.Kind == "Smoke" &&
            string.Equals(test.Script, "Test-GameLaunch.ps1", StringComparison.OrdinalIgnoreCase)) == 1,
            "The suite must classify Test-GameLaunch.ps1 as exactly one smoke assertion.");
    }

    private static bool IsSelected(ScriptDefinition test, string profile, ISet<string> requestedIds,
        ISet<string> categories, bool documentationOnly)
    {
        if (requestedIds.Count > 0)
        {
            return requestedIds.Contains(test.Id);
        }
        if (!test.Profiles.Contains(profile, StringComparer.Ordinal))
        {
            return false;
        }
        if (documentationOnly)
        {
            return test.Triggers.Contains("documentation", StringComparer.Ordinal);
        }
        if (profile == "Release" || test.AlwaysForLocalization)
        {
            return true;
        }
        return test.Triggers.Any(categories.Contains);
    }

    private static HashSet<string> ReadDelimitedEnvironment(string name)
    {
        var value = Environment.GetEnvironmentVariable(name);
        return string.IsNullOrWhiteSpace(value)
            ? new HashSet<string>(StringComparer.OrdinalIgnoreCase)
            : value.Split(new[] { ';' }, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
                .ToHashSet(StringComparer.OrdinalIgnoreCase);
    }

    private static string FindRepositoryRoot()
    {
        for (var directory = new DirectoryInfo(AppContext.BaseDirectory); directory is not null; directory = directory.Parent)
        {
            if (File.Exists(Path.Combine(directory.FullName, "AtG.Patch.sln")) &&
                Directory.Exists(Path.Combine(directory.FullName, "tools")))
            {
                return directory.FullName;
            }
        }

        throw new DirectoryNotFoundException("Could not locate the repository root from the test output directory.");
    }

    private sealed record ScriptDefinition(
        string Id,
        string Script,
        string Kind,
        IReadOnlyList<string> Profiles,
        IReadOnlyList<string> Triggers,
        bool AlwaysForLocalization);

    private sealed record ScriptSuite(
        IReadOnlyList<ScriptDefinition> AllTests,
        IReadOnlyList<string> SelectedStaticAssertions,
        IReadOnlyList<string> SelectedSmokeAssertions);

    private sealed record ProcessResult(int ExitCode, string StandardOutput, string StandardError, bool TimedOut,
        long DurationMs)
    {
        public string DescribeFailure(string scriptRelativePath) =>
            $"PowerShell test '{scriptRelativePath}' {(TimedOut ? "timed out" : "failed")} (exit {ExitCode}, {DurationMs} ms)." +
            Environment.NewLine + "stdout:" + Environment.NewLine + StandardOutput +
            Environment.NewLine + "stderr:" + Environment.NewLine + StandardError;
    }
}
