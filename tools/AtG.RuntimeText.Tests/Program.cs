using AtG.RuntimeText;

var tests = new (string Name, Action Body)[]
{
    ("Concept links preserve their machine key", ConceptLinkPreservesKey),
    ("Raw formatting tags round-trip unchanged", RawTagsRoundTrip),
    ("Dynamic config tags with pipes remain raw", DynamicConfigTagWithPipeRemainsRaw),
    ("Plural selectors with two pipes remain raw", PluralSelectorWithTwoPipesRemainsRaw),
    ("Only allowlisted keys become concept links", OnlyAllowlistedKeysBecomeConceptLinks),
    ("Rich localization changes display text but preserves keys and raw tags", RichLocalizationPreservesStructure),
    ("Display registrations reject conflicts and markup injection", DisplayRegistrationsRejectUnsafeValues),
    ("Runtime display map loads exact and concept-scoped translations", RuntimeDisplayMapLoads),
    ("CJK line breaks respect punctuation", CjkBreaksRespectPunctuation),
    ("CJK fitting breaks preserve punctuation and grapheme clusters", CjkFittingBreaksPreserveTextElements),
    ("CJK word layout splits only at invisible line boundaries", CjkWordLayoutUsesLineBoundaries),
    ("CJK word bridge preserves ASCII and wraps CJK without spaces", CjkWordBridgePreservesOriginalPath),
    ("Display templates localize only exact approved strings", ExactTemplatesOnly),
    ("SpriteFont asset names map to exact runtime descriptors", SpriteFontAssetsMapExactly),
    ("Zero-width format characters are ignored by runtime text", ZeroWidthFormatCharactersAreIgnored),
    ("Shelf packing crosses to a new atlas page", ShelfPackingCrossesToNewPage),
    ("Atlas allocation stops at eight pages", AtlasAllocationStopsAtEightPages),
    ("Faulted atlas rejects allocation without clearing its ledger", FaultedAtlasRejectsAllocationWithoutClearingLedger),
    ("Device reset retains live atlas resources and their ledger", DeviceResetRetainsLiveResources),
    ("Device reset clears the ledger only after every resource is released", DeviceResetClearsReleasedResources),
    ("Mixed reset resources remain faulted instead of reallocating", MixedResetResourcesRemainFaulted),
    ("Failed atlas allocations do not pollute allocator state", FailedAtlasAllocationsDoNotPolluteState),
    ("Glyph diagnostics charge actual atlas pages", GlyphDiagnosticsChargeActualAtlasPages),
    ("Texture binding scan finds every pixel and vertex reference", TextureBindingScanFindsEveryReference),
    ("Atlas allocator is atomic and non-overlapping under concurrency", AtlasAllocatorIsAtomicUnderConcurrency),
    ("Trace write failures never escape the rendering boundary", TraceWriteFailuresNeverEscape),
    ("Runtime trace JSON records final text bounds and missing glyphs", RuntimeTraceRecordsMetrics),
    ("Deferred glyph uploads are deduplicated and drained atomically", DeferredGlyphsAreDeduplicated),
};
var failures = 0;
foreach (var test in tests)
{
    try { test.Body(); Console.WriteLine($"PASS {test.Name}"); }
    catch (Exception ex) { failures++; Console.Error.WriteLine($"FAIL {test.Name}: {ex.Message}"); }
}
return failures == 0 ? 0 : 1;

static void ConceptLinkPreservesKey()
{
    var nodes = RichTextAst.Parse("训练[氏族|CLAN]并获得[升级|UPGRADES]");
    var links = nodes.OfType<ConceptLinkNode>().ToArray();
    Equal(2, links.Length);
    Equal("CLAN", links[0].ConceptKey);
    Equal("UPGRADES", links[1].ConceptKey);
    Equal("训练[氏族|CLAN]并获得[升级|UPGRADES]", RichTextAst.Render(nodes));
}

