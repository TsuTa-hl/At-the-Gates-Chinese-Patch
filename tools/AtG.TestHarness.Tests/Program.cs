using AtG.TestHarness;

var tests = new (string Name, Func<Task> Body)[]
{
    ("Adaptive wait stops after two stable frames", AdaptiveWaitStopsEarly),
    ("Adaptive wait requires a change from the pre-action baseline", AdaptiveWaitRequiresChange),
    ("Session planner deduplicates interface points", SessionPlannerDeduplicates),
    ("Evidence policy keeps full frames only for transitions and failures", EvidencePolicyIsCompact),
    ("Coordinates scale from the canonical 2560 by 1440 window", CoordinatesScale),
    ("Window handle recovery replaces a stale handle", WindowHandleRecoveryReplacesStaleHandle),
    ("Session executor uses one driver and adaptive waits", SessionExecutorUsesOneDriver),
    ("Capture-only points do not wait for a changing frame to stabilize", CaptureOnlySkipsAdaptiveWait),
    ("Owned session launches and sets up exactly once", OwnedSessionLaunchesAndSetsUpOnce),
    ("Program log waiter blocks until the requested marker appears", ProgramLogWaiterBlocksUntilMarker),
    ("Program log probe ignores markers before its bookmark", ProgramLogProbeIgnoresExistingMarker),
    ("Session planner groups shared setup into one state", SessionPlannerGroupsSharedState),
    ("Session planner preserves repeated actions inside one setup sequence", SessionPlannerPreservesRepeatedSetupActions),
    ("Session executor runs setup and teardown around state points", SessionExecutorRunsStateActions),
    ("A changed state action may proceed even while animation remains unstable", ChangedStateActionMayRemainUnstable),
    ("Session executor can wait for a program-log marker after a named bookmark", SessionExecutorWaitsForBookmarkedProgramLog),
    ("Session executor repeats a bounded setup action group", SessionExecutorRepeatsActionGroup),
    ("Session executor records memory around each repeat iteration", SessionExecutorRecordsRepeatMemory),
    ("Fixed-save preparation promotes and restores the requested save", FixedSavePreparationPromotesAndRestores),
    ("Game setup modes use distinct ready markers", GameSetupModesUseDistinctReadyMarkers),
    ("Per-point clear actions honor nested-hover opt out", PerPointClearHonorsNestedHoverOptOut),
    ("Fixed-save requirement uses the machine-readable flag only", FixedSaveRequirementUsesExplicitFlag),
    ("Rendered-text probe fails a point on forbidden visible text", RenderedTextProbeFindsForbiddenText),
    ("Owned session forwards its rendered-text probe", OwnedSessionForwardsTextProbe),
    ("Owned session enables runtime text tracing only when requested", OwnedSessionTextTraceIsOptIn),
    ("A point that never changes the UI fails instead of passing", TimedOutActionFails),
    ("An explicitly idempotent point can pass without a UI change", IdempotentActionCanPass),
    ("Rendered text filtering ignores unrelated screen regions", RenderedTextFilteringUsesPointRegion),
};
var failures = 0;
foreach (var test in tests)
{
    try { await test.Body(); Console.WriteLine($"PASS {test.Name}"); }
    catch (Exception ex) { failures++; Console.Error.WriteLine($"FAIL {test.Name}: {ex.Message}"); }
}
return failures == 0 ? 0 : 1;

static async Task AdaptiveWaitStopsEarly()
{
    var clock = new FakeClock();
    var values = new Queue<string>(["empty", "tooltip", "tooltip"]);
    var result = await AdaptiveWaiter.WaitForStableAsync(
        _ => Task.FromResult(values.Dequeue()),
        maximumWaitMs: 3000,
        pollIntervalMs: 100,
        clock: clock);
    Equal(3, result.PollCount);
    Equal(200L, result.ElapsedMilliseconds);
    True(!result.TimedOut);
}

