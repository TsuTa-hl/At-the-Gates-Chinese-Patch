using System.Drawing;
using System.Text.RegularExpressions;
using System.Xml.Linq;

namespace AtG.TestHarness;

public interface IWindowFrameSource
{
    Bitmap CaptureFrame(CropRegion? referenceRegion);
}

public static class TooltipPixelPanelDetector
{
    public static IReadOnlyList<CropRegion> Detect(
        Bitmap bitmap,
        CropRegion referenceRegion,
        int clientWidth,
        int clientHeight)
    {
        const int sampleStep = 6;
        var rowRanges = FindRanges(bitmap.Height, y => CountDarkRow(bitmap, y, sampleStep) >=
            Math.Max(3, bitmap.Width / sampleStep / 14));
        var regions = new List<CropRegion>();
        foreach (var rowRange in rowRanges)
        {
            var columnRanges = FindRanges(bitmap.Width, x => CountDarkColumn(bitmap, x,
                rowRange.Start, rowRange.End, sampleStep) >= Math.Max(3,
                (rowRange.End - rowRange.Start) / sampleStep / 8));
            foreach (var columnRange in columnRanges)
            {
                var left = referenceRegion.X + (int)Math.Round(columnRange.Start *
                    referenceRegion.Width / (float)bitmap.Width);
                var top = referenceRegion.Y + (int)Math.Round(rowRange.Start *
                    referenceRegion.Height / (float)bitmap.Height);
                var right = referenceRegion.X + (int)Math.Round(columnRange.End *
                    referenceRegion.Width / (float)bitmap.Width);
                var bottom = referenceRegion.Y + (int)Math.Round(rowRange.End *
                    referenceRegion.Height / (float)bitmap.Height);
                if (right - left >= 80 && bottom - top >= 18)
                    regions.Add(new CropRegion(left, top, right - left, bottom - top));
            }
        }
        return MergeOverlapping(regions);
    }

    private static int CountDarkRow(Bitmap bitmap, int y, int step)
    {
        var count = 0;
        for (var x = 0; x < bitmap.Width; x += step)
        {
            if (IsTooltipPixel(bitmap.GetPixel(Math.Clamp(x, 0, bitmap.Width - 1),
                    Math.Clamp(y, 0, bitmap.Height - 1))))
                count++;
        }
        return count;
    }

    private static int CountDarkColumn(Bitmap bitmap, int x, int startY, int endY, int step)
    {
        var count = 0;
        for (var y = startY; y < endY; y += step)
        {
            if (IsTooltipPixel(bitmap.GetPixel(Math.Clamp(x, 0, bitmap.Width - 1),
                    Math.Clamp(y, 0, bitmap.Height - 1))))
                count++;
        }
        return count;
    }

    private static bool IsTooltipPixel(Color color) =>
        color.B < 155 && color.B > color.R + 18 && color.B > color.G - 8 &&
        color.R < 100 && color.G < 135;

    private static IReadOnlyList<(int Start, int End)> FindRanges(
        int length,
        Func<int, bool> predicate)
    {
        var ranges = new List<(int Start, int End)>();
        var start = -1;
        for (var index = 0; index < length; index += 6)
        {
            var hit = predicate(index);
            if (hit && start < 0) start = index;
            if (!hit && start >= 0)
            {
                ranges.Add((start, index));
                start = -1;
            }
        }
        if (start >= 0) ranges.Add((start, length));
        return ranges;
    }

    private static IReadOnlyList<CropRegion> MergeOverlapping(IEnumerable<CropRegion> regions)
    {
        var result = new List<CropRegion>();
        foreach (var region in regions)
        {
            var overlap = result.FindIndex(existing => Intersects(existing, region));
            if (overlap < 0)
            {
                result.Add(region);
                continue;
            }
            result[overlap] = Union(result[overlap], region);
        }
        return result;
    }

    internal static bool Intersects(CropRegion left, CropRegion right) =>
        left.X < right.X + right.Width && right.X < left.X + left.Width &&
        left.Y < right.Y + right.Height && right.Y < left.Y + left.Height;

