using System.Text;
using AtG.RuntimeText;

#if LEGACY_MANUAL_RUNNER
var tests = new (string Name, Action Body)[]
{
    ("Concept links preserve their machine key", ConceptLinkPreservesKey),
    ("Raw formatting tags round-trip unchanged", RawTagsRoundTrip),
    ("Dynamic config tags with pipes remain raw", DynamicConfigTagWithPipeRemainsRaw),
    ("Plural selectors with two pipes remain raw", PluralSelectorWithTwoPipesRemainsRaw),
    ("Only allowlisted keys become concept links", OnlyAllowlistedKeysBecomeConceptLinks),
    ("Rich localization changes display text but preserves keys and raw tags", RichLocalizationPreservesStructure),
    ("Display registrations reject conflicts and markup injection", DisplayRegistrationsRejectUnsafeValues),
    ("Runtime display map localizes exact and standalone dynamic values", RuntimeDisplayMapLoads),
    ("Runtime display fragments tolerate UI spacing variants", RuntimeDisplayFragmentsTolerateUiSpacing),
    ("Generated runtime display map loads the reported dynamic fallbacks", GeneratedRuntimeDisplayMapLoads),
    ("Diplomacy tooltip bullets localize around concept links", DiplomacyTooltipBulletsLocalize),
    ("Markup-bearing display strings apply rich fragments", MarkupBearingDisplayStringsApplyRichFragments),
    ("Markup-bearing display strings also apply generated plain fragments", MarkupBearingDisplayStringsApplyPlainFragments),
    ("Dynamic tooltip fallbacks localize standalone and rich-text segments", DynamicTooltipFallbacksLocalize),
    ("Diplomacy from connector and all tribe names localize", DiplomacyFromAndFactionNamesLocalize),
    ("Wasteful and clan-title tooltip fragments localize without reordering links", WastefulAndClanTitleFragmentsLocalize),
    ("Tile-detail rich text preserves localized concept links and wrapped city text", TileDetailFallbacksLocalize),
    ("Split mood-tooltip fragments localize without changing the UI composition", RuntimeDisplayMoodFragmentsLocalize),
    ("Runtime display fragments localize plain nodes without breaking concept links", RuntimeDisplayFragmentsPreserveLinks),
    ("Runtime display fallback localizes declared concept-link labels without changing keys", RuntimeDisplayConceptLinkFallbacksLocalize),
    ("Scoped rich-text fragments preserve concept links", RuntimeDisplayRichTextFragmentsPreserveLinks),
    ("Chinese concept links collapse inherited English word spaces", RuntimeDisplayConceptSpacingPreservesLinks),
    ("Runtime display templates preserve runtime arguments", RuntimeDisplayTemplatesPreserveArguments),
    ("Game date banners use a strict localized date format", GameDatesLocalizeExactly),
    ("CJK line breaks respect punctuation", CjkBreaksRespectPunctuation),
    ("CJK fitting breaks preserve punctuation and grapheme clusters", CjkFittingBreaksPreserveTextElements),
    ("CJK word layout splits only at invisible line boundaries", CjkWordLayoutUsesLineBoundaries),
    ("CJK word bridge preserves ASCII and wraps CJK without spaces", CjkWordBridgePreservesOriginalPath),
    ("CJK word bridge localizes configured rich phrase sequences", CjkWordBridgeLocalizesTokenizedRichTextPhrase),
    ("CJK word bridge localizes tokenized Roman faction names", CjkWordBridgeLocalizesTokenizedRomanFactionNames),
    ("CJK word bridge localizes configured rich-text templates", CjkWordBridgeLocalizesTokenizedRichTextTemplate),
    ("CJK word bridge removes split winter-clause source advances", CjkWordBridgeRemovesWinterResidualWords),
    ("Display templates localize only exact approved strings", ExactTemplatesOnly),
    ("Localization cache invalidates as one generation", LocalizationCacheInvalidatesGeneration),
    ("SpriteFont asset names map to exact runtime descriptors", SpriteFontAssetsMapExactly),
    ("CJK raster size is calibrated independently from the SpriteFont asset size", CjkRasterSizeIsCalibrated),
    ("Font descriptor cache keys are stable allocations", FontDescriptorCacheKeyIsStable),
    ("CJK baselines are calibrated against the original SpriteFont sizes", CjkBaselineIsCalibrated),
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
    ("Priority glyph queue deduplicates and promotes live requests", PriorityGlyphQueuePromotesLiveRequests),
    ("Priority glyph queue peek preserves the next request", PriorityGlyphQueuePeekPreservesRequest),
    ("Frame upload budget is shared across pumps", FrameBudgetIsSharedAcrossPumps),
    ("Glyph alpha conversion handles positive and negative stride", GlyphAlphaConversionPreservesRows),
    ("Provisional glyph metrics remain stable after raster measurement", ProvisionalMetricsRemainStable),
    ("Glyph metric cache reports only the first reservation as cold", GlyphMetricReservationIsColdOnce),
    ("Runtime glyph warmset parser validates deterministic v1 records", RuntimeGlyphWarmsetParses),
    ("Prefix-width CJK wrapping avoids repeated substring measurement", PrefixWidthCjkWrapping),
    ("Atlas allocator enforces warm page and frame creation limits", AtlasAllocatorHonorsPageLimits),
    ("Performance JSON records scheduler frame counters", PerformanceTraceRecordsSchedulerCounters),
};
var failures = 0;
foreach (var test in tests)
{
    try { test.Body(); Console.WriteLine($"PASS {test.Name}"); }
    catch (Exception ex) { failures++; Console.Error.WriteLine($"FAIL {test.Name}: {ex.Message}"); }
}
return failures == 0 ? 0 : 1;
#endif

// The named cases below are executed by XunitBridge.cs through dotnet test.
return;

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
        "P\t" + B64("Content") + "\t" + B64("\u6ee1\u8db3"),
        "P\t" + B64(",") + "\t" + B64("\u3001"),
        "P\t" + B64(", or") + "\t" + B64("\u3001\u6216"),
        "P\t" + B64("Range") + "\t" + B64("\u8303\u56f4"),
        "F\t" + B64("seafaring") + "\t" + B64("\u822a\u6d77"),
        "F\t" + B64("Mounted") + "\t" + B64("\u9a91\u4e58"),
        "P\t" + B64("\u0080Max") + "\t" + B64("\u0080\u6700\u9ad8"),
        "P\t" + B64("\u0080No extra") + "\t" + B64("\u0080\u65e0\u989d\u5916"),
        "F\t" + B64("Content") + "\t" + B64("\u6ee1\u8db3"),
        "F\t" + B64("engage in ") + "\t" + B64("\u5377\u5165"),
        "B\t" + B64("STONE_LARGE") + "\t" + B64("\u5927\u578b\u77f3\u6599\u77ff\u5e8a"),
        "C\t" + B64("CLAN") + "\t" + B64("Clan") + "\t" + B64("\u6c0f\u65cf"),
        "E\t" + B64("Close") + "\t" + B64("\u5173\u95ed"),
    });
    DisplayStringLocalizer.Load(new StringReader(lines));

    Equal("\u5173\u95ed", DisplayStringLocalizer.LocalizeDisplayString("Close"));
    Equal("\u6ee1\u8db3", DisplayStringLocalizer.LocalizeDisplayString("Content"));
    Equal("\u3001", DisplayStringLocalizer.LocalizeDisplayString(","));
    Equal("\u3001\u6216", DisplayStringLocalizer.LocalizeDisplayString(", or"));
    Equal("\u8303\u56f4", DisplayStringLocalizer.LocalizeDisplayString("Range"));
    Equal("\u822a\u6d77", DisplayStringLocalizer.LocalizeRichText("seafaring"));
    Equal("\u5bf9\u9a91\u4e58\u5355\u4f4d\u51cf\u534a", DisplayStringLocalizer.LocalizeRichText("\u5bf9Mounted\u5355\u4f4d\u51cf\u534a"));
    Equal("\u0080\u6700\u9ad8", DisplayStringLocalizer.LocalizeRichText("\u0080Max"));
    Equal("\u0080\u65e0\u989d\u5916", DisplayStringLocalizer.LocalizeRichText("\u0080No extra"));
    Equal("\u59cb\u7ec8\u6ee1\u8db3", DisplayStringLocalizer.LocalizeDisplayString("\u59cb\u7ec8Content"));
    Equal("\u59cb\u7ec8[Content|MOOD]", DisplayStringLocalizer.LocalizeDisplayString("\u59cb\u7ec8[Content|MOOD]"));
    Equal("\u8bad\u7ec3[\u6c0f\u65cf|CLAN]",
        DisplayStringLocalizer.LocalizeRichText("Train [Clan|CLAN]"));
    Equal("\u5377\u5165Brawls",
        DisplayStringLocalizer.LocalizeRichText("engage in Brawls"));
    Equal("\u4f60\u5df2\u8bc6\u522b\u5927\u578b\u77f3\u6599\u77ff\u5e8a\u3002",
        DisplayStringLocalizer.LocalizeRichText("\u4f60\u5df2\u8bc6\u522b[STONE_LARGE]\u3002"));
    Equal("[UNREGISTERED_TAG]",
        DisplayStringLocalizer.LocalizeRichText("[UNREGISTERED_TAG]"));
    Equal("[COLOR:NEGATIVE]\u4fdd\u6301[/COLOR]",
        DisplayStringLocalizer.LocalizeRichText("[COLOR:NEGATIVE]\u4fdd\u6301[/COLOR]"));
}