static Task OwnedSessionTextTraceIsOptIn()
{
    using var defaultOwner = new Win32GameSessionOwner(Path.GetTempPath());
    True(defaultOwner.TextProbe is null);
    var defaultStartInfo = Win32GameSessionOwner.CreateStartInfo(Path.GetTempPath(), enableTextTrace: false);
    True(!defaultStartInfo.EnvironmentVariables.ContainsKey("ATG_RUNTIME_TEXT_TRACE"));

    using var tracedOwner = new Win32GameSessionOwner(Path.GetTempPath(), enableTextTrace: true);
    True(tracedOwner.TextProbe is JsonlRenderTextProbe);
    var tracedStartInfo = Win32GameSessionOwner.CreateStartInfo(Path.GetTempPath(), enableTextTrace: true);
    Equal("1", tracedStartInfo.EnvironmentVariables["ATG_RUNTIME_TEXT_TRACE"]);
    return Task.CompletedTask;
}

static async Task AdaptiveWaitRequiresChange()
{
    var clock = new FakeClock();
    var values = new Queue<string>(["background", "background", "tooltip", "tooltip"]);
    var result = await AdaptiveWaiter.WaitForStableAsync(
        _ => Task.FromResult(values.Dequeue()),
        baselineFingerprint: "background",
        requireChangeFromBaseline: true,
        maximumWaitMs: 3000,
        pollIntervalMs: 100,
        clock: clock);
    Equal("tooltip", result.Fingerprint);
    Equal(4, result.PollCount);
    Equal(300L, result.ElapsedMilliseconds);
}

static Task SessionPlannerDeduplicates()
{
    var point = new TestPoint { Id = "level", Action = "HoverAndCapture", X = 10, Y = 20 };
    var scenarios = new[]
    {
        new TestScenario { Id = "a", Interface = "Clan", Setup = "Load fixed save", RequiresFixedSave = true, Points = [point] },
        new TestScenario { Id = "b", Interface = "Clan", Setup = "Load fixed save", Points = [point] },
    };
    var plan = SessionPlanner.Create(scenarios);
    True(plan.LaunchGameOnce);
    True(plan.LoadFixedSaveOnce);
    Equal(1, plan.Points.Count);
    Equal(1, plan.StateTransitions.Count);
    return Task.CompletedTask;
}

static Task EvidencePolicyIsCompact()
{
    var crop = new CropRegion(0, 0, 100, 100);
    Equal(EvidenceKind.Crop, EvidencePolicy.Select(false, false, crop));
    Equal(EvidenceKind.FullWindow, EvidencePolicy.Select(true, false, crop));
    Equal(EvidenceKind.FullWindow, EvidencePolicy.Select(false, true, crop));
    return Task.CompletedTask;
}

static Task CoordinatesScale()
{
    Equal((960, 540), CoordinateTransform.Scale(1280, 720, 1920, 1080));
    return Task.CompletedTask;
}

static Task WindowHandleRecoveryReplacesStaleHandle()
{
    var stale = new IntPtr(1);
    var replacement = new IntPtr(2);
    Equal(replacement, WindowHandleRecovery.Select(
        stale, handle => handle == replacement, () => replacement));
    Equal(replacement, WindowHandleRecovery.Select(
        replacement, handle => handle == replacement, () => IntPtr.Zero));
    return Task.CompletedTask;
}

static async Task SessionExecutorUsesOneDriver()
{
    using var temp = new TempDirectory();
    using var driver = new FakeWindowDriver();
    var scenario = new TestScenario
    {
        Id = "hover",
        Interface = "HUD",
        Points = [new TestPoint { Id = "one", Action = "HoverAndCapture", X = 100, Y = 100, WaitMs = 3000 }],
    };
    var result = await SessionExecutor.ExecuteAsync(
        SessionPlanner.Create([scenario]), driver, temp.Path, new ScenarioPolicy());
    Equal(1, result.Points.Count);
    Equal(1, driver.MoveCount);
    Equal(1, driver.CaptureCount);
    True(result.Points[0].DurationMs < 3000);
}

static async Task CaptureOnlySkipsAdaptiveWait()
{
    using var temp = new TempDirectory();
    using var driver = new ChangingWindowDriver();
    var scenario = new TestScenario
    {
        Id = "capture", Interface = "HUD",
        Points = [new TestPoint { Id = "frame", Action = "CaptureOnly" }],
    };

    var result = await SessionExecutor.ExecuteAsync(
        SessionPlanner.Create([scenario]), driver, temp.Path, new ScenarioPolicy());

    Equal(0, driver.FingerprintReadCount);
    True(!result.Points[0].WaitTimedOut);
    Equal("Passed", result.Points[0].Status);
}