    internal static CropRegion Union(CropRegion left, CropRegion right)
    {
        var x = Math.Min(left.X, right.X);
        var y = Math.Min(left.Y, right.Y);
        var rightEdge = Math.Max(left.X + left.Width, right.X + right.Width);
        var bottomEdge = Math.Max(left.Y + left.Height, right.Y + right.Height);
        return new CropRegion(x, y, rightEdge - x, bottomEdge - y);
    }
}

public sealed class TileReferencePoint
{
    public int X { get; init; }
    public int Y { get; init; }

    public TileReferencePoint() { }
    public TileReferencePoint(int x, int y) => (X, Y) = (x, y);
}

public sealed class TileSweepSpec
{
    public int Radius { get; init; } = 5;
    public string Metric { get; init; } = "AxialHex";
    public TileReferencePoint Anchor { get; init; } = new();
    public TileReferencePoint BasisQ { get; init; } = new();
    public TileReferencePoint BasisR { get; init; } = new();
    public CropRegion SafeViewport { get; init; } = new(0, 0, 2560, 1440);
    public CropRegion MapRegion { get; init; } = new(250, 160, 1980, 1120);
    public CropRegion QuickReferenceRegion { get; init; } = new(1840, 1010, 720, 430);
    public string Enumerate { get; init; } = "CenterOutward";
    public bool ExpandCollapsed { get; init; } = true;
    public bool CycleItems { get; init; } = true;
    public int MaxCardsPerTile { get; init; } = 16;
    public int MaxCyclesPerTile { get; init; } = 2;
    public string BoundaryManifestId { get; init; } = string.Empty;
}

public sealed record TileSweepCoordinate(int Q, int R, int X, int Y)
{
    public int Distance => Math.Max(Math.Abs(Q), Math.Max(Math.Abs(R), Math.Abs(Q + R)));
}

public static class TileSweepPlanner
{
    public static IReadOnlyList<TileSweepCoordinate> Enumerate(
        TileSweepSpec spec,
        int referenceWidth = CoordinateTransform.ReferenceWidth,
        int referenceHeight = CoordinateTransform.ReferenceHeight)
    {
        Validate(spec, referenceWidth, referenceHeight);
        var deltaQ = (spec.BasisQ.X - spec.Anchor.X, spec.BasisQ.Y - spec.Anchor.Y);
        var deltaR = (spec.BasisR.X - spec.Anchor.X, spec.BasisR.Y - spec.Anchor.Y);
        var coordinates = new List<TileSweepCoordinate>();
        for (var q = -spec.Radius; q <= spec.Radius; q++)
        {
            for (var r = -spec.Radius; r <= spec.Radius; r++)
            {
                var distance = Math.Max(Math.Abs(q), Math.Max(Math.Abs(r), Math.Abs(q + r)));
                if (distance > spec.Radius) continue;
                coordinates.Add(new TileSweepCoordinate(
                    q, r,
                    spec.Anchor.X + q * deltaQ.Item1 + r * deltaR.Item1,
                    spec.Anchor.Y + q * deltaQ.Item2 + r * deltaR.Item2));
            }
        }

        return coordinates
            .OrderBy(point => point.Distance)
            .ThenBy(point => point.Q)
            .ThenBy(point => point.R)
            .ToArray();
    }