static void RawTagsRoundTrip()
{
    const string value = "[COLOR:EMPHASIS]重点[/COLOR][HOTKEY:F1]";
    Equal(value, RichTextAst.Render(RichTextAst.Parse(value)));
}

static void DynamicConfigTagWithPipeRemainsRaw()
{
    const string value = "[???:RESOURCE|###:NUM]";
    var nodes = RichTextAst.Parse(value, new HashSet<string>(StringComparer.Ordinal) { "RESOURCE" });
    Equal(1, nodes.Count);
    True(nodes[0] is RawTagNode);
    Equal(value, RichTextAst.Render(nodes));
}

static void PluralSelectorWithTwoPipesRemainsRaw()
{
    const string value = "[Turn|Turns|###:NUM]";
    var nodes = RichTextAst.Parse(value, new HashSet<string>(StringComparer.Ordinal) { "TURN" });
    Equal(1, nodes.Count);
    True(nodes[0] is RawTagNode);
    Equal(value, RichTextAst.Render(nodes));
}

static void OnlyAllowlistedKeysBecomeConceptLinks()
{
    var keys = new HashSet<string>(StringComparer.Ordinal) { "CLAN" };
    var known = RichTextAst.Parse("[Clan|CLAN]", keys);
    var unknown = RichTextAst.Parse("[Upgrade|UPGRADES]", keys);
    True(known[0] is ConceptLinkNode);
    True(unknown[0] is RawTagNode);
    Equal("[Upgrade|UPGRADES]", RichTextAst.Render(unknown));
}

static void RichLocalizationPreservesStructure()
{
    DisplayStringLocalizer.ResetForTests();
    DisplayStringLocalizer.RegisterConceptKey("CLAN");
    DisplayStringLocalizer.RegisterPlainText("Train ", "\u8bad\u7ec3");
    DisplayStringLocalizer.RegisterConceptDisplay("CLAN", "Clan", "\u6c0f\u65cf");

    const string raw = "Train [Clan|CLAN] [???:RESOURCE|###:NUM]";
    var localized = DisplayStringLocalizer.LocalizeRichText(raw);

    Equal("\u8bad\u7ec3[\u6c0f\u65cf|CLAN] [???:RESOURCE|###:NUM]", localized);
}

static void DisplayRegistrationsRejectUnsafeValues()
{
    DisplayStringLocalizer.ResetForTests();
    DisplayStringLocalizer.RegisterPlainText("Train ", "\u8bad\u7ec3");
    Throws<InvalidOperationException>(() =>
        DisplayStringLocalizer.RegisterPlainText("Train ", "\u57f9\u8bad"));
    Throws<ArgumentException>(() =>
        DisplayStringLocalizer.RegisterPlainText("Clan", "[\u6c0f\u65cf|CLAN]"));
}

static void RuntimeDisplayMapLoads()
{
    DisplayStringLocalizer.ResetForTests();
    var lines = string.Join("\n", new[]
    {
        "K\t" + B64("CLAN"),
        "P\t" + B64("Train ") + "\t" + B64("\u8bad\u7ec3"),
        "C\t" + B64("CLAN") + "\t" + B64("Clan") + "\t" + B64("\u6c0f\u65cf"),
        "E\t" + B64("Close") + "\t" + B64("\u5173\u95ed"),
    });
    DisplayStringLocalizer.Load(new StringReader(lines));

    Equal("\u5173\u95ed", DisplayStringLocalizer.LocalizeDisplayString("Close"));
    Equal("\u8bad\u7ec3[\u6c0f\u65cf|CLAN]",
        DisplayStringLocalizer.LocalizeRichText("Train [Clan|CLAN]"));
}

static void CjkBreaksRespectPunctuation()
{
    True(CjkText.CanBreakBetween('汉', '字'));
    True(!CjkText.CanBreakBetween('（', '汉'));
    True(!CjkText.CanBreakBetween('字', '）'));
}