static async Task OwnedSessionLaunchesAndSetsUpOnce()
{
    using var temp = new TempDirectory();
    using var owner = new FakeGameSessionOwner();
    var scenario = new TestScenario
    {
        Id = "owned",
        Interface = "HUD",
        Points = [new TestPoint { Id = "one", Action = "CaptureOnly", WaitMs = 100 }],
    };

    var result = await OwnedSessionExecutor.ExecuteAsync(
        SessionPlanner.Create([scenario]), owner, GameSetupMode.NewGame,
        temp.Path, new ScenarioPolicy());

    Equal(1, owner.StartCount);
    Equal(1, owner.SetupCount);
    Equal(GameSetupMode.NewGame, owner.LastSetupMode);
    Equal(1, owner.DisposeCount);
    Equal(1, result.Points.Count);
}

static async Task ProgramLogWaiterBlocksUntilMarker()
{
    using var temp = new TempDirectory();
    var logPath = System.IO.Path.Combine(temp.Path, "Program.AtGLog");
    await File.WriteAllTextAsync(logPath, "Main Menu - Init()\n");

    var waiting = ProgramLogWaiter.WaitForMarkerAsync(
        logPath, "XML          - Complete", TimeSpan.FromSeconds(2),
        TimeSpan.FromMilliseconds(10), CancellationToken.None);
    await Task.Delay(30);
    True(!waiting.IsCompleted);

    await File.AppendAllTextAsync(logPath, "XML          - Complete\n");
    True(await waiting);
}

static async Task ProgramLogProbeIgnoresExistingMarker()
{
    using var temp = new TempDirectory();
    var logPath = System.IO.Path.Combine(temp.Path, "Program.AtGLog");
    await File.WriteAllTextAsync(logPath, "World Screen - Children Initialized\n");
    var probe = new FileProgramLogProbe(logPath, TimeSpan.FromMilliseconds(10));
    var bookmark = probe.Bookmark();

    var waiting = probe.WaitForMarkerAfterAsync(
        bookmark, "World Screen - Children Initialized",
        TimeSpan.FromSeconds(2), CancellationToken.None);
    await Task.Delay(30);
    True(!waiting.IsCompleted);

    await File.AppendAllTextAsync(logPath, "World Screen - Children Initialized\n");
    True(await waiting);
}

static Task SessionPlannerGroupsSharedState()
{
    var setup = new ScenarioAction { Action = "Click", X = 100, Y = 200 };
    var teardown = new ScenarioAction { Action = "Key", Key = "Escape" };
    var scenarios = new[]
    {
        new TestScenario
        {
            Id = "one", Interface = "Knowledge", StateId = "knowledge",
            SetupActions = [setup], TeardownActions = [teardown],
            Points = [new TestPoint { Id = "a", Action = "CaptureOnly" }],
        },
        new TestScenario
        {
            Id = "two", Interface = "Knowledge", StateId = "knowledge",
            SetupActions = [setup], TeardownActions = [teardown],
            Points = [new TestPoint { Id = "b", Action = "CaptureOnly" }],
        },
    };

    var plan = SessionPlanner.Create(scenarios);
    Equal(1, plan.States.Count);
    Equal(1, plan.States[0].SetupActions.Count);
    Equal(2, plan.States[0].Points.Count);
    Equal(1, plan.States[0].TeardownActions.Count);
    return Task.CompletedTask;
}

static Task SessionPlannerPreservesRepeatedSetupActions()
{
    var repeated = new ScenarioAction { Action = "Key", Key = "Escape" };
    var scenario = new TestScenario
    {
        Id = "repeat", Interface = "Pause Menu", StateId = "reload",
        SetupActions = [repeated, repeated],
        Points = [new TestPoint { Id = "loaded", Action = "CaptureOnly" }],
    };

    var plan = SessionPlanner.Create([scenario]);
    Equal(2, plan.States[0].SetupActions.Count);
    return Task.CompletedTask;
}