    public static void Validate(
        TileSweepSpec spec,
        int referenceWidth = CoordinateTransform.ReferenceWidth,
        int referenceHeight = CoordinateTransform.ReferenceHeight)
    {
        ArgumentNullException.ThrowIfNull(spec);
        if (!string.Equals(spec.Metric, "AxialHex", StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("TileSweep Metric must be AxialHex.");
        if (spec.Radius != 5)
            throw new InvalidDataException("TileSweep Radius must be exactly 5.");
        if (!string.Equals(spec.Enumerate, "CenterOutward", StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("TileSweep Enumerate must be CenterOutward.");
        if (string.IsNullOrWhiteSpace(spec.BoundaryManifestId))
            throw new InvalidDataException("TileSweep BoundaryManifestId is required.");
        if (spec.MaxCardsPerTile is < 1 or > 64)
            throw new InvalidDataException("TileSweep MaxCardsPerTile must be between 1 and 64.");
        if (spec.MaxCyclesPerTile is < 1 or > 5)
            throw new InvalidDataException("TileSweep MaxCyclesPerTile must be between 1 and 5.");

        ValidatePoint(spec.Anchor, referenceWidth, referenceHeight, "Anchor");
        ValidatePoint(spec.BasisQ, referenceWidth, referenceHeight, "BasisQ");
        ValidatePoint(spec.BasisR, referenceWidth, referenceHeight, "BasisR");
        ValidateRegion(spec.SafeViewport, referenceWidth, referenceHeight, "SafeViewport");
        ValidateRegion(spec.MapRegion, referenceWidth, referenceHeight, "MapRegion");
        ValidateRegion(spec.QuickReferenceRegion, referenceWidth, referenceHeight,
            "QuickReferenceRegion");

        var deltaQ = (spec.BasisQ.X - spec.Anchor.X, spec.BasisQ.Y - spec.Anchor.Y);
        var deltaR = (spec.BasisR.X - spec.Anchor.X, spec.BasisR.Y - spec.Anchor.Y);
        if (deltaQ == (0, 0) || deltaR == (0, 0))
            throw new InvalidDataException("TileSweep BasisQ and BasisR must differ from Anchor.");
        var determinant = deltaQ.Item1 * deltaR.Item2 - deltaQ.Item2 * deltaR.Item1;
        if (determinant == 0)
            throw new InvalidDataException("TileSweep BasisQ and BasisR must be non-collinear.");

        var coordinates = GenerateUnchecked(spec, deltaQ, deltaR);
        if (coordinates.Count != 91)
            throw new InvalidDataException($"TileSweep must generate 91 tiles, got {coordinates.Count}.");
        if (coordinates.Select(point => (point.X, point.Y)).Distinct().Count() != 91)
            throw new InvalidDataException("TileSweep generated duplicate absolute coordinates.");
        if (coordinates.Any(point => !Contains(spec.SafeViewport, point.X, point.Y)))
            throw new InvalidDataException("TileSweep generated a coordinate outside SafeViewport.");
    }

    private static IReadOnlyList<TileSweepCoordinate> GenerateUnchecked(
        TileSweepSpec spec,
        (int X, int Y) deltaQ,
        (int X, int Y) deltaR)
    {
        var result = new List<TileSweepCoordinate>();
        for (var q = -spec.Radius; q <= spec.Radius; q++)
        for (var r = -spec.Radius; r <= spec.Radius; r++)
        {
            var distance = Math.Max(Math.Abs(q), Math.Max(Math.Abs(r), Math.Abs(q + r)));
            if (distance > spec.Radius) continue;
            result.Add(new TileSweepCoordinate(q, r,
                spec.Anchor.X + q * deltaQ.X + r * deltaR.X,
                spec.Anchor.Y + q * deltaQ.Y + r * deltaR.Y));
        }
        return result;
    }

    private static void ValidatePoint(TileReferencePoint point, int width, int height, string name)
    {
        ArgumentNullException.ThrowIfNull(point);
        if (point.X is < 0 || point.X >= width || point.Y is < 0 || point.Y >= height)
            throw new InvalidDataException($"TileSweep {name} must be inside the reference client.");
    }

    private static void ValidateRegion(CropRegion region, int width, int height, string name)
    {
        ArgumentNullException.ThrowIfNull(region);
        if (region.Width <= 0 || region.Height <= 0 || region.X < 0 || region.Y < 0 ||
            region.X + region.Width > width || region.Y + region.Height > height)
            throw new InvalidDataException($"TileSweep {name} must be a positive in-client region.");
    }

    public static bool Contains(CropRegion region, int x, int y) =>
        x >= region.X && y >= region.Y && x < region.X + region.Width &&
        y < region.Y + region.Height;
}

public enum TooltipPanelState
{
    Unknown,
    Collapsed,
    Expanded,
}

public enum TooltipSurface
{
    MapCard,
    QuickReference,
}

public sealed record TooltipPanel(
    string Identity,
    string NormalizedIdentity,
    TooltipSurface Surface,
    TooltipPanelState State,
    CropRegion Bounds,
    TileReferencePoint? ExpandPoint,
    bool CanCycle,
    IReadOnlyList<string> Text);

public static class TooltipPanelDetector
{
    private const string ExpandMarker = "点击展开此面板";
    private const string MinimizeMarker = "点击最小化此面板";

    public static IReadOnlyList<TooltipPanel> Detect(
        IEnumerable<RenderedTextObservation> observations,
        TileSweepSpec spec,
        int clientWidth,
        int clientHeight,
        IReadOnlyList<CropRegion>? pixelRegions = null)
    {
        var positioned = observations
            .Where(observation => observation.X.HasValue && observation.Y.HasValue)
            .Where(observation => IsInRegion(observation, spec.MapRegion, clientWidth, clientHeight) ||
                                  IsInRegion(observation, spec.QuickReferenceRegion,
                                      clientWidth, clientHeight))
            .ToArray();
        if (positioned.Length == 0 && (pixelRegions is null || pixelRegions.Count == 0)) return [];

        var markers = positioned
            .Where(observation => observation.Text.Contains(ExpandMarker, StringComparison.Ordinal) ||
                                  observation.Text.Contains(MinimizeMarker, StringComparison.Ordinal))
            .ToArray();
        if (markers.Length == 0)
            return DetectUnknownPanels(positioned, spec, clientWidth, clientHeight, pixelRegions);

        var result = new List<TooltipPanel>();
        foreach (var marker in markers)
        {
            var markerPoint = ToReference(marker, clientWidth, clientHeight);
            var related = positioned.Where(observation =>
            {
                var point = ToReference(observation, clientWidth, clientHeight);
                return Math.Abs(point.X - markerPoint.X) <= 520 &&
                       Math.Abs(point.Y - markerPoint.Y) <= 430;
            }).ToArray();
            if (related.Length == 0) related = [marker];

            var bounds = BoundsOf(related, clientWidth, clientHeight);
            var pixelRegion = pixelRegions?.FirstOrDefault(region =>
                TooltipPixelPanelDetector.Intersects(region, bounds));
            if (pixelRegion is not null)
                bounds = TooltipPixelPanelDetector.Union(bounds, pixelRegion);
            var quickReference = TileSweepPlanner.Contains(
                spec.QuickReferenceRegion, bounds.X + bounds.Width / 2,
                bounds.Y + bounds.Height / 2);
            var state = marker.Text.Contains(ExpandMarker, StringComparison.Ordinal)
                ? TooltipPanelState.Collapsed
                : TooltipPanelState.Expanded;
            var identity = ExtractIdentity(marker.Text) ?? FindNearestText(related, marker.Text);
            var text = related.Select(item => item.Text).Distinct(StringComparer.Ordinal).ToArray();
            var panel = new TooltipPanel(
                identity,
                NormalizeIdentity(identity),
                quickReference ? TooltipSurface.QuickReference : TooltipSurface.MapCard,
                state,
                bounds,
                quickReference || state != TooltipPanelState.Collapsed
                    ? null
                    : new TileReferencePoint(bounds.X + Math.Max(4, bounds.Width - 18),
                        bounds.Y + 16),
                text.Any(value => value.Contains("再次", StringComparison.Ordinal) ||
                                  value.Contains("循环", StringComparison.Ordinal) ||
                                  value.Contains("切换", StringComparison.Ordinal) ||
                                  value.Contains("click again", StringComparison.OrdinalIgnoreCase) ||
                                  value.Contains("cycle", StringComparison.OrdinalIgnoreCase)),
                text);
            if (!result.Any(existing => existing.NormalizedIdentity == panel.NormalizedIdentity &&
                                        existing.Surface == panel.Surface &&
                                        existing.State == panel.State))
                result.Add(panel);
        }
        return result;
    }

    public static string NormalizeIdentity(string value)
    {
        var normalized = value.Replace("（位于此地格）", string.Empty,
                StringComparison.Ordinal)
            .Replace("(位于此地格)", string.Empty, StringComparison.Ordinal)
            .Replace("点击展开此面板以查看基本说明：", string.Empty,
                StringComparison.Ordinal)
            .Trim();
        return Regex.Replace(normalized, @"\s+", string.Empty);
    }

    private static IReadOnlyList<TooltipPanel> DetectUnknownPanels(
        IReadOnlyList<RenderedTextObservation> observations,
        TileSweepSpec spec,
        int clientWidth,
        int clientHeight,
        IReadOnlyList<CropRegion>? pixelRegions)
    {
        var result = new List<TooltipPanel>();
        foreach (var observation in observations.Where(item => !string.IsNullOrWhiteSpace(item.Text)))
        {
            var point = ToReference(observation, clientWidth, clientHeight);
                var quick = TileSweepPlanner.Contains(spec.QuickReferenceRegion, point.X, point.Y);
            var identity = observation.Text.Trim();
            var panel = new TooltipPanel(identity, NormalizeIdentity(identity),
                quick ? TooltipSurface.QuickReference : TooltipSurface.MapCard,
                TooltipPanelState.Unknown,
                BoundsOf([observation], clientWidth, clientHeight), null, false, [identity]);
            if (!result.Any(existing => existing.NormalizedIdentity == panel.NormalizedIdentity &&
                                        existing.Surface == panel.Surface))
                result.Add(panel);
        }
        if (pixelRegions is not null)
        {
            foreach (var region in pixelRegions)
            {
                if (result.Any(panel => TooltipPixelPanelDetector.Intersects(panel.Bounds, region)))
                    continue;
                var quick = TileSweepPlanner.Contains(spec.QuickReferenceRegion,
                    region.X + region.Width / 2, region.Y + region.Height / 2);
                var identity = "pixel-panel-" + region.X + "-" + region.Y;
                result.Add(new TooltipPanel(identity, identity,
                    quick ? TooltipSurface.QuickReference : TooltipSurface.MapCard,
                    TooltipPanelState.Unknown, region, null, false, []));
            }
        }
        return result;
    }

    private static string? ExtractIdentity(string text)
    {
        var markerIndex = text.IndexOf('：');
        if (markerIndex >= 0 && markerIndex + 1 < text.Length)
            return text[(markerIndex + 1)..].Trim();
        return null;
    }

    private static string FindNearestText(
        IReadOnlyList<RenderedTextObservation> observations,
        string marker)
    {
        return observations
            .Where(item => !string.Equals(item.Text, marker, StringComparison.Ordinal))
            .OrderBy(item => item.Y ?? float.MaxValue)
            .ThenBy(item => item.X ?? float.MaxValue)
            .Select(item => item.Text.Trim())
            .FirstOrDefault(value => !string.IsNullOrWhiteSpace(value)) ?? marker;
    }

    private static CropRegion BoundsOf(
        IReadOnlyList<RenderedTextObservation> observations,
        int clientWidth,
        int clientHeight)
    {
        var points = observations.Select(observation =>
        {
            var point = ToReference(observation, clientWidth, clientHeight);
            var width = (int)Math.Ceiling((observation.Width ?? 1) *
                CoordinateTransform.ReferenceWidth / (float)clientWidth);
            var height = (int)Math.Ceiling((observation.Height ?? 1) *
                CoordinateTransform.ReferenceHeight / (float)clientHeight);
            return (Left: point.X, Top: point.Y, Right: point.X + Math.Max(1, width),
                Bottom: point.Y + Math.Max(1, height));
        }).ToArray();
        var left = Math.Max(0, points.Min(point => point.Left) - 18);
        var top = Math.Max(0, points.Min(point => point.Top) - 12);
        var right = Math.Min(CoordinateTransform.ReferenceWidth, points.Max(point => point.Right) + 18);
        var bottom = Math.Min(CoordinateTransform.ReferenceHeight, points.Max(point => point.Bottom) + 18);
        return new CropRegion(left, top, Math.Max(1, right - left), Math.Max(1, bottom - top));
    }

    private static TileReferencePoint ToReference(
        RenderedTextObservation observation,
        int clientWidth,
        int clientHeight) => new(
        (int)Math.Round(observation.X!.Value * CoordinateTransform.ReferenceWidth / clientWidth),
        (int)Math.Round(observation.Y!.Value * CoordinateTransform.ReferenceHeight / clientHeight));

    private static bool IsInRegion(
        RenderedTextObservation observation,
        CropRegion region,
        int clientWidth,
        int clientHeight)
    {
        var point = ToReference(observation, clientWidth, clientHeight);
        return TileSweepPlanner.Contains(region, point.X, point.Y);
    }
}

public sealed record BoundarySourceEntry(
    string Kind,
    string SourceKey,
    string Original,
    string Variant,
    string DescriptionStatus,
    string Reachability);

public sealed record TooltipSurfaceObservation(
    string SourceKey,
    bool Rumor,
    bool Visible,
    string Surface,
    string State);

public static class TerrainTooltipBoundaryCatalog
{
    private static readonly string[] Kinds = ["Terrain", "Deposit", "Resource"];

    public static IReadOnlyList<BoundarySourceEntry> ReadSourceInventory(string sourcePath)
    {
        var document = XDocument.Load(sourcePath, LoadOptions.PreserveWhitespace);
        var descriptionStatus = document.Descendants("e")
            .Select(element => (Key: AttributeValue(element), Value: element.Value.Trim()))
            .Where(item => item.Key.StartsWith("TEXT.Description.Terrain.", StringComparison.Ordinal))
            .GroupBy(item => item.Key["TEXT.Description.Terrain.".Length..],
                StringComparer.Ordinal)
            .ToDictionary(group => group.Key, group =>
                group.Any(item => string.Equals(item.Value, "TODO", StringComparison.OrdinalIgnoreCase))
                    ? "SourceTodo" : "Defined", StringComparer.Ordinal);
        var result = new List<BoundarySourceEntry>();
        foreach (var kind in Kinds)
        {
            var prefix = "TEXT.Name." + kind + ".";
            var sectionName = kind switch
            {
                "Terrain" => "terrains",
                "Deposit" => "deposits",
                "Resource" => "resources",
                _ => throw new InvalidDataException($"Unsupported boundary kind '{kind}'."),
            };
            var sections = document.Descendants(sectionName);
            foreach (var element in sections.SelectMany(section => section.Elements("e")))
            {
                var key = AttributeValue(element);
                if (!key.StartsWith(prefix, StringComparison.Ordinal)) continue;
                var id = key[prefix.Length..];
                var variant = kind == "Deposit"
                    ? id.StartsWith("Large", StringComparison.Ordinal) ? "Large"
                    : id.StartsWith("Vast", StringComparison.Ordinal) ? "Vast" : "Base"
                    : "Base";
                var status = kind == "Terrain" && descriptionStatus.TryGetValue(id, out var value)
                    ? value : "Defined";
                result.Add(new BoundarySourceEntry(kind, key, element.Value.Trim(), variant,
                    status, "Pending"));
            }
        }
        return result
            .GroupBy(entry => entry.SourceKey, StringComparer.Ordinal)
            .Select(group => group.First())
            .OrderBy(entry => Array.IndexOf(Kinds, entry.Kind))
            .ThenBy(entry => entry.SourceKey, StringComparer.Ordinal)
            .ToArray();
    }

    public static (int Terrains, int Deposits, int Resources) CountByKind(
        IEnumerable<BoundarySourceEntry> entries)
    {
        var grouped = entries.GroupBy(entry => entry.Kind, StringComparer.Ordinal)
            .ToDictionary(group => group.Key, group => group.Count(), StringComparer.Ordinal);
        return (Get(grouped, "Terrain"), Get(grouped, "Deposit"), Get(grouped, "Resource"));
    }

    public static string ClassifyReachability(
        bool rumorObserved,
        bool visibleObserved,
        bool explicitlyUnreachable = false)
    {
        if (rumorObserved && visibleObserved) return "Observed";
        if (rumorObserved) return "RumorOnly";
        if (visibleObserved) return "VisibleOnly";
        return explicitlyUnreachable ? "Unreachable" : "Pending";
    }

    public static IReadOnlyDictionary<string, string> MergeReachability(
        IEnumerable<TooltipSurfaceObservation> observations)
    {
        return observations.GroupBy(item => item.SourceKey, StringComparer.Ordinal)
            .ToDictionary(group => group.Key, group => ClassifyReachability(
                group.Any(item => item.Rumor), group.Any(item => item.Visible)),
                StringComparer.Ordinal);
    }

    private static int Get(IReadOnlyDictionary<string, int> grouped, string key) =>
        grouped.TryGetValue(key, out var value) ? value : 0;

    private static string AttributeValue(XElement element) =>
        element.Attribute("ntry")?.Value ?? element.Attribute("entry")?.Value ?? string.Empty;
}