static void GeneratedRuntimeDisplayMapLoads()
{
    var path = Path.Combine(FindRepositoryRoot(), "patch", "Content", "Text",
        "AtG.RuntimeText.tsv");
    True(File.Exists(path));

    DisplayStringLocalizer.ResetForTests();
    using (var reader = File.OpenText(path)) DisplayStringLocalizer.Load(reader);

    Equal("\u4f60\u5df2\u8bc6\u522b\u5927\u578b\u77f3\u6599\u77ff\u5e8a\u3002", DisplayStringLocalizer.LocalizeRichText(
        "\u4f60\u5df2\u8bc6\u522b[STONE_LARGE]\u3002"));
    Equal("\u5df2\u8bc6\u522b\u7f8a\u7fa4\u3002", DisplayStringLocalizer.LocalizeRichText("\u5df2\u8bc6\u522b[SHEEP]\u3002"));
    Equal("[UNREGISTERED_TAG]", DisplayStringLocalizer.LocalizeRichText("[UNREGISTERED_TAG]"));
    Equal("中立者（小部族）", DisplayStringLocalizer.LocalizeRichText("Neutrals（小部族）"));
    Equal("会见中立者（小部族）才能提出请求或宣战。",
        DisplayStringLocalizer.LocalizeRichText("会见Neutrals（小部族）才能提出请求或宣战。"));

    Equal("会痴迷于", DisplayStringLocalizer.LocalizeRichText(
        "become obsessed with the idea of"));
    Equal("会痴迷于", DisplayStringLocalizer.LocalizeRichText(
        "become\u00a0obsessed\u200bwith the idea of"));
    Equal("[COLOR:NEGATIVE]会痴迷于[/COLOR]", DisplayStringLocalizer.LocalizeRichText(
        "[COLOR:NEGATIVE]become obsessed with the idea of[/COLOR]"));
    Equal("[会痴迷于|DESIRE]", DisplayStringLocalizer.LocalizeRichText(
        "[become obsessed with the idea of|DESIRE]"));
    Equal("无法在[SETTLEMENT]内过冬，或作为[居民|RESIDENT]居住在[建筑|STRUCTURE]中",
        DisplayStringLocalizer.LocalizeRichText(
            "unable to spend the winter inside the [SETTLEMENT] or as the [Resident|RESIDENT] of a [Structure|STRUCTURE]"));
    Equal("被迫从事[主动|ACTIVE][职业|PROFESSION]，且既不在[SETTLEMENT]内，也不以[居民|RESIDENT]身份住在[建筑|STRUCTURE]中",
        DisplayStringLocalizer.LocalizeRichText(
            "forced into an [Active|ACTIVE] [Profession|PROFESSION] where they're neither within the [SETTLEMENT] nor the [Resident|RESIDENT] of a [Structure|STRUCTURE]"));
    Equal("• -1，因边界过近（相距不超过6格）。", DisplayStringLocalizer.LocalizeRichText(
        "• -1, borders being too close (within 6 tiles)."));
    Equal("• -1，因边界过近（相距不超过3格）。", DisplayStringLocalizer.LocalizeRichText(
        "• -1, borders being too close (within 3 tiles)."));
    for (var distance = 1; distance <= 12; distance++)
    {
        var unit = distance == 1 ? "tile" : "tiles";
        var expected = $"因边界过近（相距不超过{distance}格）。";
        foreach (var source in new[]
        {
            $"borders being too close ({distance} {unit} apart or less.)",
            $"borders being too close ({distance} {unit} apart or less).",
        })
        {
            Equal("• -1，" + expected, DisplayStringLocalizer.LocalizeRichText(
                "• -1, " + source));
            Equal(expected, DisplayStringLocalizer.LocalizeDisplayString(source));
            Equal("，" + expected, DisplayStringLocalizer.LocalizeDisplayString(
                ", " + source));
        }
    }
    Equal("无剩余移动力。", DisplayStringLocalizer.LocalizeRichText("无移动力 remaining."));
    Equal("强盗头目 (强盗 5)", DisplayStringLocalizer.LocalizeRichText(
        "Bandit Leader (Bandits 5)"));
    Equal("领袖特质（随和）", DisplayStringLocalizer.LocalizeRichText(
        "Leader Trait (随和)"));
    Equal("领袖特质（随和）", DisplayStringLocalizer.LocalizeRichText(
        "Leader 特质（随和）"));
    Equal("领袖特质", DisplayStringLocalizer.LocalizeRichText("Leader Trait"));
    Equal("领袖特质", DisplayStringLocalizer.LocalizeRichText("Leader 特质"));
    Equal("传闻有一座中立小麦农场", DisplayStringLocalizer.LocalizeRichText(
        "传闻有一个Neutral 小麦农场"));
    var westernFaction = new FakeWordProcessor("Western", 200);
    westernFaction.WordsInLine = new FakeStringSplitter(new[] { "Roman", "Empire", "tail" });
    CjkWordWrapCore.ProcessWord(westernFaction,
        (_, text) => new CjkMeasuredText(text.Length, 1f));
    Equal("西罗马帝国", westernFaction.TextSoFar.ToString());
    Equal("tail", westernFaction.Word);
    Equal(0, westernFaction.OriginalCalls);

    var easternFaction = new FakeWordProcessor("Eastern", 200);
    easternFaction.WordsInLine = new FakeStringSplitter(new[] { "Roman", "Empire", "tail" });
    CjkWordWrapCore.ProcessWord(easternFaction,
        (_, text) => new CjkMeasuredText(text.Length, 1f));
    Equal("东罗马帝国", easternFaction.TextSoFar.ToString());
    Equal("tail", easternFaction.Word);
    Equal(0, easternFaction.OriginalCalls);
    Equal("[升级|LEVEL]", DisplayStringLocalizer.LocalizeRichText(
        "[Level Up|LEVEL]"));
    Equal("[升级|LEVEL]", DisplayStringLocalizer.LocalizeRichText(
        "[Level-Up|LEVEL]"));
    Equal("• +1，因宗教信仰相同。", DisplayStringLocalizer.LocalizeRichText(
        "• +1, shared religious beliefs."));
    Equal("• -1，因背弃共同宗教信仰。", DisplayStringLocalizer.LocalizeRichText(
        "• -1, abandoning shared religious beliefs."));
    Equal("• +2, 共同宗教信仰及Leader 特质（虔诚）", DisplayStringLocalizer.LocalizeRichText(
        "• +2, shared religious beliefs plus Leader Trait（虔诚）"));
    Equal("• -3, 背弃共同宗教信仰及Leader 特质（虔诚）", DisplayStringLocalizer.LocalizeRichText(
        "• -3, abandoning shared religious beliefs plus Leader Trait（虔诚）"));
    Equal("-2, 善待敌对领袖（匈人）", DisplayStringLocalizer.LocalizeRichText(
        "-2, being nice to Enemy（匈人）"));
    Equal("+2, 苛待敌对领袖（匈人）", DisplayStringLocalizer.LocalizeRichText(
        "+2, being mean to Enemy（匈人）"));
    Equal("+1, 善待友方领袖（卡尔皮人）", DisplayStringLocalizer.LocalizeRichText(
        "+1, being nice to Friend（卡尔皮人）"));
    Equal("-1, 苛待友方领袖（卡尔皮人）", DisplayStringLocalizer.LocalizeRichText(
        "-1, being mean to Friend（卡尔皮人）"));
    Equal("缺少足够的财富（还差10）。", DisplayStringLocalizer.LocalizeRichText(
        "lacking sufficient 财富 (10 more needed)."));
    Equal("• 缺少足够的财富（还差10）。", DisplayStringLocalizer.LocalizeRichText(
        "• lacking sufficient 财富 (10 more needed)."));
    Equal("缺少足够的食物（还差5）。", DisplayStringLocalizer.LocalizeRichText(
        "You lack sufficient 食物 (5 more needed)."));
    Equal("• 缺少足够的食物（还差5）。", DisplayStringLocalizer.LocalizeRichText(
        "• You lack sufficient 食物 (5 more needed)."));
    Equal("\u6311\u8D77\u6218\u4E89", DisplayStringLocalizer.LocalizeRichText("Make War"));
    Equal("\u897f\u7f57\u9a6c\u5e1d\u56fd", DisplayStringLocalizer.LocalizeRichText("The Western Roman Empire"));
    Equal("\u897f\u7f57\u9a6c\u5e1d\u56fd", DisplayStringLocalizer.LocalizeRichText("Western Roman Empire"));
    Equal("\u897f\u7f57\u9a6c", DisplayStringLocalizer.LocalizeRichText("Western Roman"));
    Equal("\u897f\u7f57\u9a6c\u72ec\u7acb\u6d3e", DisplayStringLocalizer.LocalizeRichText("Western Roman Independents"));
    Equal("\u897f\u7f57\u9a6c\u53db\u519b", DisplayStringLocalizer.LocalizeRichText("Western Roman Rebels"));
    Equal("\u897f\u7f57\u9a6c\uff08\u72ec\u7acb\u6d3e\uff09", DisplayStringLocalizer.LocalizeRichText("Western Roman (I)"));
    Equal("\u897f\u7f57\u9a6c\uff08\u53db\u519b\uff09", DisplayStringLocalizer.LocalizeRichText("Western Roman (R)"));
}

static string FindRepositoryRoot()
{
    for (var directory = new DirectoryInfo(AppContext.BaseDirectory); directory is not null; directory = directory.Parent)
    {
        if (File.Exists(Path.Combine(directory.FullName, "AtG.Patch.sln")) &&
            Directory.Exists(Path.Combine(directory.FullName, "patch")))
        {
            return directory.FullName;
        }
    }

    throw new DirectoryNotFoundException("Could not locate the repository root from the test output directory.");
}

static void RuntimeDisplayFragmentsTolerateUiSpacing()
{
    DisplayStringLocalizer.ResetForTests();
    DisplayStringLocalizer.RegisterPlainTextFragment("become obsessed with the idea of", "会痴迷于");

    Equal("会痴迷于", DisplayStringLocalizer.LocalizeRichText(
        "become\u00a0obsessed\u200bwith the idea of"));
}