static void CjkFittingBreaksPreserveTextElements()
{
    Equal(2, CjkText.FindLongestFittingBreak("\u6c49\u5b57\u6d4b\u8bd5", 2f, text => text.Length));
    Equal(2, CjkText.FindLongestFittingBreak("\u6c49\uff0c\u5b57", 1f, text => text.Length));
    Equal(3, CjkText.FindLongestFittingBreak("\u6c49\U00020000\u5b57", 2f,
        text => new System.Globalization.StringInfo(text).LengthInTextElements));
    Equal("ASCII".Length,
        CjkText.FindLongestFittingBreak("ASCII", 2f, text => text.Length));
}

static void CjkWordLayoutUsesLineBoundaries()
{
    var pieces = CjkLineBreaker.SplitWord("\u6c49\u5b57\u6d4b\u8bd5", 2f, 2f,
        text => text.Length);
    True(pieces.SequenceEqual(new[] { "\u6c49\u5b57", "\u6d4b\u8bd5" }));
    var punctuation = CjkLineBreaker.SplitWord("\u6c49\uff0c\u5b57", 1f, 2f,
        text => text.Length);
    True(punctuation.SequenceEqual(new[] { "\u6c49\uff0c", "\u5b57" }));
    True(CjkLineBreaker.SplitWord("Unbreakable", 2f, 2f, text => text.Length)
        .SequenceEqual(new[] { "Unbreakable" }));
}

static void CjkWordBridgePreservesOriginalPath()
{
    var ascii = new FakeWordProcessor("Unbreakable", 2);
    CjkWordWrapCore.ProcessWord(ascii,
        (_, text) => new CjkMeasuredText(text.Length, 1f));
    Equal(1, ascii.OriginalCalls);

    var cjk = new FakeWordProcessor("\u6c49\u5b57\u6d4b\u8bd5", 2);
    CjkWordWrapCore.ProcessWord(cjk,
        (_, text) => new CjkMeasuredText(text.Length, 1f));
    Equal(0, cjk.OriginalCalls);
    Equal(1, cjk.FinishedLines);
    Equal("\u6d4b\u8bd5", cjk.TextSoFar.ToString());
    Equal(null, cjk.Word);
    True(cjk.Emitted.All(text => text.IndexOf(' ') < 0));
}

static void ExactTemplatesOnly()
{
    DisplayStringLocalizer.Register("Clan {0} joined", "氏族{0}加入");
    Equal("氏族{0}加入", DisplayStringLocalizer.LocalizeDisplayString("Clan {0} joined"));
    Equal("and", DisplayStringLocalizer.LocalizeDisplayString("and"));
}

static void SpriteFontAssetsMapExactly()
{
    True(FontDescriptor.TryFromAssetName(
        "Images/Interface/Components/Fonts/SegoeUI_15_Bold", out var body));
    Equal("SegoeUI_15_Bold", body.Name);
    Equal(15f, body.Size);
    True(body.Bold);

    True(FontDescriptor.TryFromAssetName(
        "Images\\Interface\\Components\\Fonts\\SegoeUI_UltraTiny", out var tiny));
    Equal(8f, tiny.Size);
    True(!tiny.Bold);

    True(!FontDescriptor.TryFromAssetName("Images/Interface/Icons/Unknown", out _));
}

static void ZeroWidthFormatCharactersAreIgnored()
{
    True(CjkText.IsIgnorableFormat('\u200B'));
    True(CjkText.IsIgnorableFormat('\uFEFF'));
    True(!CjkText.IsIgnorableFormat('A'));
    True(!CjkText.IsIgnorableFormat('汉'));
}

static void ShelfPackingCrossesToNewPage()
{
    var allocator = new GlyphAtlasAllocator(8, 8, 8);

    True(allocator.TryAllocate(8, 5, out var first));
    True(allocator.TryAllocate(8, 4, out var second));

    Equal(0, first.PageIndex);
    Equal(0, first.X);
    Equal(0, first.Y);
    Equal(1, second.PageIndex);
    Equal(0, second.X);
    Equal(0, second.Y);
    Equal(2, allocator.PageCount);
}

