using System.Diagnostics;
using System.Text.Json;

namespace AtG.TestHarness;

public sealed record TileTooltipObservation(
    string Identity,
    string NormalizedIdentity,
    string Surface,
    string State,
    string SourceKey,
    bool Rumor,
    bool Visible,
    bool Expanded,
    IReadOnlyList<string> Text);

public sealed record TileSweepTileResult(
    int Q,
    int R,
    int X,
    int Y,
    string Status,
    bool WaitTimedOut,
    bool CameraChanged,
    string? StopReason,
    IReadOnlyList<TileTooltipObservation> Tooltips,
    IReadOnlyList<string> ForbiddenText);

public sealed record TileSweepEvidence(
    string ScenarioId,
    string PointId,
    string BoundaryManifestId,
    int Radius,
    int TileCount,
    DateTime StartedAtUtc,
    IReadOnlyList<TileSweepTileResult> Tiles,
    IReadOnlyList<string> Errors);

public sealed record TileSweepExecutionResult(
    string Status,
    long DurationMs,
    string? EvidencePath,
    bool WaitTimedOut,
    string? Error,
    IReadOnlyList<TileSweepTileResult> Tiles);

public static class TileSweepRuntimeGuards
{
    public static bool HasRepeatedIdentity(ISet<string> seen, string signature) =>
        seen.Contains(signature);

    public static bool ExceedsCardCap(int cardCount, TileSweepSpec spec) =>
        cardCount > spec.MaxCardsPerTile;

    public static bool ExceedsCycleCap(int completedCycles, TileSweepSpec spec) =>
        completedCycles >= spec.MaxCyclesPerTile;

    public static bool CameraOrSelectionChanged(
        string tileBefore,
        string tileAfter,
        string geometryBefore,
        string geometryAfter) =>
        !string.Equals(tileBefore, tileAfter, StringComparison.Ordinal) ||
        !string.Equals(geometryBefore, geometryAfter, StringComparison.Ordinal);
}