static void DiplomacyTooltipBulletsLocalize()
{
    DisplayStringLocalizer.ResetForTests();
    foreach (var key in new[] { "RL", "INFLUENCE", "REPUTATION" })
        DisplayStringLocalizer.RegisterConceptKey(key);
    DisplayStringLocalizer.RegisterConceptDisplay("RL", "Relationship Level", "关系等级");
    DisplayStringLocalizer.RegisterConceptDisplay("INFLUENCE", "Influence", "影响力");
    DisplayStringLocalizer.RegisterConceptDisplay("REPUTATION", "Reputation", "声誉");
    DisplayStringLocalizer.RegisterPlainTextFragment("• Default is +0.", "• 默认值为+0。");
    DisplayStringLocalizer.RegisterPlainTextFragment("Default is ", "默认值为");
    DisplayStringLocalizer.RegisterPlainTextFragment(" from ", "来自");
    DisplayStringLocalizer.RegisterPlainTextFragment("from ", "来自");
    DisplayStringLocalizer.RegisterPlainTextFragment("-1 from ", "-1来自");
    DisplayStringLocalizer.RegisterPlainTextFragment("+0 from ", "+0来自");
    DisplayStringLocalizer.RegisterPlainTextFragment(", suffering differing religious beliefs.", "，因宗教信仰不同而承受惩罚。");
    DisplayStringLocalizer.RegisterPlainTextFragment(", abandoning shared religious beliefs.", "，因背弃共同宗教信仰。");
    DisplayStringLocalizer.RegisterPlainTextFragment("abandoning shared religious beliefs.", "因背弃共同宗教信仰。");
    DisplayStringLocalizer.RegisterPlainTextFragment("abandoning shared religious beliefs plus ", "背弃共同宗教信仰及");
    DisplayStringLocalizer.RegisterPlainTextFragment("shared religious beliefs plus ", "共同宗教信仰及");
    DisplayStringLocalizer.RegisterPlainTextFragment("differing religious beliefs.", "因宗教信仰不同而承受惩罚。");
    DisplayStringLocalizer.RegisterPlainTextFragment("Leader Trait", "领袖特质");
    DisplayStringLocalizer.RegisterPlainTextFragment("The", "");
    DisplayStringLocalizer.RegisterPlainTextFragment("The Peucini", "佩乌奇尼人");
    DisplayStringLocalizer.RegisterRichTextFragment("[Relationship Level|RL].", "[关系等级|RL]。");
    DisplayStringLocalizer.RegisterRichTextFragment("[Influence|INFLUENCE].", "[影响力|INFLUENCE]。");
    DisplayStringLocalizer.RegisterRichTextFragment("[Reputation|REPUTATION].", "[声誉|REPUTATION]。");

    Equal("• 默认值为+0。", DisplayStringLocalizer.LocalizeRichText("• Default is +0."));
    Equal("默认值为+7", DisplayStringLocalizer.LocalizeDisplayString("Default is +7"));
    Equal("来自", DisplayStringLocalizer.LocalizeDisplayString(" from "));
    Equal("来自", DisplayStringLocalizer.LocalizeDisplayString("from "));
    Equal("• -1来自[关系等级|RL]。",
        DisplayStringLocalizer.LocalizeRichText("• -1 from [Relationship Level|RL]."));
    Equal("• +0来自[影响力|INFLUENCE]。",
        DisplayStringLocalizer.LocalizeRichText("• +0 from [Influence|INFLUENCE]."));
    Equal("• +0来自[声誉|REPUTATION]。",
        DisplayStringLocalizer.LocalizeRichText("• +0 from [Reputation|REPUTATION]."));
    Equal("• -1，因宗教信仰不同而承受惩罚。",
        DisplayStringLocalizer.LocalizeRichText("• -1, suffering differing religious beliefs."));
    Equal("• -1，因背弃共同宗教信仰。",
        DisplayStringLocalizer.LocalizeRichText("• -1, abandoning shared religious beliefs."));
    Equal("• +2, 共同宗教信仰及领袖特质（虔诚）",
        DisplayStringLocalizer.LocalizeRichText(
            "• +2, shared religious beliefs plus Leader Trait（虔诚）"));
    Equal("• -3, 背弃共同宗教信仰及领袖特质（虔诚）",
        DisplayStringLocalizer.LocalizeRichText(
            "• -3, abandoning shared religious beliefs plus Leader Trait（虔诚）"));
    Equal("因宗教信仰不同而承受惩罚。",
        DisplayStringLocalizer.LocalizeDisplayString("differing religious beliefs."));
    Equal("佩乌奇尼人", DisplayStringLocalizer.LocalizeDisplayString("The Peucini"));
    Equal("", DisplayStringLocalizer.LocalizeDisplayString("The"));
}

static void MarkupBearingDisplayStringsApplyRichFragments()
{
    DisplayStringLocalizer.ResetForTests();
    DisplayStringLocalizer.RegisterRichTextFragment("become obsessed with the idea of", "\u4f1a\u75f4\u8ff7\u4e8e");

    Equal("[COLOR:EMPHASIS]\u4f1a\u75f4\u8ff7\u4e8e[/COLOR]",
        DisplayStringLocalizer.LocalizeDisplayString(
            "[COLOR:EMPHASIS]become obsessed with the idea of[/COLOR]"));
}

static void MarkupBearingDisplayStringsApplyPlainFragments()
{
    DisplayStringLocalizer.ResetForTests();
    DisplayStringLocalizer.RegisterPlainTextFragment(
        ", borders being too close (within 6 tiles).",
        "，因边界过近（相距不超过6格）。");
    DisplayStringLocalizer.RegisterPlainTextFragment(
        ", shared religious beliefs.",
        "，因宗教信仰相同。");

    Equal("[COLOR:NEGATIVE]-1，因边界过近（相距不超过6格）。[/COLOR]",
        DisplayStringLocalizer.LocalizeDisplayString(
            "[COLOR:NEGATIVE]-1, borders being too close (within 6 tiles).[/COLOR]"));
    Equal("[COLOR:POSITIVE]+1，因宗教信仰相同。[/COLOR]",
        DisplayStringLocalizer.LocalizeDisplayString(
            "[COLOR:POSITIVE]+1, shared religious beliefs.[/COLOR]"));
}

static void DynamicTooltipFallbacksLocalize()
{
    DisplayStringLocalizer.ResetForTests();
    DisplayStringLocalizer.RegisterPlainText("become obsessed with the idea of", "会痴迷于");
    DisplayStringLocalizer.RegisterPlainText("Minor Leader", "小部族领袖");
    DisplayStringLocalizer.RegisterPlainText("Strong Leader", "强势领袖");
    DisplayStringLocalizer.RegisterPlainText("No extra", "无额外");
    DisplayStringLocalizer.RegisterPlainText("This Army is resting.", "该军队正在休整。");
    DisplayStringLocalizer.RegisterPlainTextFragment("become obsessed with the idea of ", "会痴迷于");
    DisplayStringLocalizer.RegisterPlainTextFragment("No movement remaining.", "无剩余移动力。");
    DisplayStringLocalizer.RegisterPlainTextFragment("This Army is encamped", "该军队正在驻营");
    DisplayStringLocalizer.RegisterPlainTextFragment("Already ", "已");
    DisplayStringLocalizer.RegisterPlainTextFragment("Caravan has arrived!", "商队已抵达！");
    DisplayStringLocalizer.RegisterPlainTextFragment("Caravan", "商队");
    DisplayStringLocalizer.RegisterPlainTextFragment("Late March", "三月下旬");
    DisplayStringLocalizer.RegisterPlainTextFragment("Coal Deposits", "煤矿床");
    DisplayStringLocalizer.RegisterPlainTextFragment("Bandit Stronghold", "强盗营地");
    DisplayStringLocalizer.RegisterPlainTextFragment("Pillage Bandits", "劫掠强盗营地");
    DisplayStringLocalizer.RegisterPlainTextFragment("\u52AB\u63A0Bandits", "\u52AB\u63A0\u5F3A\u76D7\u8425\u5730");
    DisplayStringLocalizer.RegisterPlainTextFragment("This ", "该");
    DisplayStringLocalizer.RegisterPlainTextFragment("this ", "本");
    DisplayStringLocalizer.RegisterPlainTextFragment("No ", "无");
    DisplayStringLocalizer.RegisterPlainTextFragment("turn", "回合");
    DisplayStringLocalizer.RegisterRichTextFragment("become obsessed with the idea of ", "会痴迷于");
    DisplayStringLocalizer.RegisterRichTextFragment("[SCORE]", "得分");
    DisplayStringLocalizer.RegisterRichTextFragment("[TREASURE]", "财富");
    DisplayStringLocalizer.RegisterRichTextFragment("[HORSES]", "马匹");
    DisplayStringLocalizer.RegisterRichTextFragment("[WEAPONS]", "武器");
    DisplayStringLocalizer.RegisterRichTextFragment("[CARAVAN]", "商队");
    DisplayStringLocalizer.RegisterRichTextFragment("[COAL]", "煤");

    Equal("会痴迷于", DisplayStringLocalizer.LocalizeDisplayString("become obsessed with the idea of"));
    Equal("[COLOR:NEGATIVE]会痴迷于[/COLOR]",
        DisplayStringLocalizer.LocalizeDisplayString(
            "[COLOR:NEGATIVE]become obsessed with the idea of [/COLOR]"));
    Equal("小部族领袖", DisplayStringLocalizer.LocalizeRichText("Minor Leader"));
    Equal("强势领袖", DisplayStringLocalizer.LocalizeRichText("Strong Leader"));
    Equal("无额外", DisplayStringLocalizer.LocalizeRichText("No extra"));
    Equal("无剩余移动力。", DisplayStringLocalizer.LocalizeRichText("No movement remaining."));
    Equal("该军队正在休整。", DisplayStringLocalizer.LocalizeRichText("This Army is resting."));
    Equal("本回合", DisplayStringLocalizer.LocalizeRichText("this turn"));
    Equal("已identified", DisplayStringLocalizer.LocalizeRichText("Already identified"));
    Equal("商队已抵达！", DisplayStringLocalizer.LocalizeRichText("Caravan has arrived!"));
    Equal("三月下旬", DisplayStringLocalizer.LocalizeRichText("Late March"));
    Equal("煤矿床", DisplayStringLocalizer.LocalizeRichText("Coal Deposits"));
    Equal("劫掠强盗营地", DisplayStringLocalizer.LocalizeRichText("Pillage Bandits"));
    Equal("\u52AB\u63A0\u5F3A\u76D7\u8425\u5730", DisplayStringLocalizer.LocalizeRichText("\u52AB\u63A0Bandits"));
    Equal("得分 财富 马匹 武器 商队 煤",
        DisplayStringLocalizer.LocalizeRichText("[SCORE] [TREASURE] [HORSES] [WEAPONS] [CARAVAN] [COAL]"));
}