static void AtlasAllocationStopsAtEightPages()
{
    var state = new GlyphAtlasCacheState(1024, 1024, 8);
    for (var page = 0; page < 8; page++)
    {
        True(state.TryAllocate(1024, 1024, out var allocation));
        Equal(page, allocation.PageIndex);
        state.RecordPageCreated(allocation.PageIndex);
        state.RecordGlyphCached();
    }

    True(!state.TryAllocate(1, 1, out _));
    Equal(8, state.AllocatedPageCount);
    var diagnostics = state.GetDiagnostics();
    Equal(8, diagnostics.GlyphTextureCount);
    Equal(32L * 1024 * 1024, diagnostics.CurrentRgbaBytes);
    Equal(32L * 1024 * 1024, diagnostics.PeakRgbaBytes);
    Equal(1L, diagnostics.BudgetRejectionCount);
}

static void FaultedAtlasRejectsAllocationWithoutClearingLedger()
{
    var state = new GlyphAtlasCacheState(4, 4, 8);
    True(state.TryAllocate(4, 4, out var first));
    state.RecordPageCreated(first.PageIndex);
    state.RecordGlyphCached();

    state.MarkFaulted();

    True(!state.TryAllocate(1, 1, out _));
    Equal(1, state.AllocatedPageCount);
    var diagnostics = state.GetDiagnostics();
    Equal(1, diagnostics.GlyphCount);
    Equal(1, diagnostics.GlyphTextureCount);
    Equal(1, diagnostics.AtlasPageCount);
    Equal(64L, diagnostics.CurrentRgbaBytes);
    Equal(64L, diagnostics.PeakRgbaBytes);
    Equal(0L, diagnostics.BudgetRejectionCount);
    True(diagnostics.IsFaulted);
}

static void DeviceResetRetainsLiveResources()
{
    var state = new GlyphAtlasCacheState(4, 4, 8);
    True(state.TryAllocate(4, 4, out var first));
    state.RecordPageCreated(first.PageIndex);
    state.RecordGlyphCached();
    state.MarkFaulted();

    Equal(GlyphAtlasResetAction.RetainLivePages,
        GlyphAtlasResetDecision.Evaluate(totalPages: 1, livePages: 1));
    state.RecoverRetainedResourcesAfterDeviceReset();

    var reset = state.GetDiagnostics();
    Equal(1, reset.GlyphCount);
    Equal(1, reset.AtlasPageCount);
    Equal(64L, reset.CurrentRgbaBytes);
    Equal(64L, reset.PeakRgbaBytes);
    True(!reset.IsFaulted);
    True(state.TryAllocate(4, 4, out var next));
    Equal(1, next.PageIndex);
}

static void DeviceResetClearsReleasedResources()
{
    var state = new GlyphAtlasCacheState(4, 4, 8);
    True(state.TryAllocate(4, 4, out var first));
    state.RecordPageCreated(first.PageIndex);
    state.RecordGlyphCached();
    state.MarkFaulted();

    Equal(GlyphAtlasResetAction.ReleaseAllPages,
        GlyphAtlasResetDecision.Evaluate(totalPages: 1, livePages: 0));
    state.ResetAfterResourcesReleased();

    var reset = state.GetDiagnostics();
    Equal(0, reset.GlyphCount);
    Equal(0, reset.AtlasPageCount);
    Equal(0L, reset.CurrentRgbaBytes);
    Equal(64L, reset.PeakRgbaBytes);
    True(!reset.IsFaulted);
    True(state.TryAllocate(4, 4, out var rebuilt));
    Equal(0, rebuilt.PageIndex);
}

static void MixedResetResourcesRemainFaulted()
{
    Equal(GlyphAtlasResetAction.KeepFaulted,
        GlyphAtlasResetDecision.Evaluate(totalPages: 2, livePages: 1));
}

