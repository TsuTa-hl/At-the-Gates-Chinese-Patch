namespace AtG.TestHarness;

public enum GameSetupMode
{
    MainMenu,
    MainMenuWithFixedSave,
    NewGame,
    FixedSave,
}

public interface IGameSessionOwner : IDisposable
{
    IRenderTextProbe? TextProbe { get; }
    IProgramLogProbe? ProgramLogProbe { get; }
    IProcessMemoryProbe? ProcessMemoryProbe { get; }
    Task<IWindowDriver> StartAsync(CancellationToken cancellationToken);
    Task SetupAsync(GameSetupMode mode, IWindowDriver driver, CancellationToken cancellationToken);
    Task CompleteAsync(CancellationToken cancellationToken);
}

public static class OwnedSessionExecutor
{
    public static async Task<SessionResult> ExecuteAsync(
        TestSessionPlan plan,
        IGameSessionOwner owner,
        GameSetupMode setupMode,
        string outputDirectory,
        ScenarioPolicy policy,
        CancellationToken cancellationToken = default)
    {
        var results = await ExecutePassesAsync(
            plan, owner, setupMode, outputDirectory, policy, 1, cancellationToken);
        return results[0];
    }

    public static async Task<IReadOnlyList<SessionResult>> ExecutePassesAsync(
        TestSessionPlan plan,
        IGameSessionOwner owner,
        GameSetupMode setupMode,
        string outputDirectory,
        ScenarioPolicy policy,
        int passCount,
        CancellationToken cancellationToken = default)
    {
        if (passCount is < 1 or > 5)
            throw new ArgumentOutOfRangeException(
                nameof(passCount), "Pass count must be between one and five.");
        var results = new List<SessionResult>(passCount);
        try
        {
            var driver = await owner.StartAsync(cancellationToken);
            await owner.SetupAsync(setupMode, driver, cancellationToken);
            for (var pass = 1; pass <= passCount; pass++)
            {
                var passOutput = passCount == 1
                    ? outputDirectory
                    : Path.Combine(outputDirectory, $"pass-{pass}");
                results.Add(await SessionExecutor.ExecuteAsync(
                    plan, driver, passOutput, policy, cancellationToken,
                    owner.TextProbe, owner.ProgramLogProbe, owner.ProcessMemoryProbe));
            }
            return results;
        }
        finally
        {
            await owner.CompleteAsync(CancellationToken.None);
            owner.Dispose();
        }
    }
}