static async Task SessionExecutorRunsStateActions()
{
    using var temp = new TempDirectory();
    using var driver = new FakeWindowDriver();
    var scenario = new TestScenario
    {
        Id = "state", Interface = "Clan", StateId = "clan",
        SetupActions = [new ScenarioAction { Action = "Click", X = 10, Y = 20, WaitMs = 300 }],
        TeardownActions = [new ScenarioAction { Action = "Key", Key = "Escape", WaitMs = 300 }],
        Points = [new TestPoint { Id = "body", Action = "CaptureOnly", WaitMs = 100 }],
    };

    var result = await SessionExecutor.ExecuteAsync(
        SessionPlanner.Create([scenario]), driver, temp.Path, new ScenarioPolicy());

    Equal(1, driver.ClickCount);
    Equal(1, driver.KeyCount);
    Equal("Escape", driver.LastKey);
    Equal(1, result.Points.Count);
}

static async Task ChangedStateActionMayRemainUnstable()
{
    using var temp = new TempDirectory();
    using var driver = new ChangingWindowDriver();
    var scenario = new TestScenario
    {
        Id = "animated-state", Interface = "Pause Menu", StateId = "pause",
        SetupActions =
        [
            new ScenarioAction
            {
                Action = "Key", Key = "Escape", WaitMs = 200, RequireChange = true,
            },
        ],
        Points = [new TestPoint { Id = "menu", Action = "CaptureOnly" }],
    };

    var result = await SessionExecutor.ExecuteAsync(
        SessionPlanner.Create([scenario]), driver, temp.Path, new ScenarioPolicy());
    Equal("Passed", result.Points[0].Status);
}

static async Task SessionExecutorWaitsForBookmarkedProgramLog()
{
    using var temp = new TempDirectory();
    using var driver = new FakeWindowDriver();
    var probe = new FakeProgramLogProbe();
    var scenario = new TestScenario
    {
        Id = "reload", Interface = "Pause Menu", StateId = "reload",
        SetupActions =
        [
            new ScenarioAction { Action = "BookmarkProgramLog", Bookmark = "reload-1" },
            new ScenarioAction
            {
                Action = "WaitForProgramLogMarker", Bookmark = "reload-1",
                Marker = "World Screen - Children Initialized", WaitMs = 45000,
            },
        ],
        Points = [new TestPoint { Id = "loaded", Action = "CaptureOnly" }],
    };

    var result = await SessionExecutor.ExecuteAsync(
        SessionPlanner.Create([scenario]), driver, temp.Path, new ScenarioPolicy(),
        programLogProbe: probe);

    Equal(1, probe.BookmarkCount);
    Equal(1, probe.WaitCount);
    Equal(45000, probe.LastTimeoutMs);
    Equal("World Screen - Children Initialized", probe.LastMarker);
    Equal("Passed", result.Points[0].Status);
}

static async Task SessionExecutorRepeatsActionGroup()
{
    using var temp = new TempDirectory();
    using var driver = new FakeWindowDriver();
    var scenario = new TestScenario
    {
        Id = "repeat-group", Interface = "Pause Menu", StateId = "reload",
        SetupActions =
        [
            new ScenarioAction
            {
                Action = "Repeat", RepeatCount = 3,
                Actions =
                [
                    new ScenarioAction { Action = "Key", Key = "Escape" },
                    new ScenarioAction { Action = "Click", X = 100, Y = 200 },
                ],
            },
        ],
        Points = [new TestPoint { Id = "loaded", Action = "CaptureOnly" }],
    };

    await SessionExecutor.ExecuteAsync(
        SessionPlanner.Create([scenario]), driver, temp.Path, new ScenarioPolicy());

    Equal(3, driver.KeyCount);
    Equal(3, driver.ClickCount);
}

static async Task SessionExecutorRecordsRepeatMemory()
{
    using var temp = new TempDirectory();
    using var driver = new FakeWindowDriver();
    var probe = new FakeProcessMemoryProbe();
    var scenario = new TestScenario
    {
        Id = "memory-repeat", Interface = "Pause Menu", StateId = "reload",
        SetupActions =
        [
            new ScenarioAction
            {
                Action = "Repeat", RepeatCount = 2,
                Actions =
                [
                    new ScenarioAction { Action = "Key", Key = "Escape" },
                ],
            },
        ],
        Points = [new TestPoint { Id = "loaded", Action = "CaptureOnly" }],
    };

    var result = await SessionExecutor.ExecuteAsync(
        SessionPlanner.Create([scenario]), driver, temp.Path, new ScenarioPolicy(),
        processMemoryProbe: probe);

    True(result.MemorySamples.Any(sample =>
        sample.Label.Contains("repeat-1", StringComparison.Ordinal)));
    True(result.MemorySamples.Any(sample =>
        sample.Label.Contains("repeat-2", StringComparison.Ordinal)));
    True(result.MemorySamples.All(sample => sample.PrivateBytes > 0));
}