static void FailedAtlasAllocationsDoNotPolluteState()
{
    var state = new GlyphAtlasCacheState(4, 4, 1);
    True(!state.TryAllocate(5, 1, out _));
    Equal(0, state.AllocatedPageCount);

    True(state.TryAllocate(4, 4, out var only));
    Equal(0, only.PageIndex);
    True(!state.TryAllocate(1, 1, out _));
    Equal(1, state.AllocatedPageCount);

    var diagnostics = state.GetDiagnostics();
    Equal(0, diagnostics.GlyphCount);
    Equal(0, diagnostics.GlyphTextureCount);
    Equal(0, diagnostics.AtlasPageCount);
    Equal(0L, diagnostics.CurrentRgbaBytes);
    Equal(0L, diagnostics.PeakRgbaBytes);
    Equal(2L, diagnostics.BudgetRejectionCount);
}

static void GlyphDiagnosticsChargeActualAtlasPages()
{
    var state = new GlyphAtlasCacheState(1024, 1024, 8);
    True(state.TryAllocate(32, 32, out var first));
    state.RecordPageCreated(first.PageIndex);
    state.RecordGlyphCached();
    True(state.TryAllocate(32, 32, out _));
    state.RecordGlyphCached();

    var onePage = state.GetDiagnostics();
    Equal(2, onePage.GlyphCount);
    Equal(2, onePage.GlyphTextureCount);
    Equal(1, onePage.AtlasPageCount);
    Equal(4L * 1024 * 1024, onePage.CurrentRgbaBytes);
    Equal(4L * 1024 * 1024, onePage.PeakRgbaBytes);

    True(state.TryAllocate(1024, 1024, out var secondPage));
    Equal(1, secondPage.PageIndex);
    state.RecordPageCreated(secondPage.PageIndex);
    state.RecordGlyphCached();

    var twoPages = state.GetDiagnostics();
    Equal(3, twoPages.GlyphCount);
    Equal(3, twoPages.GlyphTextureCount);
    Equal(2, twoPages.AtlasPageCount);
    Equal(8L * 1024 * 1024, twoPages.CurrentRgbaBytes);
    Equal(8L * 1024 * 1024, twoPages.PeakRgbaBytes);
}

static void TextureBindingScanFindsEveryReference()
{
    var target = new object();
    var other = new object();
    var pixelTextures = new[] { target, other, target, null, target };
    var vertexTextures = new[] { other, target, target, null };

    var pixelSlots = TextureBindingSlots.FindReferenceSlots(
        target, pixelTextures.Length, slot => pixelTextures[slot]);
    var vertexSlots = TextureBindingSlots.FindReferenceSlots(
        target, vertexTextures.Length, slot => vertexTextures[slot]);

    True(pixelSlots.SequenceEqual(new[] { 0, 2, 4 }));
    True(vertexSlots.SequenceEqual(new[] { 1, 2 }));
}

static void AtlasAllocatorIsAtomicUnderConcurrency()
{
    const int workerCount = 64;
    var allocator = new GlyphAtlasAllocator(16, 16, 2);
    using var start = new System.Threading.ManualResetEventSlim(false);
    var workers = Enumerable.Range(0, workerCount)
        .Select(_ => Task.Run(() =>
        {
            start.Wait();
            return allocator.TryAllocate(4, 4, out var allocation)
                ? allocation
                : null;
        }))
        .ToArray();

    start.Set();
    Task.WaitAll(workers);

    var allocations = workers.Select(worker => worker.Result).Where(result => result != null).ToArray();
    Equal(32, allocations.Length);
    Equal(2, allocator.PageCount);
    foreach (var allocation in allocations)
    {
        True(allocation.X >= 0 && allocation.Y >= 0);
        True(allocation.X + allocation.Width <= 16);
        True(allocation.Y + allocation.Height <= 16);
    }
    for (var left = 0; left < allocations.Length; left++)
        for (var right = left + 1; right < allocations.Length; right++)
            True(allocations[left].PageIndex != allocations[right].PageIndex ||
                 !Overlaps(allocations[left], allocations[right]));
}

static void TraceWriteFailuresNeverEscape()
{
    var reachedFallback = false;
    TraceWriteGuard.Try(() => throw new IOException("simulated trace failure"));
    reachedFallback = true;
    True(reachedFallback);
}

