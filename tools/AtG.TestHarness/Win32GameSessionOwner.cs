using System.Diagnostics;

namespace AtG.TestHarness;

public sealed class Win32GameSessionOwner : IGameSessionOwner
{
    private readonly string _gamePath;
    private readonly TimeSpan _windowTimeout;
    private readonly TimeSpan _setupTimeout;
    private readonly string? _saveName;
    private readonly string _tracePath;
    private readonly bool _enableTextTrace;
    private readonly string _programLogPath;
    private Process? _process;
    private IWindowDriver? _driver;
    private SaveSelectionLease? _saveSelectionLease;
    private DateTime _launchUtc;
    private bool _disposed;

    public Win32GameSessionOwner(
        string gamePath,
        TimeSpan? windowTimeout = null,
        TimeSpan? setupTimeout = null,
        string? saveName = null,
        bool enableTextTrace = false)
    {
        _gamePath = Path.GetFullPath(gamePath);
        _windowTimeout = windowTimeout ?? TimeSpan.FromSeconds(25);
        _setupTimeout = setupTimeout ?? TimeSpan.FromSeconds(45);
        _saveName = saveName;
        _enableTextTrace = enableTextTrace;
        _tracePath = Path.Combine(_gamePath, "AtG.RuntimeText.jsonl");
        _programLogPath = Path.Combine(_gamePath, "Logs", "Program.AtGLog");
        TextProbe = enableTextTrace ? new JsonlRenderTextProbe(_tracePath) : null;
        ProgramLogProbe = new FileProgramLogProbe(_programLogPath);
    }

    public IRenderTextProbe? TextProbe { get; }
    public IProgramLogProbe? ProgramLogProbe { get; }
    public IProcessMemoryProbe? ProcessMemoryProbe { get; private set; }

    public async Task<IWindowDriver> StartAsync(CancellationToken cancellationToken)
    {
        if (_process is not null) throw new InvalidOperationException("The game session has already started.");
        if (Process.GetProcessesByName("At The Gates").Length > 0)
            throw new InvalidOperationException("At the Gates is already running.");

        var executable = Path.Combine(_gamePath, "At The Gates.exe");
        if (!File.Exists(executable))
            throw new FileNotFoundException("Game executable not found.", executable);

        _launchUtc = DateTime.UtcNow;
        if (_enableTextTrace && File.Exists(_tracePath)) File.Delete(_tracePath);
        var startInfo = CreateStartInfo(_gamePath, _enableTextTrace);
        _process = Process.Start(startInfo)
            ?? throw new InvalidOperationException("Unable to start At the Gates.");
        ProcessMemoryProbe = new SystemProcessMemoryProbe(_process);

        var deadline = DateTime.UtcNow + _windowTimeout;
        while (DateTime.UtcNow < deadline)
        {
            cancellationToken.ThrowIfCancellationRequested();
            _process.Refresh();
            if (_process.HasExited)
                throw new InvalidOperationException($"At the Gates exited before its window appeared (exit code {_process.ExitCode}).");
            try
            {
                _driver = new Win32WindowDriver("At The Gates", _process.Id);
                return _driver;
            }
            catch (InvalidOperationException)
            {
                await Task.Delay(100, cancellationToken);
            }
        }
        throw new TimeoutException("At the Gates window did not appear before the startup timeout.");
    }

    public static ProcessStartInfo CreateStartInfo(string gamePath, bool enableTextTrace)
    {
        var resolvedGamePath = Path.GetFullPath(gamePath);
        var startInfo = new ProcessStartInfo
        {
            FileName = Path.Combine(resolvedGamePath, "At The Gates.exe"),
            WorkingDirectory = resolvedGamePath,
            UseShellExecute = false,
        };
        if (enableTextTrace)
            startInfo.EnvironmentVariables["ATG_RUNTIME_TEXT_TRACE"] = "1";
        return startInfo;
    }

    public async Task SetupAsync(
        GameSetupMode mode,
        IWindowDriver driver,
        CancellationToken cancellationToken)
    {
        var menuReady = await ProgramLogWaiter.WaitForMarkerAsync(
            _programLogPath, "XML          - Complete", _windowTimeout,
            TimeSpan.FromMilliseconds(100), cancellationToken, _launchUtc);
        EnsureGameIsAlive();
        if (!menuReady)
            throw new TimeoutException("The main menu did not become interactive before the startup timeout.");

        if (mode == GameSetupMode.MainMenu) return;
        var steps = mode == GameSetupMode.FixedSave
            ? FixedSaveSteps()
            : new[]
        {
            (X: 1280, Y: 714, DelayMs: 1200),
            (X: 1280, Y: 526, DelayMs: 1200),
            (X: 1280, Y: 654, DelayMs: 500),
        };
        foreach (var step in steps)
        {
            EnsureGameIsAlive();
            driver.Click(step.X, step.Y);
            await Task.Delay(step.DelayMs, cancellationToken);
        }

        var mainLoopReady = await ProgramLogWaiter.WaitForMarkerAsync(
            _programLogPath, GameSetupMarkers.ReadyMarker(mode), _setupTimeout,
            TimeSpan.FromMilliseconds(100), cancellationToken, _launchUtc);
        EnsureGameIsAlive();
        if (!mainLoopReady)
            throw new TimeoutException($"{mode} setup did not reach the main loop before the timeout.");
        await Task.Delay(mode == GameSetupMode.FixedSave ? 1500 : 500, cancellationToken);
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        _driver?.Dispose();
        if (_process is null) return;
        try
        {
            _process.Refresh();
            if (!_process.HasExited)
            {
                _process.CloseMainWindow();
                if (!_process.WaitForExit(1500)) _process.Kill(entireProcessTree: true);
            }
        }
        catch
        {
            try { if (!_process.HasExited) _process.Kill(entireProcessTree: true); }
            catch { }
        }
        finally
        {
            _process.Dispose();
            _saveSelectionLease?.Dispose();
        }
    }

    private void EnsureGameIsAlive()
    {
        if (_process is null) throw new InvalidOperationException("The game session has not started.");
        _process.Refresh();
        if (_process.HasExited)
            throw new InvalidOperationException($"At the Gates exited during setup (exit code {_process.ExitCode}).");
    }

    private (int X, int Y, int DelayMs)[] FixedSaveSteps()
    {
        if (string.IsNullOrWhiteSpace(_saveName))
            throw new InvalidOperationException("Fixed-save setup requires --save-name or a scenario SaveName.");
        _saveSelectionLease = SaveSelectionLease.Promote(
            Path.Combine(_gamePath, "Saved Games"), _saveName);
        return
        [
            (X: 1280, Y: 770, DelayMs: 900),
            (X: 1285, Y: 578, DelayMs: 500),
        ];
    }
}