static Task FixedSavePreparationPromotesAndRestores()
{
    using var temp = new TempDirectory();
    var saveDirectory = System.IO.Path.Combine(temp.Path, "Saved Games");
    Directory.CreateDirectory(saveDirectory);
    var target = System.IO.Path.Combine(saveDirectory, "Quicksave.AtGSave");
    var other = System.IO.Path.Combine(saveDirectory, "Other.AtGSave");
    File.WriteAllText(target, "target");
    File.WriteAllText(other, "other");
    var originalTargetTime = DateTime.UtcNow.AddDays(-3);
    File.SetLastWriteTimeUtc(target, originalTargetTime);
    File.SetLastWriteTimeUtc(other, DateTime.UtcNow.AddDays(-1));

    using (SaveSelectionLease.Promote(saveDirectory, "Quicksave.AtGSave"))
        True(File.GetLastWriteTimeUtc(target) > File.GetLastWriteTimeUtc(other));

    Equal(originalTargetTime, File.GetLastWriteTimeUtc(target));
    return Task.CompletedTask;
}

static Task GameSetupModesUseDistinctReadyMarkers()
{
    Equal("Controller   - Giving Control to Human",
        GameSetupMarkers.ReadyMarker(GameSetupMode.NewGame));
    Equal("World Screen - Children Initialized",
        GameSetupMarkers.ReadyMarker(GameSetupMode.FixedSave));
    return Task.CompletedTask;
}

static async Task PerPointClearHonorsNestedHoverOptOut()
{
    using var temp = new TempDirectory();
    using var driver = new FakeWindowDriver();
    var scenario = new TestScenario
    {
        Id = "nested", Interface = "Clan", StateId = "clan",
        ClearBeforeEachPoint = new ScenarioAction { X = 500, Y = 500, WaitMs = 100 },
        Points =
        [
            new TestPoint { Id = "parent", Action = "CaptureOnly", WaitMs = 100 },
            new TestPoint { Id = "nested", Action = "CaptureOnly", WaitMs = 100, SkipClear = true },
        ],
    };

    await SessionExecutor.ExecuteAsync(
        SessionPlanner.Create([scenario]), driver, temp.Path, new ScenarioPolicy());
    Equal(1, driver.MoveCount);
}

static Task FixedSaveRequirementUsesExplicitFlag()
{
    var plan = SessionPlanner.Create(
    [
        new TestScenario
        {
            Id = "optional", Interface = "HUD",
            Setup = "Load a fixed save or enter a new game.",
            RequiresFixedSave = false,
            Points = [new TestPoint { Id = "capture", Action = "CaptureOnly" }],
        },
    ]);
    True(!plan.LoadFixedSaveOnce);
    return Task.CompletedTask;
}

static async Task RenderedTextProbeFindsForbiddenText()
{
    using var temp = new TempDirectory();
    using var driver = new FakeWindowDriver();
    var probe = new FakeRenderTextProbe("已发现 TEXT.Name.Resource.Fame:PLURAL");
    var scenario = new TestScenario
    {
        Id = "raw-key", Interface = "HUD", StateId = "hud",
        ExpectedNo = ["TEXT.", ":PLURAL"],
        Points = [new TestPoint { Id = "hover", Action = "CaptureOnly", WaitMs = 100 }],
    };

    var result = await SessionExecutor.ExecuteAsync(
        SessionPlanner.Create([scenario]), driver, temp.Path, new ScenarioPolicy(),
        textProbe: probe);

    Equal("Failed", result.Points[0].Status);
    var error = result.Points[0].Error ?? string.Empty;
    True(error.Contains("TEXT.", StringComparison.Ordinal));
    True(error.Contains(":PLURAL", StringComparison.Ordinal));
}