static void DiplomacyFromAndFactionNamesLocalize()
{
    DisplayStringLocalizer.ResetForTests();
    DisplayStringLocalizer.RegisterConceptKey("INFLUENCE");
    DisplayStringLocalizer.RegisterConceptKey("FACTION");
    DisplayStringLocalizer.RegisterConceptDisplay("INFLUENCE", "Influence", "\u5f71\u54cd\u529b");

    var factions = new Dictionary<string, string>(StringComparer.Ordinal)
    {
        ["The Goths"] = "\u54e5\u7279\u4eba",
        ["The Huns"] = "\u5308\u4eba",
        ["The Vandals"] = "\u6c6a\u8fbe\u5c14\u4eba",
        ["The Alemanni"] = "\u963f\u52d2\u66fc\u5c3c\u4eba",
        ["The Picts"] = "\u76ae\u514b\u7279\u4eba",
        ["The Lombards"] = "\u4f26\u5df4\u7b2c\u4eba",
        ["The Franks"] = "\u6cd5\u5170\u514b\u4eba",
        ["The Slavs"] = "\u65af\u62c9\u592b\u4eba",
        ["The Saxons"] = "\u6492\u514b\u900a\u4eba",
        ["The Avars"] = "\u963f\u74e6\u5c14\u4eba"
    };
    foreach (var faction in factions)
        DisplayStringLocalizer.RegisterConceptDisplay("FACTION", faction.Key, faction.Value);
    var neutralFactions = new Dictionary<string, string>(StringComparer.Ordinal)
    {
        ["The Suebi"] = "\u82cf\u7ef4\u6bd4\u4eba",
        ["The Frisii"] = "\u5f17\u91cc\u897f\u4eba",
        ["The Jutes"] = "\u6731\u7279\u4eba",
        ["The Burgundians"] = "\u52c3\u826e\u7b2c\u4eba",
        ["The Scirii"] = "\u65af\u57fa\u91cc\u4eba",
        ["The Bulgars"] = "\u4fdd\u52a0\u5c14\u4eba",
        ["The Thuringians"] = "\u56fe\u6797\u6839\u4eba",
        ["The Tencteri"] = "\u5766\u514b\u7279\u91cc\u4eba",
        ["The Cherusci"] = "\u5207\u9c81\u897f\u4eba",
        ["The Hermunduri"] = "\u8d6b\u5c14\u8499\u675c\u91cc\u4eba",
        ["The Chatti"] = "\u67e5\u8482\u4eba",
        ["The Rugii"] = "\u9c81\u5409\u4eba",
        ["The Heruli"] = "\u8d6b\u9c81\u5229\u4eba",
        ["The Gepids"] = "\u683c\u76ae\u5fb7\u4eba",
        ["The Sarmatians"] = "\u8428\u5c14\u9a6c\u7279\u4eba",
        ["The Bavarians"] = "\u5df4\u4f10\u5229\u4e9a\u4eba",
        ["The Khazars"] = "\u53ef\u8428\u4eba",
        ["The Berbers"] = "\u67cf\u67cf\u5c14\u4eba",
        ["The Angles"] = "\u76ce\u683c\u9c81\u4eba",
        ["The Varangians"] = "\u74e6\u5170\u5409\u4eba",
        ["The Magyars"] = "\u9a6c\u624e\u5c14\u4eba",
        ["The Danes"] = "\u4e39\u9ea6\u4eba",
        ["The Thervingi"] = "\u7279\u5c14\u6587\u5409\u4eba",
        ["The Greuthungi"] = "\u683c\u9c81\u901a\u5409\u4eba",
        ["The Bastarnae"] = "\u5df4\u65af\u5854\u5948\u4eba",
        ["The Peucini"] = "\u4f69\u4e4c\u5947\u5c3c\u4eba",
        ["The Scythians"] = "\u65af\u57fa\u6cf0\u4eba",
        ["The Alans"] = "\u963f\u5170\u4eba",
        ["The Getae"] = "\u76d6\u5854\u4eba",
        ["The Dacians"] = "\u8fbe\u5951\u4e9a\u4eba",
        ["The Jats"] = "\u8d3e\u7279\u4eba",
        ["The Geats"] = "\u8036\u963f\u7279\u4eba",
        ["The Massagetae"] = "\u9a6c\u8428\u9769\u592a\u4eba",
        ["The Aspasioi"] = "\u963f\u65af\u5e15\u897f\u5965\u4f0a\u4eba",
        ["The Dahae"] = "\u8fbe\u8d6b\u4eba",
        ["The Issedones"] = "\u4f0a\u585e\u591a\u6d85\u65af\u4eba",
        ["The Wusun"] = "\u4e4c\u5b59\u4eba",
        ["The Sacae"] = "\u585e\u8fe6\u4eba",
        ["The Varini"] = "\u74e6\u91cc\u5c3c\u4eba",
        ["The Carini"] = "\u5361\u91cc\u5c3c\u4eba",
        ["The Gutones"] = "\u53e4\u6258\u5185\u65af\u4eba",
        ["The Cimbri"] = "\u8f9b\u5e03\u91cc\u4eba",
        ["The Teutons"] = "\u6761\u987f\u4eba",
        ["The Chauci"] = "\u8003\u57fa\u4eba",
        ["The Lemovii"] = "\u83b1\u83ab\u7ef4\u4eba",
        ["The Quadi"] = "\u5938\u8fea\u4eba",
        ["The Iazyges"] = "\u4f0a\u963f\u9f50\u683c\u65af\u4eba",
        ["The Marcomanni"] = "\u9a6c\u79d1\u66fc\u5c3c\u4eba",
        ["The Costoboci"] = "\u79d1\u65af\u6258\u535a\u5947\u4eba",
        ["The Hasdingi"] = "\u54c8\u65af\u4e01\u5409\u4eba",
        ["The Lacringi"] = "\u62c9\u514b\u6797\u5409\u4eba",
        ["The Buri"] = "\u5e03\u91cc\u4eba",
        ["The Cotini"] = "\u79d1\u8482\u5c3c\u4eba",
        ["The Carpi"] = "\u5361\u5c14\u76ae\u4eba",
        ["The Taifali"] = "\u6cf0\u6cd5\u5229\u4eba",
        ["The Victohali"] = "\u7ef4\u514b\u6258\u54c8\u5229\u4eba",
        ["The Salians"] = "\u8428\u5229\u5b89\u4eba"
    };
    foreach (var faction in neutralFactions)
        DisplayStringLocalizer.RegisterConceptDisplay("FACTION", faction.Key, faction.Value);

    DisplayStringLocalizer.RegisterPlainTextFragment("from ", "\u6765\u81ea");
    DisplayStringLocalizer.RegisterPlainTextFragment(" from ", "\u6765\u81ea");

    Equal("[\u5f71\u54cd\u529b|INFLUENCE]\u6765\u81ea[\u5308\u4eba|FACTION]",
        DisplayStringLocalizer.LocalizeRichText("[Influence|INFLUENCE] from [The Huns|FACTION]"));
    foreach (var faction in factions)
        Equal($"[{faction.Value}|FACTION]",
            DisplayStringLocalizer.LocalizeRichText($"[{faction.Key}|FACTION]"));
    foreach (var faction in neutralFactions)
        Equal($"[{faction.Value}|FACTION]",
            DisplayStringLocalizer.LocalizeRichText($"[{faction.Key}|FACTION]"));
}

static void WastefulAndClanTitleFragmentsLocalize()
{
    DisplayStringLocalizer.ResetForTests();
    DisplayStringLocalizer.RegisterConceptKey("PRODUCE");
    DisplayStringLocalizer.RegisterConceptKey("FACTION");
    DisplayStringLocalizer.RegisterConceptDisplay("PRODUCE", "Resource Production", "资源产出");
    DisplayStringLocalizer.RegisterConceptDisplay("FACTION", "The Goths", "哥特人");
    DisplayStringLocalizer.RegisterPlainTextFragment("自己建造建筑降低", "（由自己建造的建筑）降低");
    DisplayStringLocalizer.RegisterPlainTextFragment(" in.", "。");
    DisplayStringLocalizer.Register("资源产出自己建造建筑降低-10%",
        "资源产出（由自己建造的建筑）降低-10%");
    DisplayStringLocalizer.Register("若位于地块补给等级低于1，则会受到伤害1",
        "若所在地块的补给等级低于1，则会受到伤害。");

    Equal("[资源产出|PRODUCE]（由自己建造的建筑）降低-10%",
        DisplayStringLocalizer.LocalizeRichText("[Resource Production|PRODUCE]自己建造建筑降低-10%"));
    Equal("资源产出（由自己建造的建筑）降低-10%",
        DisplayStringLocalizer.LocalizeRichText("资源产出自己建造建筑降低-10%"));
    Equal("若所在地块的补给等级低于1，则会受到伤害。",
        DisplayStringLocalizer.LocalizeRichText("若位于地块补给等级低于1，则会受到伤害1"));
    Equal("。", DisplayStringLocalizer.LocalizeRichText(" in."));
    Equal("[哥特人|FACTION]",
        DisplayStringLocalizer.LocalizeRichText("[The Goths|FACTION]"));
}

