using System.Diagnostics;
using System.Text.Json;

namespace AtG.TestHarness;

public sealed record PointResult(
    string ScenarioId,
    string PointId,
    string Status,
    long DurationMs,
    string? EvidencePath,
    bool WaitTimedOut,
    string? Error);

public sealed record SessionResult(
    DateTime StartedAtUtc,
    long DurationMs,
    IReadOnlyList<PointResult> Points,
    IReadOnlyList<ProcessMemorySample> MemorySamples);

public static class SessionExecutor
{
    public static async Task<SessionResult> ExecuteAsync(
        TestSessionPlan plan,
        IWindowDriver driver,
        string outputDirectory,
        ScenarioPolicy policy,
        CancellationToken cancellationToken = default,
        IRenderTextProbe? textProbe = null,
        IProgramLogProbe? programLogProbe = null,
        IProcessMemoryProbe? processMemoryProbe = null)
    {
        Directory.CreateDirectory(outputDirectory);
        var started = DateTime.UtcNow;
        var sessionStopwatch = Stopwatch.StartNew();
        var results = new List<PointResult>();
        var memorySamples = new List<ProcessMemorySample>();
        var programLogBookmarks = new Dictionary<string, long>(StringComparer.OrdinalIgnoreCase);
        CaptureMemory("session:started", processMemoryProbe, memorySamples);

        foreach (var state in plan.States)
        {
            cancellationToken.ThrowIfCancellationRequested();
            try
            {
                for (var actionIndex = 0; actionIndex < state.SetupActions.Count; actionIndex++)
                    await ExecuteControlActionAsync(
                        state.SetupActions[actionIndex], driver, policy, cancellationToken,
                        programLogProbe, programLogBookmarks,
                        processMemoryProbe, memorySamples,
                        $"{state.Id}/setup-{actionIndex + 1}");

                var firstPoint = true;
                foreach (var planned in state.Points)
                {
                    if (planned.ClearBefore is not null)
                        await ExecuteControlActionAsync(
                            planned.ClearBefore, driver, policy, cancellationToken,
                            programLogProbe, programLogBookmarks,
                            processMemoryProbe, memorySamples,
                            $"{state.Id}/point-{planned.Point.Id}/clear");
                    results.Add(await ExecutePointAsync(
                        planned, driver, outputDirectory, policy, firstPoint,
                        cancellationToken, textProbe));
                    firstPoint = false;
                }
            }
            catch (Exception ex)
            {
                results.Add(CaptureStateFailure(
                    state.Id, "__setup", ex, driver, outputDirectory));
            }
            finally
            {
                try
                {
                    for (var actionIndex = 0; actionIndex < state.TeardownActions.Count; actionIndex++)
                        await ExecuteControlActionAsync(
                            state.TeardownActions[actionIndex], driver, policy, cancellationToken,
                            programLogProbe, programLogBookmarks,
                            processMemoryProbe, memorySamples,
                            $"{state.Id}/teardown-{actionIndex + 1}");
                }
                catch (Exception ex)
                {
                    results.Add(CaptureStateFailure(
                        state.Id, "__teardown", ex, driver, outputDirectory));
                }
            }
        }

        sessionStopwatch.Stop();
        CaptureMemory("session:finished", processMemoryProbe, memorySamples);
        var result = new SessionResult(
            started, sessionStopwatch.ElapsedMilliseconds, results, memorySamples);
        File.WriteAllText(Path.Combine(outputDirectory, "run-summary.json"),
            JsonSerializer.Serialize(result, new JsonSerializerOptions { WriteIndented = true }));
        return result;
    }

