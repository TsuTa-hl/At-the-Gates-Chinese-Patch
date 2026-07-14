using System.Text.Json;

namespace AtG.TestHarness;

public sealed class ScenarioDocument
{
    public ScenarioPolicy Policy { get; init; } = new();
    public TestScenario[] FullRegression { get; init; } = [];
    public TestScenario[] Incremental { get; init; } = [];

    public static ScenarioDocument Load(string path) =>
        JsonSerializer.Deserialize<ScenarioDocument>(File.ReadAllText(path), JsonOptions)
        ?? throw new InvalidDataException($"Unable to parse scenario document '{path}'.");

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
        ReadCommentHandling = JsonCommentHandling.Skip,
        AllowTrailingCommas = true,
    };
}

public sealed class ScenarioPolicy
{
    public int HoverWaitMsDefault { get; init; } = 900;
    public int HoverWaitMsMaximum { get; init; } = 3000;
}

public sealed class TestScenario
{
    public string Id { get; init; } = string.Empty;
    public string Interface { get; init; } = string.Empty;
    public string StateId { get; init; } = string.Empty;
    public string Setup { get; init; } = string.Empty;
    public bool RequiresFixedSave { get; init; }
    public string? SaveName { get; init; }
    public string Status { get; init; } = string.Empty;
    public bool SkipByDefault { get; init; }
    public string[] ExpectedNo { get; init; } = [];
    public ScenarioAction[] SetupActions { get; init; } = [];
    public ScenarioAction[] TeardownActions { get; init; } = [];
    public ScenarioAction? ClearBeforeEachPoint { get; init; }
    public TestPoint[] Points { get; init; } = [];
}

public sealed class ScenarioAction
{
    public string Action { get; init; } = string.Empty;
    public int? X { get; init; }
    public int? Y { get; init; }
    public string? Key { get; init; }
    public string? Bookmark { get; init; }
    public string? Marker { get; init; }
    public int? WaitMs { get; init; }
    public CropRegion? Crop { get; init; }
    public bool RequireChange { get; init; }
    public int RepeatCount { get; init; } = 1;
    public ScenarioAction[] Actions { get; init; } = [];
}

public sealed class TestPoint
{
    public string Id { get; init; } = string.Empty;
    public string Action { get; init; } = string.Empty;
    public int? X { get; init; }
    public int? Y { get; init; }
    public int? WaitMs { get; init; }
    public CropRegion? Crop { get; init; }
    public bool SkipClear { get; init; }
    public bool AllowUnchanged { get; init; }
}

public sealed record CropRegion(int X, int Y, int Width, int Height);