static void RuntimeDisplayFragmentsPreserveLinks()
{
    DisplayStringLocalizer.ResetForTests();
    DisplayStringLocalizer.RegisterConceptKey("CLAN");
    DisplayStringLocalizer.RegisterConceptKey("UPGRADE");
    DisplayStringLocalizer.RegisterConceptKey("ACTIVE");
    DisplayStringLocalizer.RegisterConceptKey("SETTLED");
    DisplayStringLocalizer.RegisterConceptKey("SETTLEMENT");
    DisplayStringLocalizer.RegisterConceptKey("TILE");
    DisplayStringLocalizer.RegisterConceptKey("PROFESSION");
    DisplayStringLocalizer.RegisterConceptKey("RESIDENT");
    DisplayStringLocalizer.RegisterConceptKey("STRUCTURE");
    DisplayStringLocalizer.RegisterConceptKey("WARRIOR");
    DisplayStringLocalizer.RegisterConceptDisplay("CLAN", "Clan", "\u6c0f\u65cf");
    DisplayStringLocalizer.RegisterConceptDisplay("UPGRADE", "Upgrade", "\u5347\u7ea7");
    DisplayStringLocalizer.RegisterConceptDisplay("ACTIVE", "Active", "\u4e3b\u52a8");
    DisplayStringLocalizer.RegisterConceptDisplay("SETTLED", "Settled", "\u5b9a\u5c45");
    DisplayStringLocalizer.RegisterConceptDisplay("SETTLEMENT", "Settlement", "\u5b9a\u5c45\u70b9");
    DisplayStringLocalizer.RegisterConceptDisplay("TILE", "Tile", "\u5730\u5757");
    DisplayStringLocalizer.RegisterConceptDisplay("PROFESSION", "Profession", "\u804c\u4e1a");
    DisplayStringLocalizer.RegisterConceptDisplay("RESIDENT", "Resident", "\u5c45\u6c11");
    DisplayStringLocalizer.RegisterConceptDisplay("STRUCTURE", "Structure", "\u5efa\u7b51");
    DisplayStringLocalizer.RegisterConceptDisplay("WARRIOR", "Warrior", "\u6218\u58eb");
    DisplayStringLocalizer.RegisterPlainTextFragment("there's another ", "\u53e6\u6709");
    DisplayStringLocalizer.RegisterPlainTextFragment("engage in ", "\u5377\u5165");
    DisplayStringLocalizer.RegisterPlainTextFragment("Brawls", "\u6597\u6bb4");
    DisplayStringLocalizer.RegisterPlainTextFragment("into", "\u8fdb\u5165");
    DisplayStringLocalizer.RegisterPlainTextFragment("forced into a ", "\u88ab\u8feb\u4ece\u4e8b");
    DisplayStringLocalizer.RegisterPlainTextFragment("forced into an ", "\u88ab\u8feb\u4ece\u4e8b");
    DisplayStringLocalizer.RegisterPlainTextFragment(" within the ", "\uff0c\u4e14\u5728");
    DisplayStringLocalizer.RegisterPlainTextFragment(" outside the ", "\uff0c\u4e14\u4e0d\u5728");
    DisplayStringLocalizer.RegisterPlainTextFragment("No", "\u65e0");
    DisplayStringLocalizer.RegisterPlainTextFragment("commit Theft", "\u72af\u4e0b\u76d7\u7a83");
    DisplayStringLocalizer.RegisterPlainTextFragment("engage in Brawls", "\u53c2\u4e0e\u6597\u6bb4");
    DisplayStringLocalizer.RegisterPlainTextFragment("there's another", "\u53e6\u6709");
    DisplayStringLocalizer.RegisterPlainTextFragment(" on the same", "\u4f4d\u4e8e\u540c\u4e00");
    DisplayStringLocalizer.RegisterPlainTextFragment("forced into a", "\u88ab\u8feb\u4ece\u4e8b");
    DisplayStringLocalizer.RegisterPlainTextFragment("forced into an", "\u88ab\u8feb\u4ece\u4e8b");
    DisplayStringLocalizer.RegisterPlainTextFragment(" where they're neither within the ", "\uFF0C\u65E2\u4E0D\u5728");
    DisplayStringLocalizer.RegisterPlainTextFragment(" nor the ", "\uFF0C\u4E5F\u4E0D\u4F5C\u4E3A");
    DisplayStringLocalizer.RegisterPlainTextFragment(" within the", "\uff0c\u4e14\u5728");
    DisplayStringLocalizer.RegisterPlainTextFragment(" outside of", "\uff0c\u4e14\u4e0d\u5728");
    DisplayStringLocalizer.RegisterPlainTextFragment(" outside the", "\uff0c\u4e14\u4e0d\u5728");
    DisplayStringLocalizer.RegisterPlainTextFragment(" or as the", "\u5185\uff0c\u6216\u4f5c\u4e3a");
    DisplayStringLocalizer.RegisterPlainTextFragment(" at", "\uff0c\u9a7b\u7559\u5728");
    DisplayStringLocalizer.RegisterPlainTextFragment("seafaring", "\u822a\u6d77");

    Equal("\u53e6\u6709[\u6c0f\u65cf|CLAN]\u53c2\u4e0e\u6597\u6bb4",
        DisplayStringLocalizer.LocalizeRichText(
            "there's another [Clan|CLAN]engage in Brawls"));
    Equal("\u88ab\u8feb\u4ece\u4e8b[\u6c0f\u65cf|CLAN]",
        DisplayStringLocalizer.LocalizeRichText("forced into a [Clan|CLAN]"));
    Equal("\u88ab\u8feb\u4ece\u4e8b[\u5b9a\u5c45|SETTLED][\u4e3b\u52a8|ACTIVE]\uff0c\u4e14\u5728[\u6c0f\u65cf|CLAN]",
        DisplayStringLocalizer.LocalizeRichText(
            "forced into an [Settled|SETTLED][Active|ACTIVE] within the [Clan|CLAN]"));
    Equal("\u88ab\u8feb\u4ece\u4e8b[\u5b9a\u5c45|SETTLED][\u4e3b\u52a8|ACTIVE]\uff0c\u4e14\u5728[\u6c0f\u65cf|CLAN]",
        DisplayStringLocalizer.LocalizeRichText(
            "forced into an [Settled|SETTLED][Active|ACTIVE] within the[Clan|CLAN]"));
    Equal("\u88ab\u8feb\u4ece\u4e8b[\u4e3b\u52a8|ACTIVE]\uff0c\u4e14\u4e0d\u5728[\u5b9a\u5c45\u70b9|SETTLEMENT]",
        DisplayStringLocalizer.LocalizeRichText(
            "forced into an [Active|ACTIVE] outside the [Settlement|SETTLEMENT]"));
    Equal("[\u5347\u7ea7|UPGRADE]",
        DisplayStringLocalizer.LocalizeRichText("[Upgrade|UPGRADE]"));
    Equal("\u65e0[\u5347\u7ea7|UPGRADE]",
        DisplayStringLocalizer.LocalizeRichText("No[Upgrade|UPGRADE]"));
    Equal("\u6c38\u8fdc\u4e0d\u4f1a\u72af\u4e0b\u76d7\u7a83\uff08\u7f6a\u884c\uff09",
        DisplayStringLocalizer.LocalizeRichText("\u6c38\u8fdc\u4e0d\u4f1acommit Theft\uff08\u7f6a\u884c\uff09"));
    Equal("\u53ef\u80fd\u4f1a\u53c2\u4e0e\u6597\u6bb4\uff08\u7f6a\u884c\uff09",
        DisplayStringLocalizer.LocalizeRichText("\u53ef\u80fd\u4f1aengage in Brawls\uff08\u7f6a\u884c\uff09"));
    Equal("\u5982\u679c\u53e6\u6709[\u6c0f\u65cf|CLAN]",
        DisplayStringLocalizer.LocalizeRichText("\u5982\u679cthere's another[Clan|CLAN]"));
    Equal("\u5982\u679c\u53e6\u6709[\u6c0f\u65cf|CLAN]\u4f4d\u4e8e\u540c\u4e00[\u5730\u5757|TILE]",
        DisplayStringLocalizer.LocalizeRichText(
            "\u5982\u679cthere's another[Clan|CLAN] on the same[Tile|TILE]"));
    Equal("\u5f88\u53ef\u80fd\u53d8\u5f97\u4e0d\u6ee1\u5728\u4e00\u5e74\u5185\uff0c\u5982\u679c\u88ab\u8feb\u4ece\u4e8b[\u804c\u4e1a|PROFESSION]\uff0c\u4e14\u4e0d\u5728[\u5b9a\u5c45\u70b9|SETTLEMENT]",
        DisplayStringLocalizer.LocalizeRichText(
            "\u5f88\u53ef\u80fd\u53d8\u5f97\u4e0d\u6ee1\u5728\u4e00\u5e74\u5185\uff0c\u5982\u679cforced into a[Profession|PROFESSION] outside of[Settlement|SETTLEMENT]"));
    Equal("\u5f88\u53ef\u80fd\u53d8\u5f97\u4e0d\u6ee1\u5728\u4e00\u5e74\u5185\uff0c\u5982\u679c\u88ab\u8feb\u4ece\u4e8b[\u804c\u4e1a|PROFESSION]",
        DisplayStringLocalizer.LocalizeRichText(
            "\u5f88\u53ef\u80fd\u53d8\u5f97\u4e0d\u6ee1\u5728\u4e00\u5e74\u5185\uff0c\u5982\u679cforced into an[Profession|PROFESSION]"));
    Equal("\u88ab\u8feb\u4ece\u4e8b[\u4e3b\u52a8|ACTIVE]\uFF0C\u65E2\u4E0D\u5728[\u5b9a\u5c45|SETTLED]\uFF0C\u4E5F\u4E0D\u4F5C\u4E3A[\u5c45\u6c11|RESIDENT]\uFF0C\u9A7B\u7559\u5728[\u5efa\u7B51|STRUCTURE]",
        DisplayStringLocalizer.LocalizeRichText(
            "forced into an [Active|ACTIVE] where they're neither within the [Settled|SETTLED] nor the [Resident|RESIDENT] at[Structure|STRUCTURE]"));
    Equal("\u5982\u679c\u88ab\u8feb\u4ece\u4e8b\u822a\u6d77[\u804c\u4e1a|PROFESSION]",
        DisplayStringLocalizer.LocalizeRichText("\u5982\u679c\u88ab\u8feb\u4ece\u4e8bseafaring[Profession|PROFESSION]"));
    Equal("\u5982\u679c\u88ab\u8feb\u4ece\u4e8b[\u4e3b\u52a8|ACTIVE]\uff0c\u4e14\u4e0d\u5728[\u5b9a\u5c45\u70b9|SETTLEMENT]",
        DisplayStringLocalizer.LocalizeRichText(
            "\u5982\u679cforced into a [Active|ACTIVE] outside the[Settlement|SETTLEMENT]"));
    Equal("\u5982\u679c\u88ab\u8feb\u4ece\u4e8b[\u6218\u58eb|WARRIOR]",
        DisplayStringLocalizer.LocalizeRichText("\u5982\u679cforced into a [Warrior|WARRIOR]"));
    Equal("\u5982\u679c\u65e0\u6cd5\u5728\u51ac\u5b63\u7559\u5728[\u5b9a\u5c45\u70b9|SETTLEMENT]\u5185\uff0c\u6216\u4f5c\u4e3a[\u5c45\u6c11|RESIDENT]\uff0c\u9a7b\u7559\u5728[\u5efa\u7b51|STRUCTURE]",
        DisplayStringLocalizer.LocalizeRichText(
            "\u5982\u679c\u65e0\u6cd5\u5728\u51ac\u5b63\u7559\u5728[Settlement|SETTLEMENT] or as the[Resident|RESIDENT] at[Structure|STRUCTURE]"));

    Equal("\u5982\u679c\u65e0\u6cd5\u5728\u51ac\u5b63\u7559\u5728[\u5b9a\u5c45\u70b9|SETTLEMENT]",
        DisplayStringLocalizer.LocalizeRichText(
            "\u5982\u679c\u65e0\u6cd5\u5728\u51ac\u5b63\u7559\u5728 [Settlement|SETTLEMENT]"));

    DisplayStringLocalizer.RegisterPlainText("This is among the largest fields ever found!", "\u8fd9\u662f\u8fc4\u4eca\u53d1\u73b0\u7684\u6700\u5927\u9ea6\u7530\u4e4b\u4e00\uff01");
    DisplayStringLocalizer.RegisterPlainTextFragment("Beehives can be", "\u8702\u5de2\u53ef\u88ab");
    DisplayStringLocalizer.RegisterPlainTextFragment("Herds of", "\u4e00\u7fa4");
    DisplayStringLocalizer.RegisterPlainTextFragment(" can be", "\u53ef\u88ab");
    DisplayStringLocalizer.RegisterPlainTextFragment("、 for", "、\u83b7\u5f97");
    DisplayStringLocalizer.RegisterPlainTextFragment(" for", "，\u83b7\u5f97");
    DisplayStringLocalizer.RegisterPlainTextFragment("and then used for other purposes by", "\u4e4b\u540e\u53ef\u7531");
    DisplayStringLocalizer.RegisterPlainTextFragment("on them.", "\u5728\u5176\u4e0a\u3002");
    DisplayStringLocalizer.RegisterPlainTextFragment("This is a particularly large herd!", "\u8fd9\u662f\u4e00\u5927\u7fa4\u52a8\u7269\uff01");
    DisplayStringLocalizer.RegisterPlainTextFragment("This is among the largest herds ever found!", "\u8fd9\u662f\u8fc4\u4eca\u53d1\u73b0\u7684\u6700\u5927\u517d\u7fa4\u4e4b\u4e00\uff01");
    Equal("\u8fd9\u662f\u8fc4\u4eca\u53d1\u73b0\u7684\u6700\u5927\u9ea6\u7530\u4e4b\u4e00\uff01",
        DisplayStringLocalizer.LocalizeDisplayString("This is among the largest fields ever found!"));
    Equal("\u8702\u5de2\u53ef\u88ab[\u91c7\u6536|HARVEST]",
        DisplayStringLocalizer.LocalizeRichText("Beehives can be[采收|HARVEST]"));
    Equal("\u4e00\u7fa4 [\u9a6c|ANIMAL]\u53ef\u88ab [\u91c7\u6536|HARVEST]，\u83b7\u5f97 [\u8089|MEAT]、\u83b7\u5f97 [\u76ae|PARCHMENT]\u5728\u5176\u4e0a\u3002",
        DisplayStringLocalizer.LocalizeRichText("Herds of [马|ANIMAL] can be [采收|HARVEST] for [肉|MEAT]、 for [皮|PARCHMENT]on them."));
    Equal("\u8fd9\u662f\u4e00\u5927\u7fa4\u52a8\u7269\uff01",
        DisplayStringLocalizer.LocalizeRichText("This is a particularly large herd!"));
}