    private static async Task<PointResult> ExecutePointAsync(
        PlannedPoint planned,
        IWindowDriver driver,
        string outputDirectory,
        ScenarioPolicy policy,
        bool stateChanged,
        CancellationToken cancellationToken,
        IRenderTextProbe? textProbe)
    {
        var stopwatch = Stopwatch.StartNew();
        string? evidencePath = null;
        var timedOut = false;
        string? error = null;
        var status = "Passed";
        try
        {
            var point = planned.Point;
            var textBookmark = textProbe?.Bookmark() ?? 0;
            if (!point.Action.Equals("CaptureOnly", StringComparison.OrdinalIgnoreCase) &&
                (point.X is null || point.Y is null))
            {
                status = "Skipped";
                error = "Missing coordinates.";
            }
            else
            {
                var referenceCrop = point.Crop;
                if (referenceCrop is null && point.Action.StartsWith("Hover", StringComparison.OrdinalIgnoreCase))
                    referenceCrop = CoordinateTransform.InferHoverCrop(
                        point.X!.Value, point.Y!.Value,
                        CoordinateTransform.ReferenceWidth, CoordinateTransform.ReferenceHeight);
                var hasAction = !point.Action.Equals("CaptureOnly", StringComparison.OrdinalIgnoreCase);
                var baseline = hasAction ? driver.ReadFingerprint(referenceCrop) : null;
                if (point.Action.StartsWith("Hover", StringComparison.OrdinalIgnoreCase))
                    driver.Move(point.X!.Value, point.Y!.Value);
                else if (point.Action.StartsWith("Click", StringComparison.OrdinalIgnoreCase))
                    driver.Click(point.X!.Value, point.Y!.Value);

                if (hasAction)
                {
                    var wait = await AdaptiveWaiter.WaitForStableAsync(
                        _ => Task.FromResult(driver.ReadFingerprint(referenceCrop)),
                        maximumWaitMs: Math.Min(Math.Max(
                            point.WaitMs ?? policy.HoverWaitMsDefault, 1500),
                            policy.HoverWaitMsMaximum),
                        pollIntervalMs: 100,
                        baselineFingerprint: baseline,
                        requireChangeFromBaseline: !point.AllowUnchanged,
                        cancellationToken: cancellationToken);
                    timedOut = wait.TimedOut;
                    if (timedOut && !point.AllowUnchanged)
                    {
                        status = "Failed";
                        error = "The UI did not change and stabilize before the action timeout.";
                    }
                }

                if (textProbe is not null && planned.ExpectedNo.Count > 0)
                {
                    var observed = RenderedTextFilter.InRegion(
                        textProbe.ReadSince(textBookmark), referenceCrop,
                        CoordinateTransform.ReferenceWidth, CoordinateTransform.ReferenceHeight,
                        driver.ClientWidth, driver.ClientHeight);
                    var forbidden = planned.ExpectedNo
                        .Where(pattern => observed.Any(observation =>
                            observation.Text.Contains(pattern, StringComparison.OrdinalIgnoreCase)))
                        .Distinct(StringComparer.OrdinalIgnoreCase)
                        .ToArray();
                    if (forbidden.Length > 0)
                    {
                        status = "Failed";
                        error = string.IsNullOrEmpty(error)
                            ? "Forbidden visible text: " + string.Join(", ", forbidden)
                            : error + " Forbidden visible text: " + string.Join(", ", forbidden);
                    }
                }

                var evidenceKind = EvidencePolicy.Select(
                    stateChanged, status.Equals("Failed", StringComparison.OrdinalIgnoreCase), referenceCrop);
                var captureRegion = evidenceKind == EvidenceKind.Crop ? referenceCrop : null;
                evidencePath = Path.Combine(outputDirectory,
                    $"{Sanitize(planned.ScenarioId)}-{Sanitize(point.Id)}.png");
                driver.Capture(evidencePath, captureRegion, markCursor: true);
            }
        }
        catch (Exception ex)
        {
            status = "Failed";
            error = ex.Message;
            evidencePath = Path.Combine(outputDirectory,
                $"{Sanitize(planned.ScenarioId)}-{Sanitize(planned.Point.Id)}.failure.png");
            try { driver.Capture(evidencePath, null, markCursor: true); }
            catch { evidencePath = null; }
        }
        finally
        {
            stopwatch.Stop();
        }
        return new PointResult(planned.ScenarioId, planned.Point.Id, status,
            stopwatch.ElapsedMilliseconds, evidencePath, timedOut, error);
    }

    private static async Task ExecuteControlActionAsync(
        ScenarioAction action,
        IWindowDriver driver,
        ScenarioPolicy policy,
        CancellationToken cancellationToken,
        IProgramLogProbe? programLogProbe,
        IDictionary<string, long> programLogBookmarks,
        IProcessMemoryProbe? processMemoryProbe,
        ICollection<ProcessMemorySample> memorySamples,
        string actionPath)
    {
        CaptureMemory($"{actionPath}:before", processMemoryProbe, memorySamples);
        try
        {
            await ExecuteControlActionCoreAsync(
                action, driver, policy, cancellationToken,
                programLogProbe, programLogBookmarks,
                processMemoryProbe, memorySamples, actionPath);
        }
        finally
        {
            CaptureMemory($"{actionPath}:after", processMemoryProbe, memorySamples);
        }
    }