static void RuntimeTraceRecordsMetrics()
{
    var descriptor = new FontDescriptor("SegoeUI_15_Bold", 15f, true);
    var metrics = new RuntimeTextTraceMetrics
    {
        X = 12.5f,
        Y = 8f,
        Width = 90.25f,
        Height = 18f,
        MissingGlyphs = 2,
    };
    var line = RuntimeTextTrace.FormatLine("draw", "Final text", descriptor, null, metrics,
        new DateTime(2026, 7, 12, 1, 2, 3, DateTimeKind.Utc));
    using var document = System.Text.Json.JsonDocument.Parse(line);
    var root = document.RootElement;
    Equal("Final text", root.GetProperty("text").GetString());
    Equal("SegoeUI_15_Bold|15|True", root.GetProperty("font").GetString());
    Equal(12.5f, root.GetProperty("x").GetSingle());
    Equal(90.25f, root.GetProperty("width").GetSingle());
    Equal(2, root.GetProperty("missingGlyphs").GetInt32());
}

static void DeferredGlyphsAreDeduplicated()
{
    var queue = new DeferredGlyphQueue<string>();
    True(queue.Enqueue("font|4E2D", "first"));
    True(!queue.Enqueue("font|4E2D", "duplicate"));
    True(queue.Enqueue("font|6587", "second"));
    Equal(2, queue.Count);
    var drained = queue.Drain();
    True(drained.SequenceEqual(new[] { "first", "second" }));
    Equal(0, queue.Count);
    Equal(0, queue.Drain().Count);
}

static bool Overlaps(GlyphAtlasAllocation left, GlyphAtlasAllocation right)
{
    return left.X < right.X + right.Width &&
           right.X < left.X + left.Width &&
           left.Y < right.Y + right.Height &&
           right.Y < left.Y + left.Height;
}

static void True(bool value) { if (!value) throw new InvalidOperationException("Expected true."); }
static void Equal<T>(T expected, T actual)
{
    if (!EqualityComparer<T>.Default.Equals(expected, actual))
        throw new InvalidOperationException($"Expected '{expected}', actual '{actual}'.");
}


static void Throws<TException>(Action action) where TException : Exception
{
    try { action(); }
    catch (TException) { return; }
    throw new InvalidOperationException($"Expected {typeof(TException).Name}.");
}


static string B64(string value) => Convert.ToBase64String(System.Text.Encoding.UTF8.GetBytes(value));

sealed class FakeWordProcessor
{
    public object ChunkFont = new();
    public string Word;
    public float CurrentX;
    public float WidthOfTextSoFar;
    public float WidthOfSpace = 1f;
    public System.Text.StringBuilder TextSoFar = new();
    public int MaxLineWidthAllowed;
    public float WrappedLineShiftX = 0f;
    public float LineHeight = 0f;
    public bool AppendSpaceBeforeNextWord;
    public FakeStringSplitter WordsInLine;
    public int OriginalCalls;
    public int FinishedLines;
    public List<string> Emitted = new();

    public FakeWordProcessor(string word, int width)
    {
        Word = word;
        MaxLineWidthAllowed = width;
        WordsInLine = new FakeStringSplitter(Array.Empty<string>());
    }

    private void ProcessChunk_Normal_Word()
    {
        OriginalCalls++;
        Word = WordsInLine.Next();
    }

    private void ProcessChunk_Normal_FinishFullLine()
    {
        Emitted.Add(TextSoFar.ToString());
        FinishedLines++;
        TextSoFar.Clear();
        WidthOfTextSoFar = 0f;
        CurrentX = WrappedLineShiftX;
        AppendSpaceBeforeNextWord = false;
    }
}

struct FakeStringSplitter
{
    private readonly string[] _values;
    private int _index;
    public FakeStringSplitter(string[] values) { _values = values; _index = 0; }
    public string Next() => _index < _values.Length ? _values[_index++] : null;
}