static void TileDetailFallbacksLocalize()
{
    DisplayStringLocalizer.ResetForTests();
    DisplayStringLocalizer.RegisterConceptKey("SUPPLY");
    DisplayStringLocalizer.RegisterConceptKey("TERRAIN");
    DisplayStringLocalizer.RegisterConceptKey("DEFENSE");
    DisplayStringLocalizer.RegisterPlainText("Supply", "补给");
    DisplayStringLocalizer.RegisterPlainText("Terrain", "地形");
    DisplayStringLocalizer.RegisterPlainText("Defense", "防御");
    DisplayStringLocalizer.RegisterPlainTextFragment(
        "All that remains of a once-magnificent Roman City, abandoned",
        "昔日辉煌的罗马城市如今仅剩残迹，");
    DisplayStringLocalizer.RegisterPlainTextFragment("only recently.", "最近才被遗弃。");

    // The targeted TileTooltip RichTextLabel patch sends these strings through
    // TextFormatter; Chinese display text must retain the stable machine key.
    DisplayStringLocalizer.RegisterConceptDisplay("SUPPLY", "Supply", "补给");
    DisplayStringLocalizer.RegisterConceptDisplay("TERRAIN", "Terrain", "地形");
    DisplayStringLocalizer.RegisterConceptDisplay("DEFENSE", "Defense", "防御");
    Equal("[补给|SUPPLY]", DisplayStringLocalizer.LocalizeRichText("[Supply|SUPPLY]"));
    // SupplyInfo's fixed UI literal is rewritten to Chinese before it reaches
    // the runtime formatter; the formatter must retain its concept key.
    Equal("来自[地形|TERRAIN]",
        DisplayStringLocalizer.LocalizeRichText("来自[地形|TERRAIN]"));
    Equal("[防御|DEFENSE]", DisplayStringLocalizer.LocalizeRichText("[Defense|DEFENSE]"));

    Equal("补给", DisplayStringLocalizer.LocalizeDisplayString("Supply"));
    Equal("地形", DisplayStringLocalizer.LocalizeDisplayString("Terrain"));
    Equal("防御", DisplayStringLocalizer.LocalizeDisplayString("Defense"));
    Equal("昔日辉煌的罗马城市如今仅剩残迹，",
        DisplayStringLocalizer.LocalizeDisplayString(
            "All that remains of a once-magnificent Roman City, abandoned"));
    Equal("最近才被遗弃。", DisplayStringLocalizer.LocalizeDisplayString("only recently."));
}

static void RuntimeDisplayMoodFragmentsLocalize()
{
    DisplayStringLocalizer.ResetForTests();
    DisplayStringLocalizer.RegisterPlainTextFragment("When 高兴...", "当高兴时……");
    DisplayStringLocalizer.RegisterPlainTextFragment(" from being ", "，因为");
    DisplayStringLocalizer.RegisterPlainTextFragment(" from being", "，因为");
    DisplayStringLocalizer.RegisterPlainTextFragment("Ennobled", "已册封");
    DisplayStringLocalizer.RegisterPlainTextFragment("Enabled", "已启用");

    // GAME.BuildDescription_Mood emits its heading whole, while RecalcMood
    // exposes its reason in separate text nodes around a concept link.
    Equal("当高兴时……", DisplayStringLocalizer.LocalizeDisplayString("When 高兴..."));
    Equal("，因为", DisplayStringLocalizer.LocalizeDisplayString(" from being"));
    Equal("已册封", DisplayStringLocalizer.LocalizeDisplayString("Ennobled"));
    Equal("已启用", DisplayStringLocalizer.LocalizeDisplayString("Enabled"));
    Equal("+1心情，因为已册封",
        DisplayStringLocalizer.LocalizeRichText("+1心情 from being Ennobled"));
}

static void RuntimeDisplayRichTextFragmentsPreserveLinks()
{
    DisplayStringLocalizer.ResetForTests();
    DisplayStringLocalizer.RegisterConceptKey("ACTIVE");
    DisplayStringLocalizer.RegisterConceptKey("PROFESSION");
    DisplayStringLocalizer.RegisterConceptKey("LIVESTOCK");
    DisplayStringLocalizer.RegisterConceptKey("AGRICULTURE");
    DisplayStringLocalizer.RegisterConceptKey("CRAFTING");
    DisplayStringLocalizer.RegisterConceptKey("HONOR");
    DisplayStringLocalizer.RegisterConceptKey("METALWORKING");
    DisplayStringLocalizer.RegisterConceptKey("DISCOVERY");
    DisplayStringLocalizer.RegisterConceptKey("DISCIPLINE");
    DisplayStringLocalizer.RegisterConceptDisplay("ACTIVE", "Active", "主动");
    DisplayStringLocalizer.RegisterConceptDisplay("PROFESSION", "Profession", "职业");
    DisplayStringLocalizer.RegisterConceptDisplay("LIVESTOCK", "LIVESTOCK", "畜牧");
    DisplayStringLocalizer.RegisterConceptDisplay("AGRICULTURE", "AGRICULTURE", "农耕");
    DisplayStringLocalizer.RegisterConceptDisplay("CRAFTING", "CRAFTING", "工艺");
    DisplayStringLocalizer.RegisterConceptDisplay("HONOR", "HONOR", "荣耀");
    DisplayStringLocalizer.RegisterConceptDisplay("METALWORKING", "METALWORKING", "冶金");
    DisplayStringLocalizer.RegisterConceptDisplay("DISCOVERY", "DISCOVERY", "探索");
    DisplayStringLocalizer.RegisterConceptDisplay("DISCIPLINE", "Discipline", "纪律");
    DisplayStringLocalizer.RegisterRichTextFragment(
        "[Profession|PROFESSION] in the [LIVESTOCK] [Discipline|DISCIPLINE]",
        "[Profession|PROFESSION]，所属为[LIVESTOCK][Discipline|DISCIPLINE]");
    DisplayStringLocalizer.RegisterRichTextFragment(
        "[Profession|PROFESSION] in the [AGRICULTURE] [Discipline|DISCIPLINE]",
        "[Profession|PROFESSION]，所属为[AGRICULTURE][Discipline|DISCIPLINE]");
    DisplayStringLocalizer.RegisterRichTextFragment(
        "[Profession|PROFESSION] in the [CRAFTING] [Discipline|DISCIPLINE]",
        "[Profession|PROFESSION]，所属为[CRAFTING][Discipline|DISCIPLINE]");
    DisplayStringLocalizer.RegisterRichTextFragment(
        "[Profession|PROFESSION] in the [HONOR] [Discipline|DISCIPLINE]",
        "[Profession|PROFESSION]，所属为[HONOR][Discipline|DISCIPLINE]");
    DisplayStringLocalizer.RegisterRichTextFragment(
        "[Profession|PROFESSION] in the [METALWORKING] [Discipline|DISCIPLINE]",
        "[Profession|PROFESSION]，所属为[METALWORKING][Discipline|DISCIPLINE]");
    DisplayStringLocalizer.RegisterRichTextFragment(
        "[Profession|PROFESSION] in the [DISCOVERY] [Discipline|DISCIPLINE]",
        "[Profession|PROFESSION]，所属为[DISCOVERY][Discipline|DISCIPLINE]");

    Equal("[职业|PROFESSION]，所属为[LIVESTOCK][纪律|DISCIPLINE]",
        DisplayStringLocalizer.LocalizeRichText(
            "[Profession|PROFESSION] in the [LIVESTOCK] [Discipline|DISCIPLINE]"));
    Equal("[职业|PROFESSION]，所属为[AGRICULTURE][纪律|DISCIPLINE]",
        DisplayStringLocalizer.LocalizeRichText(
            "[Profession|PROFESSION] in the [AGRICULTURE] [Discipline|DISCIPLINE]"));
    Equal("[职业|PROFESSION]，所属为[CRAFTING][纪律|DISCIPLINE]",
        DisplayStringLocalizer.LocalizeRichText(
            "[Profession|PROFESSION] in the [CRAFTING] [Discipline|DISCIPLINE]"));
    Equal("[职业|PROFESSION]，所属为[HONOR][纪律|DISCIPLINE]",
        DisplayStringLocalizer.LocalizeRichText(
            "[Profession|PROFESSION] in the [HONOR] [Discipline|DISCIPLINE]"));
    Equal("[职业|PROFESSION]，所属为[METALWORKING][纪律|DISCIPLINE]",
        DisplayStringLocalizer.LocalizeRichText(
            "[Profession|PROFESSION] in the [METALWORKING] [Discipline|DISCIPLINE]"));
    Equal("[职业|PROFESSION]，所属为[DISCOVERY][纪律|DISCIPLINE]",
        DisplayStringLocalizer.LocalizeRichText(
            "[Profession|PROFESSION] in the [DISCOVERY] [Discipline|DISCIPLINE]"));
}