    private static async Task ExecuteControlActionCoreAsync(
        ScenarioAction action,
        IWindowDriver driver,
        ScenarioPolicy policy,
        CancellationToken cancellationToken,
        IProgramLogProbe? programLogProbe,
        IDictionary<string, long> programLogBookmarks,
        IProcessMemoryProbe? processMemoryProbe,
        ICollection<ProcessMemorySample> memorySamples,
        string actionPath)
    {
        var actionKind = string.IsNullOrWhiteSpace(action.Action) && action.X is not null && action.Y is not null
            ? "Hover"
            : action.Action;
        if (actionKind.Equals("Repeat", StringComparison.OrdinalIgnoreCase))
        {
            if (action.RepeatCount is < 1 or > 10)
                throw new InvalidDataException("Repeat requires RepeatCount between 1 and 10.");
            if (action.Actions.Length == 0)
                throw new InvalidDataException("Repeat requires at least one nested action.");
            for (var iteration = 0; iteration < action.RepeatCount; iteration++)
                for (var nestedIndex = 0; nestedIndex < action.Actions.Length; nestedIndex++)
                    await ExecuteControlActionAsync(
                        action.Actions[nestedIndex], driver, policy, cancellationToken,
                        programLogProbe, programLogBookmarks,
                        processMemoryProbe, memorySamples,
                        $"{actionPath}/repeat-{iteration + 1}/action-{nestedIndex + 1}");
            return;
        }
        if (actionKind.Equals("Wait", StringComparison.OrdinalIgnoreCase))
        {
            await Task.Delay(action.WaitMs ?? policy.HoverWaitMsDefault, cancellationToken);
            return;
        }
        if (actionKind.Equals("BookmarkProgramLog", StringComparison.OrdinalIgnoreCase))
        {
            if (programLogProbe is null)
                throw new InvalidOperationException("BookmarkProgramLog requires an owned game session.");
            if (string.IsNullOrWhiteSpace(action.Bookmark))
                throw new InvalidDataException("BookmarkProgramLog requires Bookmark.");
            programLogBookmarks[action.Bookmark] = programLogProbe.Bookmark();
            return;
        }
        if (actionKind.Equals("WaitForProgramLogMarker", StringComparison.OrdinalIgnoreCase))
        {
            if (programLogProbe is null)
                throw new InvalidOperationException("WaitForProgramLogMarker requires an owned game session.");
            if (string.IsNullOrWhiteSpace(action.Bookmark) ||
                !programLogBookmarks.TryGetValue(action.Bookmark, out var bookmark))
                throw new InvalidDataException("WaitForProgramLogMarker requires an existing named Bookmark.");
            if (string.IsNullOrWhiteSpace(action.Marker))
                throw new InvalidDataException("WaitForProgramLogMarker requires Marker.");
            var found = await programLogProbe.WaitForMarkerAfterAsync(
                bookmark, action.Marker,
                TimeSpan.FromMilliseconds(action.WaitMs ?? 45000), cancellationToken);
            if (!found)
                throw new TimeoutException(
                    $"Program log marker '{action.Marker}' did not appear after bookmark '{action.Bookmark}'.");
            return;
        }

        var crop = action.Crop;
        var baseline = driver.ReadFingerprint(crop);
        if (actionKind.StartsWith("Click", StringComparison.OrdinalIgnoreCase))
        {
            RequireCoordinates(action);
            driver.Click(action.X!.Value, action.Y!.Value);
        }
        else if (actionKind.StartsWith("Hover", StringComparison.OrdinalIgnoreCase) ||
                 actionKind.StartsWith("Move", StringComparison.OrdinalIgnoreCase))
        {
            RequireCoordinates(action);
            driver.Move(action.X!.Value, action.Y!.Value);
        }
        else if (actionKind.StartsWith("Key", StringComparison.OrdinalIgnoreCase))
        {
            if (string.IsNullOrWhiteSpace(action.Key))
                throw new InvalidDataException("A Key action requires Key.");
            driver.KeyPress(action.Key);
        }
        else
        {
            throw new InvalidDataException($"Unsupported state action '{actionKind}'.");
        }

        var wait = await AdaptiveWaiter.WaitForStableAsync(
            _ => Task.FromResult(driver.ReadFingerprint(crop)),
            maximumWaitMs: Math.Min(
                action.WaitMs ?? policy.HoverWaitMsDefault,
                policy.HoverWaitMsMaximum),
            pollIntervalMs: 100,
            baselineFingerprint: baseline,
            requireChangeFromBaseline: action.RequireChange,
            cancellationToken: cancellationToken);
        if (wait.TimedOut && action.RequireChange && !wait.ChangedFromBaseline)
            throw new TimeoutException($"State action '{actionKind}' did not change and stabilize the UI.");
    }

    private static PointResult CaptureStateFailure(
        string stateId,
        string phase,
        Exception exception,
        IWindowDriver driver,
        string outputDirectory)
    {
        var evidencePath = Path.Combine(outputDirectory,
            $"{Sanitize(stateId)}-{Sanitize(phase)}.failure.png");
        try { driver.Capture(evidencePath, null, markCursor: true); }
        catch { evidencePath = null; }
        return new PointResult(stateId, phase, "Failed", 0, evidencePath, false, exception.Message);
    }

    private static void CaptureMemory(
        string label,
        IProcessMemoryProbe? probe,
        ICollection<ProcessMemorySample> samples)
    {
        if (probe is null) return;
        try
        {
            var counters = probe.Capture();
            samples.Add(new ProcessMemorySample(
                DateTime.UtcNow, label,
                counters.WorkingSetBytes, counters.PrivateBytes,
                counters.VirtualBytes, counters.PagedBytes,
                counters.HandleCount));
        }
        catch (Exception ex)
        {
            samples.Add(new ProcessMemorySample(
                DateTime.UtcNow, label, -1, -1, -1, -1, -1, ex.Message));
        }
    }

    private static void RequireCoordinates(ScenarioAction action)
    {
        if (action.X is null || action.Y is null)
            throw new InvalidDataException($"State action '{action.Action}' requires X and Y.");
    }

    private static string Sanitize(string value) => string.Concat(value.Select(character =>
        Path.GetInvalidFileNameChars().Contains(character) ? '_' : character));
}