static async Task OwnedSessionForwardsTextProbe()
{
    using var temp = new TempDirectory();
    using var owner = new FakeGameSessionOwner(new FakeRenderTextProbe("visible raw-key"));
    var scenario = new TestScenario
    {
        Id = "owned-trace", Interface = "HUD", StateId = "hud",
        ExpectedNo = ["raw-key"],
        Points = [new TestPoint { Id = "capture", Action = "CaptureOnly", WaitMs = 100 }],
    };

    var result = await OwnedSessionExecutor.ExecuteAsync(
        SessionPlanner.Create([scenario]), owner, GameSetupMode.MainMenu,
        temp.Path, new ScenarioPolicy());
    Equal("Failed", result.Points[0].Status);
}

static async Task TimedOutActionFails()
{
    using var temp = new TempDirectory();
    using var driver = new ConstantWindowDriver();
    var scenario = new TestScenario
    {
        Id = "missed-click", Interface = "HUD", StateId = "hud",
        Points =
        [
            new TestPoint { Id = "target", Action = "ClickAndCapture", X = 10, Y = 20, WaitMs = 200 },
        ],
    };
    var result = await SessionExecutor.ExecuteAsync(
        SessionPlanner.Create([scenario]), driver, temp.Path, new ScenarioPolicy());
    Equal("Failed", result.Points[0].Status);
    True(result.Points[0].WaitTimedOut);
}

static async Task IdempotentActionCanPass()
{
    using var temp = new TempDirectory();
    using var driver = new ConstantWindowDriver();
    var scenario = new TestScenario
    {
        Id = "idempotent-click", Interface = "HUD", StateId = "hud",
        Points =
        [
            new TestPoint
            {
                Id = "already-selected", Action = "ClickAndCapture", X = 10, Y = 20,
                WaitMs = 200, AllowUnchanged = true,
            },
        ],
    };
    var result = await SessionExecutor.ExecuteAsync(
        SessionPlanner.Create([scenario]), driver, temp.Path, new ScenarioPolicy());
    Equal("Passed", result.Points[0].Status);
    True(!result.Points[0].WaitTimedOut);
}

static Task RenderedTextFilteringUsesPointRegion()
{
    var region = new CropRegion(700, 0, 500, 250);
    var observations = new[]
    {
        new RenderedTextObservation("draw", "氏族当前职业。", 820, 60, 120, 20),
        new RenderedTextObservation("draw", "Clan Landbert 加入了部族！", 1700, 700, 300, 20),
        new RenderedTextObservation("measure", "Clan hidden measure", null, null, 100, 20),
    };
    var visible = RenderedTextFilter.InRegion(observations, region, 2560, 1440, 2560, 1440);
    Equal(1, visible.Count);
    Equal("氏族当前职业。", visible[0].Text);
    return Task.CompletedTask;
}

static void True(bool value) { if (!value) throw new InvalidOperationException("Expected true."); }
static void Equal<T>(T expected, T actual)
{
    if (!EqualityComparer<T>.Default.Equals(expected, actual))
        throw new InvalidOperationException($"Expected '{expected}', actual '{actual}'.");
}

sealed class FakeClock : IWaitClock
{
    public long ElapsedMilliseconds { get; private set; }
    public Task DelayAsync(int milliseconds, CancellationToken cancellationToken)
    {
        ElapsedMilliseconds += milliseconds;
        return Task.CompletedTask;
    }
}

sealed class FakeWindowDriver : IWindowDriver
{
    private int _operationCount;
    public int ClientWidth => 2560;
    public int ClientHeight => 1440;
    public int MoveCount { get; private set; }
    public int ClickCount { get; private set; }
    public int KeyCount { get; private set; }
    public string? LastKey { get; private set; }
    public int CaptureCount { get; private set; }
    public void Move(int referenceX, int referenceY)
    {
        MoveCount++;
        _operationCount++;
    }
    public void Click(int referenceX, int referenceY)
    {
        ClickCount++;
        _operationCount++;
    }
    public void KeyPress(string key)
    {
        KeyCount++;
        LastKey = key;
        _operationCount++;
    }
    public string ReadFingerprint(CropRegion? referenceRegion) => _operationCount.ToString();
    public void Capture(string outputPath, CropRegion? referenceRegion, bool markCursor)
    {
        CaptureCount++;
        File.WriteAllText(outputPath, "evidence");
    }
    public void Dispose() { }
}

