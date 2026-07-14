namespace AtG.TestHarness;

public enum GameSetupMode
{
    MainMenu,
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
        try
        {
            var driver = await owner.StartAsync(cancellationToken);
            await owner.SetupAsync(setupMode, driver, cancellationToken);
            return await SessionExecutor.ExecuteAsync(
                plan, driver, outputDirectory, policy, cancellationToken,
                owner.TextProbe, owner.ProgramLogProbe, owner.ProcessMemoryProbe);
        }
        finally
        {
            owner.Dispose();
        }
    }
}
