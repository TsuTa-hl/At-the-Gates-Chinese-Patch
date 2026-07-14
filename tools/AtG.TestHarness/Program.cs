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

    if (args[0].Equals("plan", StringComparison.OrdinalIgnoreCase))
    {
        Console.WriteLine(JsonSerializer.Serialize(plan, jsonOptions));
        return 0;
    }
    var output = Option("--output") ?? Path.Combine(
        Directory.GetCurrentDirectory(), ".tmp", "runs",
        DateTime.Now.ToString("yyyyMMdd-HHmmss") + "-test-session");
    SessionResult result;
    if (args[0].Equals("run-attached", StringComparison.OrdinalIgnoreCase))
    {
        var processName = Option("--process-name") ?? "At The Gates";
        using var driver = new Win32WindowDriver(processName);
        result = await SessionExecutor.ExecuteAsync(plan, driver, output, document.Policy);
    }
    else if (args[0].Equals("run-owned", StringComparison.OrdinalIgnoreCase))
    {
        var gamePath = Option("--game-path") ?? throw new ArgumentException("--game-path is required for run-owned.");
        var setup = ParseSetup(Option("--setup") ?? "main-menu");
        var saveName = Option("--save-name") ?? scenarios
            .Select(scenario => scenario.SaveName)
            .FirstOrDefault(value => !string.IsNullOrWhiteSpace(value));
        var owner = new Win32GameSessionOwner(
            gamePath,
            saveName: saveName,
            enableTextTrace: HasFlag("--text-trace"));
        result = await OwnedSessionExecutor.ExecuteAsync(
            plan, owner, setup, output, document.Policy);
    }
    else throw new ArgumentException($"Unknown command '{args[0]}'.");
    Console.WriteLine(JsonSerializer.Serialize(result, jsonOptions));
    return result.Points.Any(point => point.Status == "Failed") ? 1 : 0;
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

GameSetupMode ParseSetup(string value) => value.ToLowerInvariant() switch
{
    "main-menu" => GameSetupMode.MainMenu,
    "new-game" => GameSetupMode.NewGame,
    "fixed-save" => GameSetupMode.FixedSave,
    _ => throw new ArgumentException($"Unknown setup mode '{value}'."),
};

void PrintUsage()
{
    Console.WriteLine("AtG.TestHarness plan --scenarios PATH [--suite Incremental|FullRegression|All] [--scenario ID]");
    Console.WriteLine("AtG.TestHarness run-attached --scenarios PATH [--suite ...] [--scenario ID] [--output PATH]");
    Console.WriteLine("AtG.TestHarness run-owned --game-path PATH --setup main-menu|new-game|fixed-save [--save-name FILE] [--text-trace] --scenarios PATH [--scenario ID]");
}
