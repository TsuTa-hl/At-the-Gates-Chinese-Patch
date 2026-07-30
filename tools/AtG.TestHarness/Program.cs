using System.Text.Json;
using AtG.TestHarness;

if (args.Length == 0 || args[0] is "-h" or "--help")
{
    PrintUsage();
    return 0;
}
var jsonOptions = new JsonSerializerOptions { WriteIndented = true };

try
{
    var scenarioPath = Option("--scenarios") ?? throw new ArgumentException("--scenarios is required.");
    var suite = Option("--suite") ?? "Incremental";
    var scenarioId = Option("--scenario");
    var document = ScenarioDocument.Load(scenarioPath);
    var scenarios = SelectScenarios(document, suite, scenarioId).ToArray();
    var plan = SessionPlanner.Create(scenarios, HasFlag("--include-completed"));
    var passCount = ParsePassCount(Option("--passes"));

    if (args[0].Equals("plan", StringComparison.OrdinalIgnoreCase))
    {
        Console.WriteLine(JsonSerializer.Serialize(plan, jsonOptions));
        return 0;
    }
    if (plan.Points.Count == 0)
    {
        Console.WriteLine(JsonSerializer.Serialize(new
        {
            Status = "Skipped",
            Reason = "The selected scenarios contain no runtime points (Deferred or archived).",
        }, jsonOptions));
        return 0;
    }
    var output = Option("--output") ?? Path.Combine(
        Directory.GetCurrentDirectory(), ".tmp", "runs",
        DateTime.Now.ToString("yyyyMMdd-HHmmss") + "-test-session");
    IReadOnlyList<SessionResult> results;
    if (args[0].Equals("run-attached", StringComparison.OrdinalIgnoreCase))
    {
        if (passCount != 1)
            throw new ArgumentException("--passes is supported only by run-owned.");
        var processName = Option("--process-name") ?? "At The Gates";
        using var driver = new Win32WindowDriver(processName);
        results =
        [
            await SessionExecutor.ExecuteAsync(plan, driver, output, document.Policy),
        ];
    }
    else if (args[0].Equals("run-owned", StringComparison.OrdinalIgnoreCase))
    {
        var gamePath = Option("--game-path") ?? throw new ArgumentException("--game-path is required for run-owned.");
        var setup = ParseSetup(Option("--setup") ?? "main-menu");
        ValidateSetupCompatibility(scenarios, setup);
        var saveName = Option("--save-name") ?? scenarios
            .Select(scenario => scenario.SaveName)
            .FirstOrDefault(value => !string.IsNullOrWhiteSpace(value));
        var enableTextTrace = HasFlag("--text-trace");
        var enablePerformanceTrace = HasFlag("--perf");
        var owner = new Win32GameSessionOwner(
            gamePath,
            saveName: saveName,
            enableTextTrace: enableTextTrace,
            enablePerformanceTrace: enablePerformanceTrace,
            glyphMode: Option("--glyph-mode") ?? "Budgeted",
            disableWarmset: HasFlag("--disable-warmset"),
            saveAfterNewGame: HasFlag("--save-after-new-game"),
            saveEvidencePath: Path.Combine(output, "new-game-save.json"),
            textTraceEvidencePath: enableTextTrace
                ? Path.Combine(output, "runtime-text.jsonl")
                : null,
            performanceEvidencePath: enablePerformanceTrace
                ? Path.Combine(output, "runtime-performance.jsonl")
                : null);
        results = await OwnedSessionExecutor.ExecutePassesAsync(
            plan, owner, setup, output, document.Policy, passCount);
        // Keep the measured interval independent from game startup for every
        // owned performance run. One-pass scenarios (such as the main-menu
        // load flow) are still cold samples, but their raw trace also includes
        // startup warmup before SessionExecutor records its start timestamp.
        if (enablePerformanceTrace)
            RuntimePerformanceEvidence.SplitBySession(
                Path.Combine(output, "runtime-performance.jsonl"), output, results);
    }
    else throw new ArgumentException($"Unknown command '{args[0]}'.");
    object resultPayload = results.Count == 1
        ? results[0]
        : new { Passes = results };
    Console.WriteLine(JsonSerializer.Serialize(resultPayload, jsonOptions));
    return results.SelectMany(result => result.Points)
        .Any(point => point.Status == "Failed") ? 1 : 0;
}
catch (Exception ex)
{
    Console.Error.WriteLine(ex.Message);
    return 1;
}

IEnumerable<TestScenario> SelectScenarios(ScenarioDocument document, string suite, string? scenarioId)
{
    var selected = suite switch
    {
        "Incremental" => document.Incremental.AsEnumerable(),
        "FullRegression" => document.FullRegression,
        "All" => document.Incremental.Concat(document.FullRegression),
        _ => throw new ArgumentException($"Unknown suite '{suite}'."),
    };
    if (scenarioId is not null)
        selected = selected.Where(scenario =>
            scenario.Id.Equals(scenarioId, StringComparison.OrdinalIgnoreCase));
    return selected;
}

string? Option(string name)
{
    for (var index = 1; index < args.Length - 1; index++)
        if (args[index].Equals(name, StringComparison.OrdinalIgnoreCase))
            return args[index + 1];
    return null;
}

bool HasFlag(string name) => args.Any(value => value.Equals(name, StringComparison.OrdinalIgnoreCase));

int ParsePassCount(string? value)
{
    if (value is null) return 1;
    if (!int.TryParse(value, out var passCount) || passCount is < 1 or > 5)
        throw new ArgumentException("--passes must be an integer between 1 and 5.");
    return passCount;
}

GameSetupMode ParseSetup(string value) => value.ToLowerInvariant() switch
{
    "main-menu" => GameSetupMode.MainMenu,
    "main-menu-fixed-save" => GameSetupMode.MainMenuWithFixedSave,
    "new-game" => GameSetupMode.NewGame,
    "fixed-save" => GameSetupMode.FixedSave,
    _ => throw new ArgumentException($"Unknown setup mode '{value}'."),
};

void ValidateSetupCompatibility(IEnumerable<TestScenario> scenarios, GameSetupMode setup)
{
    var fixedSaveScenarioIds = scenarios
        .Where(scenario => scenario.RequiresFixedSave)
        .Select(scenario => scenario.Id)
        .ToArray();

    if (fixedSaveScenarioIds.Length == 0 ||
        setup == GameSetupMode.FixedSave ||
        setup == GameSetupMode.MainMenuWithFixedSave)
        return;

    throw new ArgumentException(
        $"Setup '{setup}' cannot run fixed-save scenarios: {string.Join(", ", fixedSaveScenarioIds)}. " +
        "Use --setup fixed-save, or --setup main-menu-fixed-save when the scenario itself performs the main-menu load flow.");
}

void PrintUsage()
{
    Console.WriteLine("AtG.TestHarness plan --scenarios PATH [--suite Incremental|FullRegression|All] [--scenario ID]");
    Console.WriteLine("AtG.TestHarness run-attached --scenarios PATH [--suite ...] [--scenario ID] [--output PATH]");
    Console.WriteLine("AtG.TestHarness run-owned --game-path PATH --setup main-menu|main-menu-fixed-save|new-game|fixed-save [--save-name FILE] [--text-trace] [--perf] [--glyph-mode Budgeted|LegacySync] [--disable-warmset] [--passes 1..5] [--save-after-new-game] --scenarios PATH [--scenario ID]");
}