static void RuntimeDisplayConceptLinkFallbacksLocalize()
{
    DisplayStringLocalizer.ResetForTests();
    DisplayStringLocalizer.RegisterConceptKey("DESIRE");
    DisplayStringLocalizer.RegisterPlainText(
        "become obsessed with the idea of", "\u4f1a\u75f4\u8ff7\u4e8e");

    Equal("[\u4f1a\u75f4\u8ff7\u4e8e|DESIRE]",
        DisplayStringLocalizer.LocalizeRichText(
            "[become obsessed with the idea of|DESIRE]"));
}

static void RuntimeDisplayConceptSpacingPreservesLinks()
{
    DisplayStringLocalizer.ResetForTests();
    DisplayStringLocalizer.RegisterConceptKey("ACTIVE");
    DisplayStringLocalizer.RegisterConceptKey("PROFESSION");
    DisplayStringLocalizer.RegisterConceptKey("UNMAPPED");
    DisplayStringLocalizer.RegisterConceptDisplay("ACTIVE", "Active", "\u4e3b\u52a8");
    DisplayStringLocalizer.RegisterConceptDisplay("PROFESSION", "Profession", "\u804c\u4e1a");

    Equal("[\u4e3b\u52a8|ACTIVE][\u804c\u4e1a|PROFESSION]",
        DisplayStringLocalizer.LocalizeRichText("[Active|ACTIVE] [Profession|PROFESSION]"));
    Equal("[\u4e3b\u52a8|ACTIVE] [Unknown|UNMAPPED]",
        DisplayStringLocalizer.LocalizeRichText("[Active|ACTIVE] [Unknown|UNMAPPED]"));
}

static void RuntimeDisplayTemplatesPreserveArguments()
{
    DisplayStringLocalizer.ResetForTests();
    var lines = "T\t" + B64("Cannot {arg:1}.") + "\t" +
        B64("\u65e0\u6cd5{arg:1}\u3002");
    DisplayStringLocalizer.Load(new StringReader(lines));

    Equal("\u65e0\u6cd5Train\u3002",
        DisplayStringLocalizer.LocalizeDisplayString("Cannot Train."));
    Equal("\u65e0\u6cd5[Study|STUDY]\u3002",
        DisplayStringLocalizer.LocalizeRichText("Cannot [Study|STUDY]."));
}

static void GameDatesLocalizeExactly()
{
    DisplayStringLocalizer.ResetForTests();
    Equal("公元400年4月上旬",
        DisplayStringLocalizer.LocalizeDisplayString("Early April, 400 AD"));
    Equal("公元401年12月下旬",
        DisplayStringLocalizer.LocalizeDisplayString("Late December, 401 AD"));
    Equal("Early on, April 2014 was unusual.",
        DisplayStringLocalizer.LocalizeDisplayString("Early on, April 2014 was unusual."));
}