public static class TileHoverSweepExecutor
{
    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true };

    public static async Task<TileSweepExecutionResult> ExecuteAsync(
        PlannedPoint planned,
        IWindowDriver driver,
        string outputDirectory,
        ScenarioPolicy policy,
        bool stateChanged,
        CancellationToken cancellationToken,
        IRenderTextProbe? textProbe)
    {
        var started = DateTime.UtcNow;
        var stopwatch = Stopwatch.StartNew();
        var tileResults = new List<TileSweepTileResult>();
        var errors = new List<string>();
        string? evidencePath = null;
        var timedOut = false;
        try
        {
            if (textProbe is null)
                throw new InvalidOperationException("TileHoverSweep requires --text-trace.");
            var spec = planned.TileSweep ??
                throw new InvalidDataException("TileHoverSweep point is missing TileSweep specification.");
            var coordinates = TileSweepPlanner.Enumerate(spec);
            var hoverWaitMs = Math.Min(Math.Max(
                planned.Point.WaitMs ?? policy.HoverWaitMsDefault, 900),
                policy.HoverWaitMsMaximum);

            foreach (var coordinate in coordinates)
            {
                cancellationToken.ThrowIfCancellationRequested();
                var result = await ExecuteTileAsync(
                    planned, spec, coordinate, driver, policy, hoverWaitMs,
                    cancellationToken, textProbe);
                tileResults.Add(result);
                timedOut |= result.WaitTimedOut;
                if (result.Status != "Passed")
                {
                    var message = $"tile ({result.Q},{result.R}) {result.Status}: " +
                        (result.StopReason ?? "unspecified stop");
                    errors.Add(message);
                }
            }

            var failed = tileResults.Where(tile => tile.Status == "Failed").ToArray();
            var incomplete = tileResults.Where(tile => tile.Status == "Incomplete").ToArray();
            var forbidden = tileResults.SelectMany(tile => tile.ForbiddenText)
                .Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
            if (forbidden.Length > 0)
                errors.Add("Forbidden visible text: " + string.Join(", ", forbidden));
            var status = failed.Length > 0 || forbidden.Length > 0 ? "Failed" :
                incomplete.Length > 0 ? "Incomplete" : "Passed";
            var summary = errors.Count == 0 ? null : string.Join("; ", errors);
            evidencePath = Path.Combine(outputDirectory,
                $"{Sanitize(planned.ScenarioId)}-{Sanitize(planned.Point.Id)}-tile-sweep.json");
            var evidence = new TileSweepEvidence(
                planned.ScenarioId, planned.Point.Id, spec.BoundaryManifestId,
                spec.Radius, tileResults.Count, started, tileResults, errors);
            Directory.CreateDirectory(outputDirectory);
            File.WriteAllText(evidencePath, JsonSerializer.Serialize(evidence, JsonOptions));
            var shouldCapture = stateChanged || status != "Passed";
            if (shouldCapture)
            {
                var imagePath = Path.Combine(outputDirectory,
                    $"{Sanitize(planned.ScenarioId)}-{Sanitize(planned.Point.Id)}" +
                    (status == "Passed" ? ".png" : ".failure.png"));
                driver.Capture(imagePath, null, markCursor: true);
                evidencePath = evidencePath + "|" + imagePath;
            }
            return new TileSweepExecutionResult(status, stopwatch.ElapsedMilliseconds,
                evidencePath, timedOut, summary, tileResults);
        }
        catch (Exception ex)
        {
            errors.Add(ex.Message);
            evidencePath = Path.Combine(outputDirectory,
                $"{Sanitize(planned.ScenarioId)}-{Sanitize(planned.Point.Id)}-tile-sweep.failure.json");
            Directory.CreateDirectory(outputDirectory);
            var evidence = new TileSweepEvidence(
                planned.ScenarioId, planned.Point.Id,
                planned.TileSweep?.BoundaryManifestId ?? string.Empty,
                planned.TileSweep?.Radius ?? 0, tileResults.Count, started, tileResults, errors);
            File.WriteAllText(evidencePath, JsonSerializer.Serialize(evidence, JsonOptions));
            try
            {
                var imagePath = Path.Combine(outputDirectory,
                    $"{Sanitize(planned.ScenarioId)}-{Sanitize(planned.Point.Id)}.failure.png");
                driver.Capture(imagePath, null, markCursor: true);
                evidencePath = evidencePath + "|" + imagePath;
            }
            catch { }
            return new TileSweepExecutionResult("Failed", stopwatch.ElapsedMilliseconds,
                evidencePath, timedOut, ex.Message, tileResults);
        }
        finally
        {
            stopwatch.Stop();
        }
    }

    private static async Task<TileSweepTileResult> ExecuteTileAsync(
        PlannedPoint planned,
        TileSweepSpec spec,
        TileSweepCoordinate coordinate,
        IWindowDriver driver,
        ScenarioPolicy policy,
        int hoverWaitMs,
        CancellationToken cancellationToken,
        IRenderTextProbe textProbe)
    {
        var waitTimedOut = false;
        var cameraChanged = false;
        var stopReasons = new List<string>();
        var observations = new List<TileTooltipObservation>();
        var forbidden = new List<string>();
        try
        {
            var textBookmark = textProbe.Bookmark();
            var baseline = driver.ReadFingerprint(spec.SafeViewport);
            driver.Move(coordinate.X, coordinate.Y);
            var waitStopwatch = Stopwatch.StartNew();
            var wait = await AdaptiveWaiter.WaitForStableAsync(
                _ => Task.FromResult(driver.ReadFingerprint(spec.SafeViewport)),
                maximumWaitMs: hoverWaitMs,
                pollIntervalMs: 100,
                baselineFingerprint: baseline,
                requireChangeFromBaseline: false,
                cancellationToken: cancellationToken);
            var remaining = hoverWaitMs - (int)waitStopwatch.ElapsedMilliseconds;
            if (remaining > 0) await Task.Delay(remaining, cancellationToken);
            waitTimedOut = wait.TimedOut;

            var panels = DetectPanels(textProbe, textBookmark, spec, driver);
            forbidden.AddRange(FindForbidden(planned.ExpectedNo, panels));
            if (panels.Count == 0)
            {
                return new TileSweepTileResult(coordinate.Q, coordinate.R, coordinate.X, coordinate.Y,
                    "Passed", waitTimedOut, false, "NoTooltip", [], forbidden);
            }

            if (panels.Any(panel => panel.State == TooltipPanelState.Unknown))
                stopReasons.Add("UnknownPanelState");
            if (TileSweepRuntimeGuards.ExceedsCardCap(
                    panels.Count(panel => panel.Surface == TooltipSurface.MapCard), spec))
                stopReasons.Add($"MaxCardsPerTile:{spec.MaxCardsPerTile}");

            if (spec.ExpandCollapsed)
            {
                var expansion = await ExpandCollapsedPanelsAsync(
                    panels, spec, coordinate, driver, textProbe, textBookmark,
                    hoverWaitMs, cancellationToken);
                panels = expansion.Panels.ToList();
                if (expansion.CameraChanged)
                {
                    cameraChanged = true;
                    stopReasons.Add("CameraOrSelectionChangedDuringExpand");
                }
                if (expansion.Incomplete)
                    stopReasons.Add(expansion.StopReason ?? "ExpansionDidNotConverge");
            }

            // Only cycle when the rendered card explicitly advertises that the
            // tile has another item.  Clicking every tile would select units or
            // pan the camera on ordinary terrain cards.
            if (spec.CycleItems && panels.Any(panel => panel.Surface == TooltipSurface.MapCard &&
                                                       panel.CanCycle))
            {
                var cycling = await CycleTileItemsAsync(
                    panels, spec, coordinate, driver, textProbe, textBookmark,
                    hoverWaitMs, cancellationToken);
                panels = cycling.Panels.ToList();
                if (cycling.CameraChanged)
                {
                    cameraChanged = true;
                    stopReasons.Add("CameraOrSelectionChangedDuringCycle");
                }
                if (cycling.Incomplete)
                    stopReasons.Add(cycling.StopReason ?? "CycleDidNotConverge");
            }

            observations.AddRange(ToObservations(panels));
            forbidden.AddRange(FindForbidden(planned.ExpectedNo, panels));
            var status = cameraChanged || forbidden.Count > 0 ? "Failed" :
                stopReasons.Count > 0 ? "Incomplete" : "Passed";
            return new TileSweepTileResult(coordinate.Q, coordinate.R, coordinate.X, coordinate.Y,
                status, waitTimedOut, cameraChanged,
                stopReasons.Count == 0 ? null : string.Join(",", stopReasons),
                observations, forbidden.Distinct(StringComparer.OrdinalIgnoreCase).ToArray());
        }
        catch (Exception ex)
        {
            stopReasons.Add(ex.Message);
            return new TileSweepTileResult(coordinate.Q, coordinate.R, coordinate.X, coordinate.Y,
                "Failed", waitTimedOut, cameraChanged, string.Join(",", stopReasons),
                observations, forbidden);
        }
    }

    private static async Task<(IReadOnlyList<TooltipPanel> Panels, bool Incomplete,
        bool CameraChanged, string? StopReason)> ExpandCollapsedPanelsAsync(
        IReadOnlyList<TooltipPanel> initial,
        TileSweepSpec spec,
        TileSweepCoordinate coordinate,
        IWindowDriver driver,
        IRenderTextProbe textProbe,
        long textBookmark,
        int waitMs,
        CancellationToken cancellationToken)
    {
        var panels = initial.ToList();
        for (var iteration = 0; iteration < spec.MaxCardsPerTile; iteration++)
        {
            var collapsed = panels.Where(panel => panel.Surface == TooltipSurface.MapCard &&
                panel.State == TooltipPanelState.Collapsed).ToArray();
            if (collapsed.Length == 0)
                return (panels, panels.Any(panel => panel.State == TooltipPanelState.Unknown),
                    false, panels.Any(panel => panel.State == TooltipPanelState.Unknown)
                        ? "UnknownPanelState" : null);
            var changed = false;
            foreach (var panel in collapsed)
            {
                if (panel.ExpandPoint is null)
                    return (panels, true, false, "CollapsedPanelHasNoExpandPoint");
                var guardBefore = ReadGuardSnapshot(driver, spec, coordinate);
                driver.Click(panel.ExpandPoint.X, panel.ExpandPoint.Y);
                await WaitAfterClickAsync(driver, spec.SafeViewport, waitMs, cancellationToken);
                var guardAfter = ReadGuardSnapshot(driver, spec, coordinate);
                if (TileSweepRuntimeGuards.CameraOrSelectionChanged(
                        guardBefore.Tile, guardAfter.Tile,
                        guardBefore.Geometry, guardAfter.Geometry))
                    return (panels, true, true, "CameraOrSelectionChanged");
                var rescanned = DetectPanels(textProbe, textBookmark, spec, driver);
                if (!rescanned.Any(item => item.State == TooltipPanelState.Expanded &&
                                           item.NormalizedIdentity == panel.NormalizedIdentity))
                    return (rescanned, true, false, "ExpandClickProducedNoExpandedPanel");
                panels = rescanned.ToList();
                changed = true;
            }
            if (!changed)
                return (panels, true, false, "ExpansionDidNotConverge");
        }
        return (panels, true, false, $"MaxCardsPerTile:{spec.MaxCardsPerTile}");
    }

    private static async Task<(IReadOnlyList<TooltipPanel> Panels, bool Incomplete,
        bool CameraChanged, string? StopReason)> CycleTileItemsAsync(
        IReadOnlyList<TooltipPanel> initial,
        TileSweepSpec spec,
        TileSweepCoordinate coordinate,
        IWindowDriver driver,
        IRenderTextProbe textProbe,
        long textBookmark,
        int waitMs,
        CancellationToken cancellationToken)
    {
        var panels = initial.ToList();
        var signatures = new HashSet<string>(StringComparer.Ordinal);
        for (var iteration = 0; !TileSweepRuntimeGuards.ExceedsCycleCap(iteration, spec); iteration++)
        {
            var signature = Signature(panels);
            if (!signatures.Add(signature))
                return (panels, false, false, null);
            var guardBefore = ReadGuardSnapshot(driver, spec, coordinate);
            driver.Click(coordinate.X, coordinate.Y);
            await WaitAfterClickAsync(driver, spec.SafeViewport, waitMs, cancellationToken);
            var guardAfter = ReadGuardSnapshot(driver, spec, coordinate);
            if (TileSweepRuntimeGuards.CameraOrSelectionChanged(
                    guardBefore.Tile, guardAfter.Tile,
                    guardBefore.Geometry, guardAfter.Geometry))
                return (panels, true, true, "CameraOrSelectionChanged");
            var rescanned = DetectPanels(textProbe, textBookmark, spec, driver);
            var nextSignature = Signature(rescanned);
            if (string.Equals(signature, nextSignature, StringComparison.Ordinal))
                return (rescanned, false, false, null);
            // A -> B -> A is the normal two-item cycle.  Stop as soon as a
            // complete identity signature repeats instead of consuming the
            // cycle cap and misreporting a converged tile as incomplete.
            if (TileSweepRuntimeGuards.HasRepeatedIdentity(signatures, nextSignature))
                return (rescanned, false, false, null);
            panels = rescanned.ToList();
            if (TileSweepRuntimeGuards.ExceedsCardCap(
                    panels.Count(panel => panel.Surface == TooltipSurface.MapCard), spec))
                return (panels, true, false, $"MaxCardsPerTile:{spec.MaxCardsPerTile}");
        }
        return (panels, true, false, $"MaxCyclesPerTile:{spec.MaxCyclesPerTile}");
    }

    private static async Task WaitAfterClickAsync(
        IWindowDriver driver,
        CropRegion stabilityRegion,
        int waitMs,
        CancellationToken cancellationToken)
    {
        var wait = await AdaptiveWaiter.WaitForStableAsync(
            _ => Task.FromResult(driver.ReadFingerprint(stabilityRegion)),
            maximumWaitMs: waitMs,
            pollIntervalMs: 100,
            baselineFingerprint: null,
            requireChangeFromBaseline: false,
            cancellationToken: cancellationToken);
        _ = wait;
    }

    private sealed record GuardSnapshot(string Tile, string Geometry);

    private static GuardSnapshot ReadGuardSnapshot(
        IWindowDriver driver,
        TileSweepSpec spec,
        TileSweepCoordinate coordinate)
    {
        var tile = driver.ReadFingerprint(GuardRegion(coordinate.X, coordinate.Y));
        var geometry = string.Join("|", GeometryRegions(spec.MapRegion)
            .Select(region => driver.ReadFingerprint(region)));
        return new GuardSnapshot(tile, geometry);
    }

    private static IReadOnlyList<CropRegion> GeometryRegions(CropRegion mapRegion)
    {
        const int size = 80;
        var width = Math.Min(size, Math.Max(1, mapRegion.Width / 3));
        var height = Math.Min(size, Math.Max(1, mapRegion.Height / 3));
        return
        [
            new CropRegion(mapRegion.X + 12, mapRegion.Y + 12, width, height),
            new CropRegion(mapRegion.X + mapRegion.Width - width - 12,
                mapRegion.Y + 12, width, height),
            new CropRegion(mapRegion.X + 12,
                mapRegion.Y + mapRegion.Height - height - 12, width, height),
            new CropRegion(mapRegion.X + mapRegion.Width - width - 12,
                mapRegion.Y + mapRegion.Height - height - 12, width, height),
        ];
    }

    private static IReadOnlyList<TooltipPanel> DetectPanels(
        IRenderTextProbe textProbe,
        long textBookmark,
        TileSweepSpec spec,
        IWindowDriver driver)
    {
        IReadOnlyList<CropRegion>? pixelRegions = null;
        if (driver is IWindowFrameSource frameSource)
        {
            using var frame = frameSource.CaptureFrame(spec.MapRegion);
            pixelRegions = TooltipPixelPanelDetector.Detect(
                frame, spec.MapRegion, driver.ClientWidth, driver.ClientHeight);
        }
        return TooltipPanelDetector.Detect(
            textProbe.ReadSince(textBookmark), spec, driver.ClientWidth, driver.ClientHeight,
            pixelRegions);
    }

    private static IReadOnlyList<TileTooltipObservation> ToObservations(
        IEnumerable<TooltipPanel> panels) => panels.Select(panel =>
    {
        var rumor = panel.Text.Any(text => text.Contains("传闻", StringComparison.Ordinal) ||
                                           text.Contains("Rumor", StringComparison.OrdinalIgnoreCase));
        var visible = panel.Surface == TooltipSurface.MapCard && !rumor;
        var surface = panel.Surface == TooltipSurface.QuickReference
            ? "TileQuickReference"
            : rumor ? "RumorKnownDeposit" : "VisibleDeposit";
        return new TileTooltipObservation(
            panel.Identity,
            panel.NormalizedIdentity,
            surface,
            panel.State.ToString(),
            panel.NormalizedIdentity,
            rumor,
            visible,
            panel.State == TooltipPanelState.Expanded,
            panel.Text);
    }).ToArray();

    private static IReadOnlyList<string> FindForbidden(
        IReadOnlyList<string> expectedNo,
        IEnumerable<TooltipPanel> panels) => panels.SelectMany(panel => panel.Text)
        .Where(text => expectedNo.Any(pattern =>
            text.Contains(pattern, StringComparison.OrdinalIgnoreCase)))
        .Distinct(StringComparer.OrdinalIgnoreCase)
        .ToArray();

    private static string Signature(IEnumerable<TooltipPanel> panels) => string.Join("|",
        panels.Where(panel => panel.Surface == TooltipSurface.MapCard)
            .OrderBy(panel => panel.NormalizedIdentity, StringComparer.Ordinal)
            .ThenBy(panel => panel.State)
            .Select(panel => panel.NormalizedIdentity + ":" + panel.State));

    private static CropRegion GuardRegion(int x, int y)
    {
        var left = Math.Clamp(x - 55, 0, CoordinateTransform.ReferenceWidth - 110);
        var top = Math.Clamp(y - 55, 0, CoordinateTransform.ReferenceHeight - 110);
        return new CropRegion(left, top, 110, 110);
    }

    private static string Sanitize(string value) => string.Concat(value.Select(character =>
        Path.GetInvalidFileNameChars().Contains(character) ? '_' : character));
}