sealed class ConstantWindowDriver : IWindowDriver
{
    public int ClientWidth => 2560;
    public int ClientHeight => 1440;
    public void Move(int referenceX, int referenceY) { }
    public void Click(int referenceX, int referenceY) { }
    public void KeyPress(string key) { }
    public string ReadFingerprint(CropRegion? referenceRegion) => "unchanged";
    public void Capture(string outputPath, CropRegion? referenceRegion, bool markCursor) =>
        File.WriteAllText(outputPath, "evidence");
    public void Dispose() { }
}

sealed class ChangingWindowDriver : IWindowDriver
{
    public int ClientWidth => 2560;
    public int ClientHeight => 1440;
    public int FingerprintReadCount { get; private set; }
    public void Move(int referenceX, int referenceY) { }
    public void Click(int referenceX, int referenceY) { }
    public void KeyPress(string key) { }
    public string ReadFingerprint(CropRegion? referenceRegion) =>
        (++FingerprintReadCount).ToString();
    public void Capture(string outputPath, CropRegion? referenceRegion, bool markCursor) =>
        File.WriteAllText(outputPath, "evidence");
    public void Dispose() { }
}

sealed class FakeGameSessionOwner : IGameSessionOwner
{
    private readonly FakeWindowDriver _driver = new();
    public FakeGameSessionOwner(IRenderTextProbe? textProbe = null) => TextProbe = textProbe;
    public IRenderTextProbe? TextProbe { get; }
    public IProgramLogProbe? ProgramLogProbe => null;
    public IProcessMemoryProbe? ProcessMemoryProbe => null;
    public int StartCount { get; private set; }
    public int SetupCount { get; private set; }
    public int DisposeCount { get; private set; }
    public GameSetupMode LastSetupMode { get; private set; }
    public Task<IWindowDriver> StartAsync(CancellationToken cancellationToken)
    {
        StartCount++;
        return Task.FromResult<IWindowDriver>(_driver);
    }
    public Task SetupAsync(GameSetupMode mode, IWindowDriver driver, CancellationToken cancellationToken)
    {
        SetupCount++;
        LastSetupMode = mode;
        return Task.CompletedTask;
    }
    public void Dispose()
    {
        DisposeCount++;
        _driver.Dispose();
    }
}

sealed class FakeRenderTextProbe : IRenderTextProbe
{
    private readonly RenderedTextObservation[] _text;
    public FakeRenderTextProbe(params string[] text) => _text = text
        .Select(value => new RenderedTextObservation("draw", value, null, null, null, null))
        .ToArray();
    public long Bookmark() => 0;
    public IReadOnlyList<RenderedTextObservation> ReadSince(long bookmark) => _text;
}

sealed class FakeProgramLogProbe : IProgramLogProbe
{
    public int BookmarkCount { get; private set; }
    public int WaitCount { get; private set; }
    public int LastTimeoutMs { get; private set; }
    public string? LastMarker { get; private set; }
    public long Bookmark()
    {
        BookmarkCount++;
        return 42;
    }
    public Task<bool> WaitForMarkerAfterAsync(
        long bookmark, string marker, TimeSpan timeout,
        CancellationToken cancellationToken)
    {
        if (bookmark != 42)
            throw new InvalidOperationException($"Expected bookmark 42, actual {bookmark}.");
        WaitCount++;
        LastTimeoutMs = (int)timeout.TotalMilliseconds;
        LastMarker = marker;
        return Task.FromResult(true);
    }
}

sealed class FakeProcessMemoryProbe : IProcessMemoryProbe
{
    private long _next = 1024;
    public ProcessMemoryCounters Capture()
    {
        var value = _next++;
        return new ProcessMemoryCounters(value, value, value, value, 1);
    }
}

sealed class TempDirectory : IDisposable
{
    public string Path { get; } = System.IO.Path.Combine(
        System.IO.Path.GetTempPath(), "atg-harness-tests", Guid.NewGuid().ToString("N"));
    public TempDirectory() => Directory.CreateDirectory(Path);
    public void Dispose() { if (Directory.Exists(Path)) Directory.Delete(Path, true); }
}