static void CjkBreaksRespectPunctuation()
{
    True(CjkText.CanBreakBetween('汉', '字'));
    True(!CjkText.CanBreakBetween('（', '汉'));
    True(!CjkText.CanBreakBetween('字', '）'));
    True(CjkText.RequiresDynamicGlyph('\u201C'));
    True(CjkText.RequiresDynamicGlyph('\u201D'));
    True(CjkText.RequiresDynamicGlyph('\u300A'));
    True(!CjkText.RequiresDynamicGlyph('\u200B'));
    True(!CjkText.CanBreakBetween('\u201C', '汉'));
    True(!CjkText.CanBreakBetween('汉', '\u201D'));
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

static void CjkWordBridgeLocalizesTokenizedRichTextPhrase()
{
    DisplayStringLocalizer.ResetForTests();
    DisplayStringLocalizer.RegisterRichTextFragment(
        "become obsessed with the idea of", "会痴迷于");
    var processor = new FakeWordProcessor("become", 200);
    processor.WordsInLine = new FakeStringSplitter(new[]
    {
        "obsessed", "with", "the", "idea", "of", "something",
    });

    CjkWordWrapCore.ProcessWord(processor,
        (_, text) => new CjkMeasuredText(text.Length, 1f));

    Equal("会痴迷于", processor.TextSoFar.ToString());
    Equal("something", processor.Word);
    Equal(0, processor.OriginalCalls);

    var nonMatch = new FakeWordProcessor("become", 200);
    nonMatch.WordsInLine = new FakeStringSplitter(new[]
    {
        "interested", "in", "something",
    });
    CjkWordWrapCore.ProcessWord(nonMatch,
        (_, text) => new CjkMeasuredText(text.Length, 1f));
    Equal(1, nonMatch.OriginalCalls);
    Equal("interested", nonMatch.Word);
}

static void CjkWordBridgeLocalizesTokenizedRomanFactionNames()
{
    DisplayStringLocalizer.ResetForTests();
    DisplayStringLocalizer.RegisterRichTextFragment("Western Roman Empire", "西罗马帝国");
    DisplayStringLocalizer.RegisterRichTextFragment("Eastern Roman Empire", "东罗马帝国");

    foreach (var (firstWord, expected) in new[]
    {
        ("Western", "西罗马帝国"),
        ("Eastern", "东罗马帝国"),
    })
    {
        var processor = new FakeWordProcessor(firstWord, 200);
        processor.WordsInLine = new FakeStringSplitter(new[] { "Roman", "Empire", "tail" });

        CjkWordWrapCore.ProcessWord(processor,
            (_, text) => new CjkMeasuredText(text.Length, 1f));

        Equal(expected, processor.TextSoFar.ToString());
        Equal("tail", processor.Word);
        Equal(0, processor.OriginalCalls);
    }
}

static void CjkWordBridgeLocalizesTokenizedRichTextTemplate()
{
    DisplayStringLocalizer.ResetForTests();
    DisplayStringLocalizer.RegisterTemplate("Leader Trait ({arg:0})", "领袖特质（{arg:0}）");
    DisplayStringLocalizer.RegisterTemplate("Leader 特质（{arg:0}）", "领袖特质（{arg:0}）");

    var english = new FakeWordProcessor("Leader", 200);
    english.WordsInLine = new FakeStringSplitter(new[] { "Trait", "(随和)", "tail" });
    CjkWordWrapCore.ProcessWord(english, (_, text) => new CjkMeasuredText(text.Length, 1f));
    Equal("领袖特质（随和）", english.TextSoFar.ToString());
    Equal("tail", english.Word);
    Equal(0, english.OriginalCalls);

    var mixed = new FakeWordProcessor("Leader", 200);
    mixed.WordsInLine = new FakeStringSplitter(new[] { "特质（随和）", "tail" });
    CjkWordWrapCore.ProcessWord(mixed, (_, text) => new CjkMeasuredText(text.Length, 1f));
    Equal("领袖特质（随和）", mixed.TextSoFar.ToString());
    Equal("tail", mixed.Word);
    Equal(0, mixed.OriginalCalls);

    var nonMatch = new FakeWordProcessor("Leader", 200);
    nonMatch.WordsInLine = new FakeStringSplitter(new[] { "Traits", "(随和)", "tail" });
    CjkWordWrapCore.ProcessWord(nonMatch, (_, text) => new CjkMeasuredText(text.Length, 1f));
    Equal(1, nonMatch.OriginalCalls);
    Equal("Traits", nonMatch.Word);
}

static void CjkWordBridgeRemovesWinterResidualWords()
{
    var processor = new FakeWordProcessor("\u5f88\u53ef\u80fd\u5982\u679cunable\u4ee5", 200);
    processor.WordsInLine = new FakeStringSplitter(new[] { "spend", "the", "winter", "inside", "the", "final" });
    CjkWordWrapCore.ProcessWord(processor, (_, text) => new CjkMeasuredText(text.Length, 1f));
    CjkWordWrapCore.ProcessWord(processor, (_, text) => new CjkMeasuredText(text.Length, 1f));
    CjkWordWrapCore.ProcessWord(processor, (_, text) => new CjkMeasuredText(text.Length, 1f));
    CjkWordWrapCore.ProcessWord(processor, (_, text) => new CjkMeasuredText(text.Length, 1f));
    CjkWordWrapCore.ProcessWord(processor, (_, text) => new CjkMeasuredText(text.Length, 1f));
    CjkWordWrapCore.ProcessWord(processor, (_, text) => new CjkMeasuredText(text.Length, 1f));
    True(processor.TextSoFar.ToString().IndexOf("\u65e0\u6cd5\u5728\u51ac\u5b63\u7559\u5728", StringComparison.Ordinal) >= 0);
    True(processor.TextSoFar.ToString().IndexOf("spend", StringComparison.Ordinal) < 0);
    True(processor.TextSoFar.ToString().IndexOf("winter", StringComparison.Ordinal) < 0);
    Equal("final", processor.Word);
}

static void ExactTemplatesOnly()
{
    DisplayStringLocalizer.Register("Clan {0} joined", "氏族{0}加入");
    Equal("氏族{0}加入", DisplayStringLocalizer.LocalizeDisplayString("Clan {0} joined"));
    Equal("and", DisplayStringLocalizer.LocalizeDisplayString("and"));
}

static void LocalizationCacheInvalidatesGeneration()
{
    DisplayStringLocalizer.ResetForTests();
    Equal("Status", DisplayStringLocalizer.LocalizeDisplayString("Status"));
    DisplayStringLocalizer.RegisterPlainText("Status", "\u72b6\u6001");
    Equal("\u72b6\u6001", DisplayStringLocalizer.LocalizeDisplayString("Status"));
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

static void CjkRasterSizeIsCalibrated()
{
    var descriptor = new FontDescriptor("SegoeUI_15_Bold", 15f, true);
    Equal(FontDescriptor.DefaultCjkScale, descriptor.CjkScale);
    Equal(15f * FontDescriptor.DefaultCjkScale, descriptor.RasterSize);
    True(descriptor.CacheKey.IndexOf("|cjk=1.15", StringComparison.Ordinal) >= 0);
}

static void FontDescriptorCacheKeyIsStable()
{
    var descriptor = new FontDescriptor("SegoeUI_15", 15f, false);
    var first = descriptor.CacheKey;
    var second = descriptor.CacheKey;
    True(ReferenceEquals(first, second));
    Equal("SegoeUI_15|15|False|cjk=1.15", first);
}

static void CjkBaselineIsCalibrated()
{
    Equal(-2f, new FontDescriptor("SegoeUI_9", 9f, false).CjkBaselineOffset);
    Equal(-3f, new FontDescriptor("SegoeUI_11_Bold", 11f, true).CjkBaselineOffset);
    Equal(-2f, new FontDescriptor("SegoeUI_13", 13f, false).CjkBaselineOffset);
    Equal(-3f, new FontDescriptor("SegoeUI_15_Bold", 15f, true).CjkBaselineOffset);
    Equal(-2f, new FontDescriptor("SegoeUI_18", 18f, false).CjkBaselineOffset);
    Equal(-1f, new FontDescriptor("SegoeUI_24_Bold", 24f, true).CjkBaselineOffset);
    Equal(0f, new FontDescriptor("SegoeUI_40_Bold", 40f, true).CjkBaselineOffset);
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
    Equal("SegoeUI_15_Bold|15|True|cjk=1.15", root.GetProperty("font").GetString());
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

static void PriorityGlyphQueuePromotesLiveRequests()
{
    var queue = new PriorityDeduplicatingQueue<string>(4, 3);
    True(queue.Enqueue("warm", "warm", 2));
    True(queue.Enqueue("background", "background", 3));
    True(!queue.Enqueue("warm", "duplicate", 1));
    True(queue.Promote("background", 0));
    True(queue.Enqueue("middle", "middle", 1));
    True(!queue.Enqueue("full", "full", 0));

    True(queue.TryDequeue(out var firstKey, out var first, out var firstPriority));
    Equal("background", firstKey);
    Equal("background", first);
    Equal(0, firstPriority);
    True(queue.TryDequeue(out _, out var second, out var secondPriority));
    Equal("warm", second);
    Equal(1, secondPriority);
    True(queue.TryDequeue(out _, out var third, out var thirdPriority));
    Equal("middle", third);
    Equal(1, thirdPriority);
}

static void PriorityGlyphQueuePeekPreservesRequest()
{
    var queue = new PriorityDeduplicatingQueue<string>(4, 3);
    True(queue.Enqueue("warm", "warm", 2));
    True(queue.Enqueue("live", "live", 0));

    True(queue.TryPeek(out var peekedKey, out var peeked, out var peekedPriority));
    Equal("live", peekedKey);
    Equal("live", peeked);
    Equal(0, peekedPriority);
    Equal(2, queue.Count);

    True(queue.TryDequeue(out var dequeuedKey, out var dequeued, out var dequeuedPriority));
    Equal(peekedKey, dequeuedKey);
    Equal(peeked, dequeued);
    Equal(peekedPriority, dequeuedPriority);
    Equal(1, queue.Count);
}

static void FrameBudgetIsSharedAcrossPumps()
{
    var budget = new FrameUploadBudget(2d, 1000L, 16, 1);
    budget.BeginFrame();
    True(budget.CanAttempt(requiresPageCreation: true));
    budget.RecordOperation(1L, pageCreated: true);
    True(!budget.CanAttempt(requiresPageCreation: true));
    True(budget.CanAttempt(requiresPageCreation: false));
    budget.RecordOperation(1L, pageCreated: false);
    True(!budget.CanAttempt(requiresPageCreation: false));

    budget.BeginFrame();
    for (var index = 0; index < 16; index++)
    {
        True(budget.CanAttempt(requiresPageCreation: false));
        budget.RecordOperation(0L, pageCreated: false);
    }
    True(!budget.CanAttempt(requiresPageCreation: false));
}

static void GlyphAlphaConversionPreservesRows()
{
    var positive = new byte[]
    {
        1, 2, 3, 10, 4, 5, 6, 20,
        7, 8, 9, 30, 10, 11, 12, 40,
    };
    var converted = GlyphAlphaConverter.FromBgra(positive, 2, 2, 8);
    True(converted.SequenceEqual(new byte[]
    {
        10, 10, 10, 10, 20, 20, 20, 20,
        30, 30, 30, 30, 40, 40, 40, 40,
    }));
    var negative = GlyphAlphaConverter.FromBgra(positive, 2, 2, -8);
    True(negative.SequenceEqual(new byte[]
    {
        30, 30, 30, 30, 40, 40, 40, 40,
        10, 10, 10, 10, 20, 20, 20, 20,
    }));

    var memory = System.Runtime.InteropServices.Marshal.AllocHGlobal(8);
    try
    {
        var bottomUp = new byte[]
        {
            7, 8, 9, 30,
            1, 2, 3, 10,
        };
        System.Runtime.InteropServices.Marshal.Copy(bottomUp, 0, memory, bottomUp.Length);
        var scan0 = IntPtr.Add(memory, 4);
        var pointerConverted = GlyphAlphaConverter.FromBgra(scan0, 1, 2, -4);
        True(pointerConverted.SequenceEqual(new byte[]
        {
            10, 10, 10, 10,
            30, 30, 30, 30,
        }));
    }
    finally
    {
        System.Runtime.InteropServices.Marshal.FreeHGlobal(memory);
    }
}

static void ProvisionalMetricsRemainStable()
{
    GlyphMetricsCache.ResetForTests();
    var descriptor = new FontDescriptor("SegoeUI_15", 15f, false);
    var provisional = GlyphMetricsCache.GetOrReserve(descriptor, '\u6c49');
    True(provisional.Provisional);
    var measured = GlyphMetricsCache.PublishMeasured(descriptor, '\u6c49', 99f, 88f);
    True(ReferenceEquals(provisional, measured));
    Equal(provisional.Advance, measured.Advance);
    Equal(provisional.LineHeight, measured.LineHeight);

    var warmMeasured = GlyphMetricsCache.PublishMeasured(descriptor, '\u5b57', 17f, 20f);
    True(!warmMeasured.Provisional);
    Equal(17f, warmMeasured.Advance);
    Equal(20f, warmMeasured.LineHeight);
}

static void GlyphMetricReservationIsColdOnce()
{
    GlyphMetricsCache.ResetForTests();
    var descriptor = new FontDescriptor("SegoeUI_15", 15f, false);
    var first = GlyphMetricsCache.GetOrReserve(descriptor, '\u6c49', out var firstReserved);
    var second = GlyphMetricsCache.GetOrReserve(descriptor, '\u6c49', out var secondReserved);

    True(firstReserved);
    True(!secondReserved);
    True(ReferenceEquals(first, second));
}

static void RuntimeGlyphWarmsetParses()
{
    var fontName = B64("SegoeUI_15_Bold");
    var characters = B64("\u4e2d\u6587");
    var text = "# AtG.RuntimeGlyphWarmset v1\n" +
               "W\t1\t" + fontName + "\t15\t1\t" + characters +
               "\tknowledge-screen-hovers,clan-screen-buttons\n";
    var entries = RuntimeGlyphWarmsetCatalog.Load(new StringReader(text));
    Equal(1, entries.Count);
    Equal(1, entries[0].Priority);
    Equal("SegoeUI_15_Bold", entries[0].FontName);
    Equal(15f, entries[0].Size);
    True(entries[0].Bold);
    Equal("\u4e2d\u6587", entries[0].Characters);
    Throws<InvalidDataException>(() => RuntimeGlyphWarmsetCatalog.Load(
        new StringReader("W\t0\t" + fontName + "\t15\t1\t" +
                         B64("\u4e2d\u4e2d") + "\tduplicate\n")));
}

static void PrefixWidthCjkWrapping()
{
    var text = "\u6c49\u5b57\u6d4b\u8bd5";
    var prefix = new[] { 0f, 1f, 2f, 3f, 4f };
    var pieces = CjkLineBreaker.SplitWord(text, 2f, 2f, prefix);
    True(pieces.SequenceEqual(new[] { "\u6c49\u5b57", "\u6d4b\u8bd5" }));

    var punctuationText = "\u6c49\uff0c\u5b57";
    var punctuationPrefix = new[] { 0f, 1f, 2f, 3f };
    Equal(2, CjkText.FindLongestFittingBreak(
        punctuationText, 0, 1f, punctuationPrefix));
}

static void AtlasAllocatorHonorsPageLimits()
{
    var allocator = new GlyphAtlasAllocator(4, 4, 2);
    True(allocator.TryAllocate(4, 4, 1, true, out var first));
    Equal(0, first.PageIndex);
    True(!allocator.TryAllocate(1, 1, 1, true, out _));
    True(!allocator.TryAllocate(1, 1, 2, false, out _));
    True(allocator.TryAllocate(1, 1, 2, true, out var second));
    Equal(1, second.PageIndex);
}

static void PerformanceTraceRecordsSchedulerCounters()
{
    var line = RuntimeTextPerformance.FormatLine(
        42L,
        new DateTime(2026, 7, 24, 1, 2, 3, DateTimeKind.Utc),
        "Budgeted",
        System.Diagnostics.Stopwatch.Frequency / 1000,
        System.Diagnostics.Stopwatch.Frequency / 2000,
        System.Diagnostics.Stopwatch.Frequency / 100,
        System.Diagnostics.Stopwatch.Frequency / 4000,
        4, 5, 6, 20, 14, 6, 7, 8, 9, 1, 2, 10, 11, 3);
    using var document = System.Text.Json.JsonDocument.Parse(line);
    var root = document.RootElement;
    Equal(42L, root.GetProperty("frame").GetInt64());
    Equal("Budgeted", root.GetProperty("mode").GetString());
    Equal(4, root.GetProperty("uploads").GetInt32());
    Equal(20, root.GetProperty("lookups").GetInt32());
    Equal(14, root.GetProperty("hits").GetInt32());
    Equal(0.7d, root.GetProperty("hitRate").GetDouble());
    Equal(11, root.GetProperty("maxReady").GetInt32());
    Equal(3, root.GetProperty("atlasPages").GetInt32());
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
    public string str;
    public char delimeter;
    public int startIndex;
    public int endIndex;
    public int length;

    public FakeStringSplitter(string[] values)
    {
        str = string.Join(" ", values);
        delimeter = ' ';
        startIndex = 0;
        length = str.Length;
        endIndex = str.IndexOf(delimeter);
        if (endIndex < 0) endIndex = length;
    }

    public string Next()
    {
        if (startIndex >= length) return null;
        var value = str.Substring(startIndex, endIndex - startIndex);
        startIndex = endIndex + 1;
        if (endIndex != length)
        {
            endIndex = str.IndexOf(delimeter, startIndex);
            if (endIndex < 0) endIndex = length;
        }
        return value;
    }
}
