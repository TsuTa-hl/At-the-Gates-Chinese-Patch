using System.Diagnostics;
using System.Text.Json;

namespace AtG.TestHarness;

public sealed class Win32GameSessionOwner : IGameSessionOwner
{
    private readonly string _gamePath;
    private readonly TimeSpan _windowTimeout;
    private readonly TimeSpan _setupTimeout;
    private readonly string? _saveName;
    private readonly string _tracePath;
    private readonly bool _enableTextTrace;
    private readonly string _performancePath;
    private readonly bool _enablePerformanceTrace;
    private readonly string _glyphMode;
    private readonly bool _disableWarmset;
    private readonly bool _saveAfterNewGame;
    private readonly string? _saveEvidencePath;
    private readonly string? _textTraceEvidencePath;
    private readonly string? _performanceEvidencePath;
    private readonly string _programLogPath;
    private Process? _process;
    private IWindowDriver? _driver;
    private SaveSelectionLease? _saveSelectionLease;
    private Dictionary<string, SaveSignature>? _newGameSaveBaseline;
    private DateTime _newGameSaveStartedAtUtc;
    private bool _sessionCompleted;
    private DateTime _launchUtc;
    private long _launchLogBookmark;
    private bool _disposed;

    public Win32GameSessionOwner(
        string gamePath,
        TimeSpan? windowTimeout = null,
        TimeSpan? setupTimeout = null,
        string? saveName = null,
        bool enableTextTrace = false,
        bool enablePerformanceTrace = false,
        string glyphMode = "Budgeted",
        bool disableWarmset = false,
        bool saveAfterNewGame = false,
        string? saveEvidencePath = null,
        string? textTraceEvidencePath = null,
        string? performanceEvidencePath = null)
    {
        _gamePath = Path.GetFullPath(gamePath);
        _windowTimeout = windowTimeout ?? TimeSpan.FromSeconds(25);
        _setupTimeout = setupTimeout ?? TimeSpan.FromSeconds(45);
        _saveName = saveName;
        _enableTextTrace = enableTextTrace;
        _enablePerformanceTrace = enablePerformanceTrace;
        _glyphMode = NormalizeGlyphMode(glyphMode);
        _disableWarmset = disableWarmset;
        _saveAfterNewGame = saveAfterNewGame;
        _saveEvidencePath = saveEvidencePath;
        _textTraceEvidencePath = textTraceEvidencePath;
        _performanceEvidencePath = performanceEvidencePath;
        _tracePath = Path.Combine(_gamePath, "AtG.RuntimeText.jsonl");
        _performancePath = Path.Combine(_gamePath, "AtG.RuntimeText.Perf.jsonl");
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

        _launchLogBookmark = ProgramLogProbe?.Bookmark() ?? 0;
        _launchUtc = DateTime.UtcNow;
        if (_enableTextTrace && File.Exists(_tracePath)) File.Delete(_tracePath);
        if (_enablePerformanceTrace && File.Exists(_performancePath)) File.Delete(_performancePath);
        var existingIds = Process.GetProcessesByName("At The Gates")
            .Select(process => process.Id)
            .ToHashSet();
        using (var launcher = Process.Start(CreatePowerShellLaunchInfo(
                   _gamePath,
                   _enableTextTrace,
                   _enablePerformanceTrace,
                   _glyphMode,
                   _disableWarmset))
            ?? throw new InvalidOperationException("Unable to start the PowerShell game launcher."))
        {
            await launcher.WaitForExitAsync(cancellationToken);
        }

        var deadline = DateTime.UtcNow + _windowTimeout;
        while (DateTime.UtcNow < deadline)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (_process is null)
            {
                _process = Process.GetProcessesByName("At The Gates")
                    .FirstOrDefault(process =>
                    {
                        try
                        {
                            process.Refresh();
                            return !existingIds.Contains(process.Id) && !process.HasExited;
                        }
                        catch
                        {
                            return false;
                        }
                    });
                if (_process is not null)
                    ProcessMemoryProbe = new SystemProcessMemoryProbe(_process);
            }

            if (_process is not null)
            {
                _process.Refresh();
                if (_process.HasExited)
                {
                    var exitCode = _process.ExitCode;
                    _process.Dispose();
                    _process = null;
                    throw new InvalidOperationException($"At the Gates exited before its window appeared (exit code {exitCode}).");
                }
                try
                {
                    _driver = new Win32WindowDriver("At The Gates", _process.Id);
                    return _driver;
                }
                catch (InvalidOperationException)
                {
                    // The process can exist before XNA creates its usable window.
                }
            }
            await Task.Delay(100, cancellationToken);
        }
        throw new TimeoutException("At the Gates window did not appear before the startup timeout.");
    }

    public static ProcessStartInfo CreateStartInfo(
        string gamePath,
        bool enableTextTrace,
        bool enablePerformanceTrace = false,
        string glyphMode = "Budgeted",
        bool disableWarmset = false)
    {
        var resolvedGamePath = Path.GetFullPath(gamePath);
        var startInfo = new ProcessStartInfo
        {
            FileName = Path.Combine(resolvedGamePath, "At The Gates.exe"),
            WorkingDirectory = resolvedGamePath,
            // XNA's Windows host needs the same ShellExecute launch path as the
            // supported PowerShell smoke test. Without it, the process can
            // exit before creating Program.AtGLog or a usable menu window.
            UseShellExecute = true,
        };
        ApplyRuntimeTextEnvironment(
            startInfo,
            enableTextTrace,
            enablePerformanceTrace,
            NormalizeGlyphMode(glyphMode),
            disableWarmset);
        return startInfo;
    }

    private static ProcessStartInfo CreatePowerShellLaunchInfo(
        string gamePath,
        bool enableTextTrace,
        bool enablePerformanceTrace,
        string glyphMode,
        bool disableWarmset)
    {
        var resolvedGamePath = Path.GetFullPath(gamePath);
        var powershellPath = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.System),
            "WindowsPowerShell",
            "v1.0",
            "powershell.exe");
        var command = $"Start-Process -FilePath {QuotePowerShell(Path.Combine(resolvedGamePath, "At The Gates.exe"))} " +
                      $"-WorkingDirectory {QuotePowerShell(resolvedGamePath)}";
        var startInfo = new ProcessStartInfo
        {
            FileName = powershellPath,
            UseShellExecute = false,
            CreateNoWindow = true,
        };
        startInfo.ArgumentList.Add("-NoProfile");
        startInfo.ArgumentList.Add("-ExecutionPolicy");
        startInfo.ArgumentList.Add("Bypass");
        startInfo.ArgumentList.Add("-Command");
        startInfo.ArgumentList.Add(command);
        ApplyRuntimeTextEnvironment(
            startInfo,
            enableTextTrace,
            enablePerformanceTrace,
            glyphMode,
            disableWarmset);
        return startInfo;
    }

    private static void ApplyRuntimeTextEnvironment(
        ProcessStartInfo startInfo,
        bool enableTextTrace,
        bool enablePerformanceTrace,
        string glyphMode,
        bool disableWarmset)
    {
        SetOptionalEnvironmentVariable(
            startInfo, "ATG_RUNTIME_TEXT_TRACE", enableTextTrace ? "1" : null);
        SetOptionalEnvironmentVariable(
            startInfo, "ATG_RUNTIME_TEXT_PERF", enablePerformanceTrace ? "1" : null);
        startInfo.EnvironmentVariables["ATG_RUNTIME_TEXT_GLYPH_MODE"] = glyphMode;
        startInfo.EnvironmentVariables["ATG_RUNTIME_TEXT_WARMSET"] =
            disableWarmset ? "0" : "1";
    }

    private static void SetOptionalEnvironmentVariable(
        ProcessStartInfo startInfo, string name, string? value)
    {
        if (value is null)
            startInfo.EnvironmentVariables.Remove(name);
        else
            startInfo.EnvironmentVariables[name] = value;
    }

    private static string NormalizeGlyphMode(string? glyphMode)
    {
        if (string.Equals(glyphMode, "Budgeted", StringComparison.OrdinalIgnoreCase))
            return "Budgeted";
        if (string.Equals(glyphMode, "LegacySync", StringComparison.OrdinalIgnoreCase))
            return "LegacySync";
        throw new ArgumentException(
            $"Unknown glyph mode '{glyphMode}'. Expected Budgeted or LegacySync.",
            nameof(glyphMode));
    }

    private static string QuotePowerShell(string value) =>
        "'" + value.Replace("'", "''", StringComparison.Ordinal) + "'";

    private static ProcessStartInfo CreateShellStartInfo(string gamePath)
    {
        var resolvedGamePath = Path.GetFullPath(gamePath);
        return new ProcessStartInfo
        {
            FileName = Path.Combine(resolvedGamePath, "At The Gates.exe"),
            WorkingDirectory = resolvedGamePath,
            UseShellExecute = true,
        };
    }

    public async Task SetupAsync(
        GameSetupMode mode,
        IWindowDriver driver,
        CancellationToken cancellationToken)
    {
        var menuReady = await WaitForMarkerOrWindowWarmupAsync(
            driver, "XML          - Complete", _windowTimeout,
            TimeSpan.FromSeconds(5), _launchLogBookmark, cancellationToken);
        EnsureGameIsAlive();
        if (!menuReady)
            throw new TimeoutException("The main menu did not become interactive before the startup timeout.");

        if (mode == GameSetupMode.MainMenu) return;
        if (mode == GameSetupMode.MainMenuWithFixedSave)
        {
            if (string.IsNullOrWhiteSpace(_saveName))
                throw new InvalidOperationException(
                    "Main-menu fixed-save setup requires --save-name or a scenario SaveName.");
            _saveSelectionLease = SaveSelectionLease.Promote(
                Path.Combine(_gamePath, "Saved Games"), _saveName);
            return;
        }
        var steps = mode == GameSetupMode.FixedSave
            ? FixedSaveSteps()
            : new[]
        {
            (X: 1280, Y: 714, DelayMs: 1200),
            (X: 1280, Y: 526, DelayMs: 1200),
            (X: 1280, Y: 654, DelayMs: 500),
        };
        // The ready marker must be produced by this setup operation. Reusing a
        // marker left in Program.AtGLog by a previous game made a main-menu
        // screenshot look like a completed new-game run.
        var setupLogBookmark = ProgramLogProbe?.Bookmark() ?? 0;
        // A new game writes its initial auto-save while the setup buttons are
        // being processed. Snapshot before the first click so that save is a
        // detectable artifact for later fixed-save reproduction.
        if (mode == GameSetupMode.NewGame && _saveAfterNewGame)
            BeginNewGameSaveCapture();
        foreach (var step in steps)
        {
            EnsureGameIsAlive();
            driver.Click(step.X, step.Y);
            await Task.Delay(step.DelayMs, cancellationToken);
        }

        var mainLoopReady = await WaitForSetupMarkerAsync(
            GameSetupMarkers.ReadyMarker(mode), setupLogBookmark,
            _setupTimeout, cancellationToken);
        EnsureGameIsAlive();
        if (!mainLoopReady)
            throw new TimeoutException($"{mode} setup did not reach the main loop before the timeout.");
        await Task.Delay(mode == GameSetupMode.FixedSave ? 1500 : 500, cancellationToken);
    }

    private async Task<bool> WaitForMarkerOrWindowWarmupAsync(
        IWindowDriver driver,
        string marker,
        TimeSpan timeout,
        TimeSpan fallbackWarmup,
        long logBookmark,
        CancellationToken cancellationToken)
    {
        var deadline = DateTime.UtcNow + timeout;
        var fallbackReadyAt = DateTime.UtcNow + fallbackWarmup;
        while (DateTime.UtcNow < deadline)
        {
            cancellationToken.ThrowIfCancellationRequested();
            EnsureGameIsAlive();

            if (ProgramLogProbe is not null && await ProgramLogProbe.WaitForMarkerAfterAsync(
                    logBookmark, marker, TimeSpan.Zero, cancellationToken))
                return true;

            if (DateTime.UtcNow >= fallbackReadyAt)
            {
                // Some launches expose a usable XNA window but never create
                // Program.AtGLog. The window driver is already attached, so
                // use a bounded warmup instead of treating that as a startup
                // failure. Later UI actions still verify the actual state.
                _ = driver.ClientWidth;
                return true;
            }

            await Task.Delay(100, cancellationToken);
        }

        return false;
    }

    private async Task<bool> WaitForSetupMarkerAsync(
        string marker,
        long logBookmark,
        TimeSpan timeout,
        CancellationToken cancellationToken)
    {
        if (ProgramLogProbe is null) return false;
        return await ProgramLogProbe.WaitForMarkerAfterAsync(
            logBookmark, marker, timeout, cancellationToken);
    }

    public async Task CompleteAsync(CancellationToken cancellationToken)
    {
        if (_sessionCompleted) return;
        _sessionCompleted = true;
        _driver?.Dispose();
        _driver = null;
        if (_process is not null)
        {
            try
            {
                _process.Refresh();
                if (!_process.HasExited)
                {
                    _process.CloseMainWindow();
                    var deadline = DateTime.UtcNow + TimeSpan.FromSeconds(5);
                    while (!_process.HasExited && DateTime.UtcNow < deadline)
                    {
                        cancellationToken.ThrowIfCancellationRequested();
                        await Task.Delay(100, cancellationToken);
                        _process.Refresh();
                    }
                    if (!_process.HasExited)
                        _process.Kill(entireProcessTree: true);
                }
            }
            catch
            {
                try { if (!_process.HasExited) _process.Kill(entireProcessTree: true); }
                catch { }
            }
        }

        CopyRuntimeEvidence(_tracePath, _textTraceEvidencePath, _enableTextTrace);
        CopyRuntimeEvidence(
            _performancePath, _performanceEvidencePath, _enablePerformanceTrace);

        if (_newGameSaveBaseline is not null)
            CaptureNewGameAutoSave();
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

    private void BeginNewGameSaveCapture()
    {
        var saveDirectory = Path.Combine(_gamePath, "Saved Games");
        Directory.CreateDirectory(saveDirectory);
        _newGameSaveBaseline = Directory.EnumerateFiles(saveDirectory, "*.AtGSave")
            .ToDictionary(path => Path.GetFileName(path)!, ReadSaveSignature, StringComparer.OrdinalIgnoreCase);
        _newGameSaveStartedAtUtc = DateTime.UtcNow;
    }

    private void CaptureNewGameAutoSave()
    {
        var saveDirectory = Path.Combine(_gamePath, "Saved Games");
        var baseline = _newGameSaveBaseline ?? throw new InvalidOperationException("New-game save capture was not initialized.");
        var changed = Directory.EnumerateFiles(saveDirectory, "*.AtGSave")
            .Select(path => new { Path = path, Signature = ReadSaveSignature(path) })
            .Where(candidate => !baseline.TryGetValue(Path.GetFileName(candidate.Path)!, out var existing) ||
                !existing.Equals(candidate.Signature))
            .OrderByDescending(candidate => candidate.Signature.LastWriteTimeUtc)
            .FirstOrDefault();
        if (changed is null)
        {
            WriteSaveEvidence(saveDirectory, null, _newGameSaveStartedAtUtc, null,
                "No saved game was created or updated while closing the new-game test session.");
            throw new InvalidOperationException("New-game test session did not preserve a reloadable saved game.");
        }

        WriteSaveEvidence(saveDirectory, Path.GetFileName(changed.Path), _newGameSaveStartedAtUtc, changed.Signature, null);
    }

    private void WriteSaveEvidence(
        string saveDirectory,
        string? saveName,
        DateTime startedAtUtc,
        SaveSignature? signature,
        string? error)
    {
        if (string.IsNullOrWhiteSpace(_saveEvidencePath)) return;
        var path = Path.GetFullPath(_saveEvidencePath);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        var evidence = new
        {
            SaveName = saveName,
            SaveDirectory = saveDirectory,
            SaveStartedAtUtc = startedAtUtc,
            SaveLastWriteTimeUtc = signature?.LastWriteTimeUtc,
            Length = signature?.Length,
            Error = error,
        };
        File.WriteAllText(path, JsonSerializer.Serialize(evidence, new JsonSerializerOptions { WriteIndented = true }));
    }

    private static SaveSignature ReadSaveSignature(string path)
    {
        var file = new FileInfo(path);
        return new SaveSignature(file.LastWriteTimeUtc, file.Length);
    }

    private static void CopyRuntimeEvidence(
        string sourcePath, string? destinationPath, bool enabled)
    {
        if (!enabled || string.IsNullOrWhiteSpace(destinationPath) ||
            !File.Exists(sourcePath))
            return;
        var resolvedDestination = Path.GetFullPath(destinationPath);
        Directory.CreateDirectory(Path.GetDirectoryName(resolvedDestination)!);
        File.Copy(sourcePath, resolvedDestination, overwrite: true);
    }

    private readonly record struct SaveSignature(DateTime LastWriteTimeUtc, long Length);
}
