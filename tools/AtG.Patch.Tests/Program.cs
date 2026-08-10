using AtG.Patch.Core.Build;
using AtG.ManagedRewrite;
using dnlib.DotNet;
using dnlib.DotNet.Emit;

#if LEGACY_MANUAL_RUNNER
var tests = new (string Name, Action Body)[]
{
    ("Content hash is stable across input ordering", ContentHashIsStable),
    ("Content hash changes with file content", ContentHashChanges),
    ("Build cache validates all declared outputs", BuildCacheValidatesOutputs),
    ("Build cache records parallel stages atomically", BuildCacheRecordsParallelStages),
    ("Managed rewriter replaces one exact ldstr", ManagedRewriterReplacesExactString),
    ("Rewrite map loads exact context", RewriteMapLoadsExactContext),
    ("Clan-list distance unit covers singular and plural forms", ClanListDistanceUnitCoversSingularAndPluralForms),
    ("Diplomacy war actions keep their distinct meanings", DiplomacyWarActionsKeepTheirDistinctMeanings),
    ("Leader-trait tooltip prefix preserves its dynamic value", LeaderTraitTooltipPrefixPreservesDynamicValue),
    ("Clan-training connectors preserve their dynamic labels", ClanTrainingConnectorsPreserveDynamicLabels),
    ("Caravan action buttons preserve transaction direction at every quantity", CaravanActionButtonsPreserveTransactionDirection),
    ("Caravan unavailable tooltip localizes the plural concept label", CaravanUnavailableTooltipLocalizesPluralConceptLabel),
    ("Discipline tooltip config map covers all six entries", DisciplineTooltipConfigMapCoversAllSixEntries),
    ("Obsessed intensity tooltip config preserves its rich-text boundary", ObsessedIntensityTooltipConfigPreservesRichTextBoundary),
    ("Deserted-location exploration configs cover all event outcomes", DesertedLocationExplorationConfigsCoverAllEventOutcomes),
    ("Flax deposit tooltips cover all field sizes", FlaxDepositTooltipsCoverAllFieldSizes),
    ("Clan-feud tooltips and pack warning use exact safe mappings", ClanFeudTooltipsAndPackWarningUseExactSafeMappings),
    ("Besiege tooltip maps every composed literal", BesiegeTooltipMapsEveryComposedLiteral),
    ("Rewrite coordinator caches completed jobs", RewriteCoordinatorCachesJobs),
    ("Repository rewrite plan discovers all available assemblies", RepositoryRewritePlanDiscoversAssemblies),
    ("Managed rewriter redirects an instance call to a static shim", ManagedRewriterRedirectsCall),
    ("Managed rewriter registers a returned value with exact metadata", ManagedRewriterRegistersReturnedValue),
    ("Managed rewriter redirects a constructed generic call", ManagedRewriterRedirectsConstructedGenericCall),
    ("Managed rewriter filters one string field at method entry", ManagedRewriterFiltersStringField),
    ("Managed rewriter filters string return values", ManagedRewriterFiltersStringReturn),
    ("Managed rewriter filters explicit method arguments", ManagedRewriterFiltersMethodArgument),
    ("Managed rewriter injects one static frame hook at method entry", ManagedRewriterInjectsMethodEntryHook),
    ("Managed rewriter injects caller instance for startup hook", ManagedRewriterInjectsInstanceEntryHook),
    ("Runtime display map preserves all valid concept keys", RuntimeDisplayMapPreservesConceptKeys),
    ("Runtime display map imports approved single concept tags", RuntimeDisplayMapImportsConceptTags),
    ("Runtime display map imports composite exact entries", RuntimeDisplayMapImportsCompositeExactEntries),
    ("Runtime display map imports only uniform composite fragments", RuntimeDisplayMapImportsUniformCompositeFragments),
    ("Runtime display map rejects generic composite templates", RuntimeDisplayMapRejectsGenericCompositeTemplates),
    ("Composite catalog discovers templates and preserves approved rules", CompositeCatalogDiscoversTemplatesAndPreservesRules),
    ("Composite catalog refreshes runtime-map translations", CompositeCatalogRefreshesRuntimeMapTranslations),
    ("Composite catalog permits only plain bare runtime display replacements", CompositeCatalogPermitsBareRuntimeDisplayReplacements),
    ("Concept tooltip catalog covers every static registration", ConceptTooltipCatalogCoversEveryStaticRegistration),
    ("Load lifecycle patch releases only IdSpriteBatch owned resources", LoadLifecyclePatchReleasesOwnedResources),
    ("Load lifecycle patch clears stale world roots before loading", LoadLifecyclePatchClearsStaleWorldRoots),
};

var failures = 0;
foreach (var test in tests)
{
    try
    {
        test.Body();
        Console.WriteLine($"PASS {test.Name}");
    }
    catch (Exception ex)
    {
        failures++;
        Console.Error.WriteLine($"FAIL {test.Name}: {ex.Message}");
    }
}

return failures == 0 ? 0 : 1;
#endif

// The named cases below are executed by XunitBridge.cs through dotnet test.
return;

static void ContentHashIsStable()
{
    using var temp = new TempDirectory();
    var a = temp.Write("a.txt", "alpha");
    var b = temp.Write("b.txt", "beta");
    var first = ContentHasher.HashFiles(new[] { a, b }, "v1");
    var second = ContentHasher.HashFiles(new[] { b, a }, "v1");
    Assert.Equal(first, second);
}

static void ContentHashChanges()
{
    using var temp = new TempDirectory();
    var path = temp.Write("input.txt", "before");
    var before = ContentHasher.HashFiles(new[] { path }, "v1");
    File.WriteAllText(path, "after");
    var after = ContentHasher.HashFiles(new[] { path }, "v1");
    Assert.NotEqual(before, after);
}

static void BuildCacheValidatesOutputs()
{
    using var temp = new TempDirectory();
    var cachePath = Path.Combine(temp.Path, "cache.json");
    var output = temp.Write("output.bin", "patched");
    var cache = new BuildCache(cachePath);
    cache.Record("ui", "abc123", new[] { output });
    Assert.True(cache.IsCurrent("ui", "abc123", new[] { output }));
    File.Delete(output);
    Assert.False(cache.IsCurrent("ui", "abc123", new[] { output }));
}

static void BuildCacheRecordsParallelStages()
{
    using var temp = new TempDirectory();
    var cachePath = Path.Combine(temp.Path, "cache.json");
    var cache = new BuildCache(cachePath);
    var outputs = Enumerable.Range(0, 64)
        .Select(index => temp.Write($"outputs/{index}.bin", index.ToString()))
        .ToArray();

    Parallel.For(0, outputs.Length, index =>
        cache.Record($"stage-{index}", $"hash-{index}", [outputs[index]]));

    var reloaded = new BuildCache(cachePath);
    for (var index = 0; index < outputs.Length; index++)
        Assert.True(reloaded.IsCurrent($"stage-{index}", $"hash-{index}", [outputs[index]]));
}

static void ManagedRewriterReplacesExactString()
{
    using var temp = new TempDirectory();
    var source = typeof(RewriteFixture).Assembly.Location;
    var output = System.IO.Path.Combine(temp.Path, "patched.dll");
    var entry = LdstrCatalog.Read(source).Single(x => x.Value == RewriteFixture.Value());
    var result = ManagedAssemblyRewriter.Rewrite(source, output,
    [
        new StringRewriteSpec(entry.MethodToken, entry.IlOffset, entry.Value, "rewrite-fixture-translated"),
    ]);

    Assert.Equal(1, result.RewrittenCount);
    Assert.True(File.Exists(output));
    Assert.True(LdstrCatalog.Read(output).Any(x => x.Value == "rewrite-fixture-translated"));
    Assert.False(LdstrCatalog.Read(output).Any(x =>
        x.MethodToken == entry.MethodToken && x.IlOffset == entry.IlOffset && x.Value == entry.Value));
}

static void RewriteMapLoadsExactContext()
{
    using var temp = new TempDirectory();
    var path = temp.Write("map.json", """
        [
          {
            "MethodToken": "0x06000001",
            "ILOffset": 12,
            "Original": "before",
            "Translation": "之后"
          }
        ]
        """);
    var specs = RewriteMap.Load(path);
    Assert.Equal(1, specs.Count);
    Assert.Equal("0x06000001", specs[0].MethodToken);
    Assert.Equal(12, specs[0].IlOffset);
    Assert.Equal("before", specs[0].Original);
    Assert.Equal("之后", specs[0].Translation);
}

static void ClanListDistanceUnitCoversSingularAndPluralForms()
{
    var repositoryRoot = FindRepositoryRoot();
    var mapPath = Path.Combine(repositoryRoot, "translations", "hardcoded-ui-il-rewrite.json");
    var specs = RewriteMap.Load(mapPath);
    var source = Path.Combine(repositoryRoot, "source", "AtTheGatesUI.original.dll");
    var familySpecs = specs.Where(candidate => candidate.MethodToken == "0x060003e8" &&
        (candidate.IlOffset == 2120 || candidate.IlOffset == 2127)).ToArray();

    foreach (var expected in new[]
    {
        (Original: "tile", IlOffset: 2127),
        (Original: "tiles", IlOffset: 2120),
    })
    {
        var spec = specs.Single(candidate =>
            candidate.MethodToken == "0x060003e8" &&
            candidate.IlOffset == expected.IlOffset &&
            candidate.Original == expected.Original);
        Assert.Equal("格", spec.Translation);
    }

    using var temp = new TempDirectory();
    var output = Path.Combine(temp.Path, "AtTheGatesUI.dll");
    var result = ManagedAssemblyRewriter.Rewrite(source, output, familySpecs);
    Assert.Equal(2, result.RewrittenCount);

    var rewritten = LdstrCatalog.Read(output);
    foreach (var expected in new[]
    {
        (Original: "tile", IlOffset: 2127),
        (Original: "tiles", IlOffset: 2120),
    })
    {
        Assert.True(rewritten.Any(candidate =>
            candidate.MethodToken == "0x060003e8" &&
            candidate.IlOffset == expected.IlOffset &&
            candidate.Value == "格"));
    }
}

static void DiplomacyWarActionsKeepTheirDistinctMeanings()
{
    var repositoryRoot = FindRepositoryRoot();
    var mapPath = Path.Combine(repositoryRoot, "translations", "hardcoded-ui-il-rewrite.json");
    var specs = RewriteMap.Load(mapPath);
    var source = Path.Combine(repositoryRoot, "source", "AtTheGatesUI.original.dll");
    var expected = new[]
    {
        (Original: "Declare War", Translation: "\u5BA3\u6218", IlOffset: 1526),
        (Original: "Make War", Translation: "\u6311\u8D77\u6218\u4E89", IlOffset: 1582),
    };

    var familySpecs = expected.Select(item => specs.Single(candidate =>
        candidate.MethodToken == "0x06000678" &&
        candidate.IlOffset == item.IlOffset &&
        candidate.Original == item.Original)).ToArray();

    Assert.NotEqual(familySpecs[0].Translation, familySpecs[1].Translation);

    using var temp = new TempDirectory();
    var output = Path.Combine(temp.Path, "AtTheGatesUI.dll");
    var result = ManagedAssemblyRewriter.Rewrite(source, output, familySpecs);
    Assert.Equal(expected.Length, result.RewrittenCount);

    var rewritten = LdstrCatalog.Read(output);
    foreach (var item in expected)
    {
        Assert.True(rewritten.Any(candidate =>
            candidate.MethodToken == "0x06000678" &&
            candidate.IlOffset == item.IlOffset &&
            candidate.Value == item.Translation));
    }
}

static void LeaderTraitTooltipPrefixPreservesDynamicValue()
{
    var repositoryRoot = FindRepositoryRoot();
    var mapPath = Path.Combine(repositoryRoot, "translations", "hardcoded-common-il-rewrite.json");
    var specs = RewriteMap.Load(mapPath);
    var source = Path.Combine(repositoryRoot, "source", "AtTheGatesCommon.original.dll");
    var familySpecs = specs.Where(candidate => candidate.MethodToken == "0x06000c08" &&
        (candidate.IlOffset == 8 || candidate.IlOffset == 33)).ToArray();

    foreach (var expected in new[]
    {
        (Original: "Leader Trait (", Translation: "领袖特质（", IlOffset: 8),
        (Original: ")", Translation: "）", IlOffset: 33),
    })
    {
        var spec = specs.Single(candidate =>
            candidate.MethodToken == "0x06000c08" &&
            candidate.IlOffset == expected.IlOffset &&
            candidate.Original == expected.Original);
        Assert.Equal(expected.Translation, spec.Translation);
    }

    using var temp = new TempDirectory();
    var output = Path.Combine(temp.Path, "AtTheGatesCommon.dll");
    var result = ManagedAssemblyRewriter.Rewrite(source, output, familySpecs);
    Assert.Equal(2, result.RewrittenCount);

    var rewritten = LdstrCatalog.Read(output);
    foreach (var expected in new[]
    {
        (Value: "领袖特质（", IlOffset: 8),
        (Value: "）", IlOffset: 33),
    })
    {
        Assert.True(rewritten.Any(candidate =>
            candidate.MethodToken == "0x06000c08" && candidate.IlOffset == expected.IlOffset &&
            candidate.Value == expected.Value));
    }
}

static void KnowledgeStudyCountdownConnectorUsesCompleteChinesePhrase()
{
    var repositoryRoot = FindRepositoryRoot();
    var mapPath = Path.Combine(repositoryRoot, "translations", "hardcoded-common-il-rewrite.json");
    var source = Path.Combine(repositoryRoot, "source", "AtTheGatesCommon.original.dll");
    const string MethodToken = "0x06000348";
    const int IlOffset = 4818;
    const string Original = " to ";
    const string Translation = "\u5373\u53ef";

    Assert.True(LdstrCatalog.Read(source).Any(candidate =>
        candidate.MethodToken == MethodToken &&
        candidate.IlOffset == IlOffset &&
        candidate.Value == Original));

    var spec = RewriteMap.Load(mapPath).Single(candidate =>
        candidate.MethodToken == MethodToken &&
        candidate.IlOffset == IlOffset &&
        candidate.Original == Original);
    Assert.Equal(Translation, spec.Translation);

    using var temp = new TempDirectory();
    var output = Path.Combine(temp.Path, "AtTheGatesCommon.dll");
    Assert.Equal(1, ManagedAssemblyRewriter.Rewrite(source, output, [spec]).RewrittenCount);
    Assert.True(LdstrCatalog.Read(output).Any(candidate =>
        candidate.MethodToken == MethodToken &&
        candidate.IlOffset == IlOffset &&
        candidate.Value == Translation));
}

static void EasternRomanDiplomacyDisplayNamesRemainAtRuntimeBoundary()
{
    var repositoryRoot = FindRepositoryRoot();
    var runtimeMap = File.ReadAllText(Path.Combine(repositoryRoot, "translations",
        "runtime-display-strings.json"));
    var expectedMappings = new[]
    {
        (Original: "The Eastern Roman Empire", Translation: "东罗马帝国"),
        (Original: "Eastern Roman Empire", Translation: "东罗马帝国"),
        (Original: "Eastern Roman", Translation: "东罗马"),
        (Original: "Eastern Roman Independents", Translation: "东罗马独立派"),
        (Original: "Eastern Roman Rebels", Translation: "东罗马叛军"),
        (Original: "Eastern Roman (I)", Translation: "东罗马（独立派）"),
        (Original: "Eastern Roman (R)", Translation: "东罗马（叛军）"),
        (Original: "Roman", Translation: "罗马"),
    };

    foreach (var expected in expectedMappings)
    {
        Assert.True(runtimeMap.Contains(
            $"\"Original\": \"{expected.Original}\",\n      \"Translation\": \"{expected.Translation}\"",
            StringComparison.Ordinal));
    }

    var factionsSource = File.ReadAllText(Path.Combine(repositoryRoot, "source", "Content",
        "Config", "Primary", "Factions.original.xml"));
    Assert.True(factionsSource.Contains("<ID>FACTION_EASTERN_ROME</ID>",
        StringComparison.Ordinal));
    Assert.True(factionsSource.Contains("<name>The Eastern Roman Empire</name>",
        StringComparison.Ordinal));

    var configNodeMap = File.ReadAllText(Path.Combine(repositoryRoot, "translations",
        "config-node-strings.json"));
    Assert.False(configNodeMap.Contains("FACTION_EASTERN_ROME", StringComparison.Ordinal));
}

static void DiplomacyInteractionTagsCoverEveryConfiguredKeyword()
{
    var repositoryRoot = FindRepositoryRoot();
    var runtimeMapPath = Path.Combine(repositoryRoot, "translations", "runtime-display-strings.json");
    using var runtimeMap = System.Text.Json.JsonDocument.Parse(File.ReadAllText(runtimeMapPath));
    var expectedMappings = new[]
    {
        (Original: "BULLYING", Translation: "恃强凌弱"),
        (Original: "DEFIANT", Translation: "挑衅"),
        (Original: "GENEROUS", Translation: "慷慨"),
        (Original: "HOSTILE", Translation: "敌对"),
        (Original: "NEUTRAL", Translation: "中立"),
        (Original: "PLEASANT", Translation: "友善"),
        (Original: "RUDE", Translation: "粗鲁"),
        (Original: "SUBMISSIVE", Translation: "顺从"),
        (Original: "TRAITOR", Translation: "叛徒"),
        (Original: "UNPLEASANT", Translation: "不友善"),
    };

    foreach (var sectionName in new[] { "PlainText", "PlainTextFragments" })
    {
        var mappings = runtimeMap.RootElement.GetProperty(sectionName)
            .EnumerateArray()
            .ToDictionary(
                entry => entry.GetProperty("Original").GetString()!,
                entry => entry.GetProperty("Translation").GetString()!,
                StringComparer.Ordinal);

        foreach (var expected in expectedMappings)
        {
            Assert.True(mappings.TryGetValue(expected.Original, out var translation) &&
                translation == expected.Translation);
        }
    }

    var diplomacySource = Path.Combine(repositoryRoot, "source", "Content", "Config", "Diplomacy");
    var configuredTags = Directory.EnumerateFiles(diplomacySource, "*.original.xml",
            SearchOption.AllDirectories)
        .SelectMany(path => System.Text.RegularExpressions.Regex
            .Matches(File.ReadAllText(path), @"INTERACTIONTAG_[A-Z_]+")
            .Select(match => match.Value))
        .ToHashSet(StringComparer.Ordinal);
    var expectedTags = expectedMappings
        .Select(expected => $"INTERACTIONTAG_{expected.Original}")
        .ToHashSet(StringComparer.Ordinal);

    Assert.Equal(expectedTags.Count, configuredTags.Count);
    Assert.True(expectedTags.SetEquals(configuredTags));
}

static void ClanTrainingConnectorsPreserveDynamicLabels()
{
    var repositoryRoot = FindRepositoryRoot();
    var mapPath = Path.Combine(repositoryRoot, "translations", "hardcoded-ui-il-rewrite.json");
    var specs = RewriteMap.Load(mapPath);
    var source = Path.Combine(repositoryRoot, "source", "AtTheGatesUI.original.dll");
    var expected = new[]
    {
        (MethodToken: "0x06000504", Original: " in ", Translation: "：", IlOffset: 133),
        (MethodToken: "0x06000122", Original: "as ", Translation: "成为", IlOffset: 2295),
        (MethodToken: "0x0600051f", Original: " in ", Translation: "：", IlOffset: 15),
        (MethodToken: "0x06000522", Original: " in ", Translation: "，在", IlOffset: 152),
        (MethodToken: "0x06000522", Original: " (will start at ", Translation: "纪律中（将从", IlOffset: 224),
        (MethodToken: "0x06000522", Original: "[COLOR:BAD-RED][FONT:CLEAN-BOLD]- WARNING -[/FONT][/COLOR] Once Training is complete ", Translation: "[COLOR:BAD-RED][FONT:CLEAN-BOLD]- 警告 -[/FONT][/COLOR] 训练完成后，", IlOffset: 324),
        (MethodToken: "0x06000522", Original: " ", Translation: "", IlOffset: 350),
        (MethodToken: "0x06000522", Original: " will abandon and lose all [Experience|XP] in ", Translation: "将放弃并失去全部[经验|XP]，原纪律：", IlOffset: 382),
        (MethodToken: "0x06000522", Original: " in ", Translation: "，在", IlOffset: 1224),
        (MethodToken: "0x06000522", Original: " (from ", Translation: "纪律中（从", IlOffset: 1277),
    };
    var familySpecs = specs.Where(candidate => expected.Any(item =>
        candidate.MethodToken == item.MethodToken && candidate.IlOffset == item.IlOffset &&
        candidate.Original == item.Original)).ToArray();

    foreach (var item in expected)
    {
        var spec = specs.Single(candidate =>
            candidate.MethodToken == item.MethodToken &&
            candidate.IlOffset == item.IlOffset &&
            candidate.Original == item.Original);
        Assert.Equal(item.Translation, spec.Translation);
    }

    using var temp = new TempDirectory();
    var output = Path.Combine(temp.Path, "AtTheGatesUI.dll");
    var result = ManagedAssemblyRewriter.Rewrite(source, output, familySpecs);
    Assert.Equal(expected.Length, result.RewrittenCount);

    var rewritten = LdstrCatalog.Read(output);
    foreach (var item in expected)
    {
        Assert.True(rewritten.Any(candidate =>
            candidate.MethodToken == item.MethodToken &&
            candidate.IlOffset == item.IlOffset &&
            candidate.Value == item.Translation));
    }
}

static void TrainingAsConnectorsCoverEveryDisplayPath()
{
    var repositoryRoot = FindRepositoryRoot();
    var uiMapPath = Path.Combine(repositoryRoot, "translations", "hardcoded-ui-il-rewrite.json");
    var gameMapPath = Path.Combine(repositoryRoot, "translations", "hardcoded-game-il-rewrite.json");
    var uiSource = Path.Combine(repositoryRoot, "source", "AtTheGatesUI.original.dll");
    var gameSource = Path.Combine(repositoryRoot, "source", "AtTheGatesGame.original.exe");
    var uiExpected = new[]
    {
        (MethodToken: "0x06000504", IlOffset: 84, Original: " as ", Translation: "为"),
        (MethodToken: "0x060005c1", IlOffset: 258, Original: "as ", Translation: "为"),
        (MethodToken: "0x06000122", IlOffset: 2295, Original: "as ", Translation: "成为"),
        // Profession-study completion uses a different notification branch from
        // training completion, but it also appends a dynamic profession concept.
        (MethodToken: "0x0600002f", IlOffset: 3196, Original: " as ", Translation: "成为"),
        // Notification.AppendDetails takes every completed profession through
        // this one concept-tagged branch, so it covers all "as a <profession>"
        // variants without a hazardous global article replacement.
        (MethodToken: "0x0600002d", IlOffset: 2538, Original: "a [", Translation: "["),
        (MethodToken: "0x0600002f", IlOffset: 3494, Original: " as ", Translation: "，成为"),
        (MethodToken: "0x0600002f", IlOffset: 3522, Original: ":A/AN]", Translation: "]"),
    };
    var gameExpected = new[]
    {
        (MethodToken: "0x06000864", IlOffset: 369, Original: " as ", Translation: "为"),
        (MethodToken: "0x0600086c", IlOffset: 73, Original: " as ", Translation: "成为"),
    };

    var uiSpecs = RewriteMap.Load(uiMapPath);
    var gameSpecs = RewriteMap.Load(gameMapPath);
    var sourceUiEntries = LdstrCatalog.Read(uiSource);
    var sourceGameEntries = LdstrCatalog.Read(gameSource);

    foreach (var item in uiExpected)
    {
        Assert.True(sourceUiEntries.Any(candidate =>
            candidate.MethodToken == item.MethodToken &&
            candidate.IlOffset == item.IlOffset &&
            candidate.Value == item.Original));
        var spec = uiSpecs.Single(candidate =>
            candidate.MethodToken == item.MethodToken &&
            candidate.IlOffset == item.IlOffset &&
            candidate.Original == item.Original);
        Assert.Equal(item.Translation, spec.Translation);
    }

    foreach (var item in gameExpected)
    {
        Assert.True(sourceGameEntries.Any(candidate =>
            candidate.MethodToken == item.MethodToken &&
            candidate.IlOffset == item.IlOffset &&
            candidate.Value == item.Original));
        var spec = gameSpecs.Single(candidate =>
            candidate.MethodToken == item.MethodToken &&
            candidate.IlOffset == item.IlOffset &&
            candidate.Original == item.Original);
        Assert.Equal(item.Translation, spec.Translation);
    }

    var selectedUiSpecs = uiSpecs.Where(candidate => uiExpected.Any(item =>
        candidate.MethodToken == item.MethodToken &&
        candidate.IlOffset == item.IlOffset &&
        candidate.Original == item.Original)).ToArray();
    var selectedGameSpecs = gameSpecs.Where(candidate => gameExpected.Any(item =>
        candidate.MethodToken == item.MethodToken &&
        candidate.IlOffset == item.IlOffset &&
        candidate.Original == item.Original)).ToArray();

    using var temp = new TempDirectory();
    var uiOutput = Path.Combine(temp.Path, "AtTheGatesUI.dll");
    var gameOutput = Path.Combine(temp.Path, "At The Gates.exe");
    Assert.Equal(uiExpected.Length, ManagedAssemblyRewriter.Rewrite(uiSource, uiOutput, selectedUiSpecs).RewrittenCount);
    Assert.Equal(gameExpected.Length, ManagedAssemblyRewriter.Rewrite(gameSource, gameOutput, selectedGameSpecs).RewrittenCount);

    var rewrittenUiEntries = LdstrCatalog.Read(uiOutput);
    var rewrittenGameEntries = LdstrCatalog.Read(gameOutput);
    foreach (var item in uiExpected)
    {
        Assert.True(rewrittenUiEntries.Any(candidate =>
            candidate.MethodToken == item.MethodToken &&
            candidate.IlOffset == item.IlOffset &&
            candidate.Value == item.Translation));
    }

    foreach (var item in gameExpected)
    {
        Assert.True(rewrittenGameEntries.Any(candidate =>
            candidate.MethodToken == item.MethodToken &&
            candidate.IlOffset == item.IlOffset &&
            candidate.Value == item.Translation));
    }

    var patchedUi = Path.Combine(repositoryRoot, "patch", "AtTheGatesUI.dll");
    Assert.True(File.Exists(patchedUi));
    var patchedUiEntries = LdstrCatalog.Read(patchedUi);
    foreach (var item in uiExpected)
    {
        Assert.True(patchedUiEntries.Any(candidate =>
            candidate.MethodToken == item.MethodToken &&
            candidate.IlOffset == item.IlOffset &&
            candidate.Value == item.Translation));
    }

    var patchedGame = Path.Combine(repositoryRoot, "patch", "At The Gates.exe");
    Assert.True(File.Exists(patchedGame));
    var patchedGameEntries = LdstrCatalog.Read(patchedGame);
    foreach (var item in gameExpected)
    {
        Assert.True(patchedGameEntries.Any(candidate =>
            candidate.MethodToken == item.MethodToken &&
            candidate.IlOffset == item.IlOffset &&
            candidate.Value == item.Translation));
    }
}

static void CaravanActionButtonsPreserveTransactionDirection()
{
    var repositoryRoot = FindRepositoryRoot();
    var mapPath = Path.Combine(repositoryRoot, "translations", "hardcoded-ui-il-rewrite.json");
    var specs = RewriteMap.Load(mapPath);
    var source = Path.Combine(repositoryRoot, "source", "AtTheGatesUI.original.dll");
    const string MethodToken = "0x06000577";
    var expected = new[]
    {
        (Original: "for ", Translation: "，花费 ", IlOffset: 534),
        (Original: "for ", Translation: "，花费 ", IlOffset: 1055),
        (Original: " Buy ", Translation: "买入 ", IlOffset: 1496),
        (Original: "for ", Translation: "，花费 ", IlOffset: 1594),
        (Original: "for ", Translation: "，获得 ", IlOffset: 2121),
        (Original: "for ", Translation: "，获得 ", IlOffset: 2644),
        (Original: "for ", Translation: "，获得 ", IlOffset: 3194),
    };

    var sourceCatalog = LdstrCatalog.Read(source);
    foreach (var item in expected)
    {
        Assert.True(sourceCatalog.Any(candidate =>
            candidate.MethodToken == MethodToken &&
            candidate.IlOffset == item.IlOffset &&
            candidate.Value == item.Original));

        var spec = specs.Single(candidate =>
            candidate.MethodToken == MethodToken &&
            candidate.IlOffset == item.IlOffset &&
            candidate.Original == item.Original);
        Assert.Equal(item.Translation, spec.Translation);
    }

    var familySpecs = specs.Where(candidate => expected.Any(item =>
        candidate.MethodToken == MethodToken &&
        candidate.IlOffset == item.IlOffset &&
        candidate.Original == item.Original)).ToArray();
    Assert.Equal(expected.Length, familySpecs.Length);

    using var temp = new TempDirectory();
    var output = Path.Combine(temp.Path, "AtTheGatesUI.dll");
    var result = ManagedAssemblyRewriter.Rewrite(source, output, familySpecs);
    Assert.Equal(expected.Length, result.RewrittenCount);

    var rewritten = LdstrCatalog.Read(output);
    foreach (var item in expected)
    {
        Assert.True(rewritten.Any(candidate =>
            candidate.MethodToken == MethodToken &&
            candidate.IlOffset == item.IlOffset &&
            candidate.Value == item.Translation));
    }
}

static void CaravanUnavailableTooltipLocalizesPluralConceptLabel()
{
    var repositoryRoot = FindRepositoryRoot();
    var mapPath = Path.Combine(repositoryRoot, "translations", "hardcoded-ui-il-rewrite.json");
    var specs = RewriteMap.Load(mapPath);
    var source = Path.Combine(repositoryRoot, "source", "AtTheGatesUI.original.dll");
    const string MethodToken = "0x06000267";
    const int IlOffset = 92;
    const string Original = "\n\nAlas, no [Caravans|CARAVAN] are in our area this [Turn|TURN].";
    const string Translation = "\n\n遗憾的是，本[回合|TURN]没有[商队|CARAVAN]来到附近。";

    Assert.True(LdstrCatalog.Read(source).Any(candidate =>
        candidate.MethodToken == MethodToken &&
        candidate.IlOffset == IlOffset &&
        candidate.Value == Original));

    var spec = specs.Single(candidate =>
        candidate.MethodToken == MethodToken &&
        candidate.IlOffset == IlOffset &&
        candidate.Original == Original);
    Assert.Equal(Translation, spec.Translation);
    Assert.False(spec.Translation.Contains("[Caravans|CARAVAN]", StringComparison.Ordinal));

    using var temp = new TempDirectory();
    var output = Path.Combine(temp.Path, "AtTheGatesUI.dll");
    var result = ManagedAssemblyRewriter.Rewrite(source, output, [spec]);
    Assert.Equal(1, result.RewrittenCount);
    Assert.True(LdstrCatalog.Read(output).Any(candidate =>
        candidate.MethodToken == MethodToken &&
        candidate.IlOffset == IlOffset &&
        candidate.Value == Translation));
}

static void EnnobledEventChoiceUsesLocalizedMoodReason()
{
    var repositoryRoot = FindRepositoryRoot();
    var mapPath = Path.Combine(repositoryRoot, "translations", "hardcoded-game-il-rewrite.json");
    var source = Path.Combine(repositoryRoot, "source", "AtTheGatesGame.original.exe");
    const string MethodToken = "0x06000da7";
    const int IlOffset = 703;
    const string Original = " from being [Ennobled|NOBLE]";
    const string Translation = "，源于[已册封|NOBLE]";

    Assert.True(LdstrCatalog.Read(source).Any(candidate =>
        candidate.MethodToken == MethodToken &&
        candidate.IlOffset == IlOffset &&
        candidate.Value == Original));

    var spec = RewriteMap.Load(mapPath).Single(candidate =>
        candidate.MethodToken == MethodToken &&
        candidate.IlOffset == IlOffset &&
        candidate.Original == Original);
    Assert.Equal(Translation, spec.Translation);

    using var temp = new TempDirectory();
    var output = Path.Combine(temp.Path, "At The Gates.exe");
    var result = ManagedAssemblyRewriter.Rewrite(source, output, [spec]);
    Assert.Equal(1, result.RewrittenCount);
    Assert.True(LdstrCatalog.Read(output).Any(candidate =>
        candidate.MethodToken == MethodToken &&
        candidate.Value == Translation));
}

static void FinalGamePatchRetainsLocalizedEnnobledMoodReason()
{
    var repositoryRoot = FindRepositoryRoot();
    var patchedGame = Path.Combine(repositoryRoot, "patch", "At The Gates.exe");
    const string MethodToken = "0x06000da7";
    const string Translation = "，源于[已册封|NOBLE]";

    Assert.True(File.Exists(patchedGame));
    Assert.True(LdstrCatalog.Read(patchedGame).Any(candidate =>
        candidate.MethodToken == MethodToken && candidate.Value == Translation));
}

static void EnnobledDisciplineChoiceOptionsCoverAllSixEffects()
{
    var repositoryRoot = FindRepositoryRoot();
    var sourcePath = Path.Combine(repositoryRoot, "source", "Content", "Config", "Constants",
        "GameConstants.original.xml");
    var mapPath = Path.Combine(repositoryRoot, "translations", "config-node-misc-strings.json");
    var patchedPath = Path.Combine(repositoryRoot, "patch", "Content", "Config", "Constants",
        "GameConstants.xml");
    var expected = new Dictionary<string, (string Source, string Translation)>(StringComparer.Ordinal)
    {
        ["DISCIPLINE_HONOR"] = ("+5 Levels in Honor", "荣誉等级+5"),
        ["DISCIPLINE_AGRICULTURE"] = ("+5 Levels in Agriculture", "农业等级+5"),
        ["DISCIPLINE_LIVESTOCK"] = ("+5 Levels in Livestock", "畜牧等级+5"),
        ["DISCIPLINE_METALWORKING"] = ("+5 Levels in Metalworking", "冶金等级+5"),
        ["DISCIPLINE_CRAFTING"] = ("+5 Levels in Crafting", "工艺等级+5"),
        ["DISCIPLINE_DISCOVERY"] = ("+5 Levels in Discovery", "探索等级+5"),
    };

    var source = System.Xml.Linq.XDocument.Load(sourcePath);
    var ennobledProperties = source.Root!.Element("propertiesWhenEnnobled")!;
    var choice = ennobledProperties.Elements("property")
        .Single(node => (string?)node.Element("propertyID") == "Choose_Property");
    var sourceOptions = choice.Elements("property")
        .ToDictionary(
            node => node.Element("ID")!.Value,
            node => node.Element("usage")!.Value,
            StringComparer.Ordinal);
    Assert.True(expected.Keys.OrderBy(id => id, StringComparer.Ordinal).SequenceEqual(
        sourceOptions.Keys.OrderBy(id => id, StringComparer.Ordinal), StringComparer.Ordinal));
    foreach (var item in expected)
    {
        Assert.Equal(item.Value.Source, sourceOptions[item.Key]);
    }

    using var map = System.Text.Json.JsonDocument.Parse(File.ReadAllText(mapPath));
    var gameConstantsMap = map.RootElement.GetProperty(@"Content\Config\Constants\GameConstants.xml");
    Assert.Equal(@"source\Content\Config\Constants\GameConstants.original.xml",
        gameConstantsMap.GetProperty("Source").GetString());
    Assert.Equal("property", gameConstantsMap.GetProperty("Container").GetString());
    var translations = gameConstantsMap.GetProperty("Items").EnumerateArray()
        .ToDictionary(
            item => item.GetProperty("ID").GetString()!,
            item => item.GetProperty("Nodes").EnumerateArray().Single(
                node => node.GetProperty("XPath").GetString() == "usage").GetProperty("Value").GetString()!,
            StringComparer.Ordinal);
    Assert.True(expected.Keys.OrderBy(id => id, StringComparer.Ordinal).SequenceEqual(
        translations.Keys.OrderBy(id => id, StringComparer.Ordinal), StringComparer.Ordinal));
    foreach (var item in expected)
    {
        Assert.Equal(item.Value.Translation, translations[item.Key]);
        Assert.False(System.Text.RegularExpressions.Regex.IsMatch(translations[item.Key], "[A-Za-z]"));
    }

    const string sourceReason = "being [Ennobled|NOBLE]";
    const string localizedReason = "[已册封|NOBLE]";
    var sourceReasons = ennobledProperties.Descendants("fromDescription")
        .Where(node => node.Value == sourceReason)
        .ToArray();
    Assert.Equal(8, sourceReasons.Length);

    var reasonReplacement = gameConstantsMap.GetProperty("CompositeReplacements")
        .EnumerateArray()
        .Single(item => item.GetProperty("OriginalValue").GetString() == sourceReason);
    Assert.Equal("descendant::fromDescription", reasonReplacement.GetProperty("XPath").GetString());
    Assert.Equal(localizedReason, reasonReplacement.GetProperty("LocalizedValue").GetString());
    Assert.Equal(sourceReasons.Length, reasonReplacement.GetProperty("ExpectedMatchCount").GetInt32());

    Assert.True(File.Exists(patchedPath));
    var patched = System.Xml.Linq.XDocument.Load(patchedPath);
    var patchedChoice = patched.Root!.Element("propertiesWhenEnnobled")!.Elements("property")
        .Single(node => (string?)node.Element("propertyID") == "Choose_Property");
    var patchedOptions = patchedChoice.Elements("property")
        .ToDictionary(
            node => node.Element("ID")!.Value,
            node => node.Element("usage")!.Value,
            StringComparer.Ordinal);
    Assert.True(expected.Keys.OrderBy(id => id, StringComparer.Ordinal).SequenceEqual(
        patchedOptions.Keys.OrderBy(id => id, StringComparer.Ordinal), StringComparer.Ordinal));
    foreach (var item in expected)
    {
        Assert.Equal(item.Value.Translation, patchedOptions[item.Key]);
    }

    var patchedReasons = patched.Root!.Element("propertiesWhenEnnobled")!
        .Descendants("fromDescription")
        .Where(node => node.Value == localizedReason)
        .ToArray();
    Assert.Equal(sourceReasons.Length, patchedReasons.Length);
}

static void DisciplineTooltipConfigMapCoversAllSixEntries()
{
    var repositoryRoot = FindRepositoryRoot();
    var sourcePath = Path.Combine(repositoryRoot, "source", "Content", "Config", "Misc",
        "Disciplines.original.xml");
    var mapPath = Path.Combine(repositoryRoot, "translations", "config-node-misc-strings.json");
    var source = System.Xml.Linq.XDocument.Load(sourcePath);
    using var map = System.Text.Json.JsonDocument.Parse(File.ReadAllText(mapPath));
    var disciplineMap = map.RootElement.GetProperty(@"Content\Config\Misc\Disciplines.xml");

    Assert.Equal(@"source\Content\Config\Misc\Disciplines.original.xml",
        disciplineMap.GetProperty("Source").GetString());
    Assert.Equal("discipline", disciplineMap.GetProperty("Container").GetString());

    var translations = disciplineMap.GetProperty("Items").EnumerateArray()
        .ToDictionary(
            item => item.GetProperty("ID").GetString()!,
            item => item.GetProperty("Description").GetString()!,
            StringComparer.Ordinal);
    var expectedNames = new Dictionary<string, string>(StringComparer.Ordinal)
    {
        ["DISCIPLINE_HONOR"] = "荣誉",
        ["DISCIPLINE_AGRICULTURE"] = "农业",
        ["DISCIPLINE_LIVESTOCK"] = "畜牧",
        ["DISCIPLINE_METALWORKING"] = "冶金",
        ["DISCIPLINE_CRAFTING"] = "工艺",
        ["DISCIPLINE_DISCOVERY"] = "探索",
    };
    const string SharedPrefix = "是六种[纪律|DISCIPLINE]之一，[职业|PROFESSION]和[氏族|CLAN]都可归属其中。[BLANK-LINE]";

    Assert.Equal(expectedNames.Count, translations.Count);
    foreach (var expected in expectedNames)
    {
        Assert.True(translations.TryGetValue(expected.Key, out var translation));
        if (translation is null) throw new InvalidOperationException("Discipline translation was not found.");
        Assert.True(translation.StartsWith(expected.Value + SharedPrefix, StringComparison.Ordinal));

        var sourceDescription = source.Root!.Elements("discipline")
            .Single(node => (string?)node.Element("ID") == expected.Key)
            .Element("description")!.Value;
        foreach (System.Text.RegularExpressions.Match match in
            System.Text.RegularExpressions.Regex.Matches(sourceDescription, @"\[[^\]]+\]"))
        {
            var sourceTag = match.Value;
            var separator = sourceTag.IndexOf('|');
            var preservedToken = separator >= 0 ? sourceTag[separator..] : sourceTag;
            Assert.True(translation.Contains(preservedToken, StringComparison.Ordinal));
        }

        var displayText = System.Text.RegularExpressions.Regex.Replace(translation, @"\[[^\]]+\]", "");
        Assert.False(System.Text.RegularExpressions.Regex.IsMatch(displayText, "[A-Za-z]"));
    }
}

static void ObsessedIntensityTooltipConfigPreservesRichTextBoundary()
{
    var repositoryRoot = FindRepositoryRoot();
    var sourcePath = Path.Combine(repositoryRoot, "source", "Content", "Config", "Misc",
        "Intensities.original.xml");
    var mapPath = Path.Combine(repositoryRoot, "translations", "config-node-misc-strings.json");
    var source = System.Xml.Linq.XDocument.Load(sourcePath);
    using var map = System.Text.Json.JsonDocument.Parse(File.ReadAllText(mapPath));
    var intensityMap = map.RootElement.GetProperty(@"Content\Config\Misc\Intensities.xml");

    Assert.Equal(@"source\Content\Config\Misc\Intensities.original.xml",
        intensityMap.GetProperty("Source").GetString());
    Assert.Equal("intensity", intensityMap.GetProperty("Container").GetString());

    var item = intensityMap.GetProperty("Items").EnumerateArray()
        .Single(candidate => candidate.GetProperty("ID").GetString() == "INTENSITY_OBSESSED");
    Assert.Equal("痴迷", item.GetProperty("Name").GetString());
    const string ExpectedTranslation = "[COLOR:BAD-RED]会痴迷[/COLOR]于";
    Assert.Equal(ExpectedTranslation, item.GetProperty("Description").GetString());

    var sourceDescription = source.Root!.Elements("intensity")
        .Single(node => (string?)node.Element("ID") == "INTENSITY_OBSESSED")
        .Element("description")!.Value;
    Assert.Equal("[COLOR:BAD-RED]become obsessed[/COLOR] with the idea of", sourceDescription);
    foreach (System.Text.RegularExpressions.Match tag in
        System.Text.RegularExpressions.Regex.Matches(sourceDescription, @"\[[^\]]+\]"))
    {
        Assert.True(ExpectedTranslation.Contains(tag.Value, StringComparison.Ordinal));
    }

    var displayText = System.Text.RegularExpressions.Regex.Replace(ExpectedTranslation, @"\[[^\]]+\]", "");
    Assert.False(System.Text.RegularExpressions.Regex.IsMatch(displayText, "[A-Za-z]"));
}

static void DesertedLocationExplorationConfigsCoverAllEventOutcomes()
{
    var repositoryRoot = FindRepositoryRoot();
    var goodyResultsSourcePath = Path.Combine(repositoryRoot, "source", "Content", "Config", "Misc",
        "GoodyResults.original.xml");
    var goodyHutsSourcePath = Path.Combine(repositoryRoot, "source", "Content", "Config", "OnMap",
        "GoodyHuts.original.xml");
    var miscMapPath = Path.Combine(repositoryRoot, "translations", "config-node-misc-strings.json");
    var onMapPath = Path.Combine(repositoryRoot, "translations", "config-node-onmap-strings.json");

    var goodyResultsSource = System.Xml.Linq.XDocument.Load(goodyResultsSourcePath);
    var goodyHutsSource = System.Xml.Linq.XDocument.Load(goodyHutsSourcePath);
    using var miscMap = System.Text.Json.JsonDocument.Parse(File.ReadAllText(miscMapPath));
    using var onMapMap = System.Text.Json.JsonDocument.Parse(File.ReadAllText(onMapPath));
    var goodyResultsMap = miscMap.RootElement.GetProperty(@"Content\Config\Misc\GoodyResults.xml");
    var goodyHutsMap = onMapMap.RootElement.GetProperty(@"Content\Config\OnMap\GoodyHuts.xml");

    Assert.Equal(@"source\Content\Config\Misc\GoodyResults.original.xml",
        goodyResultsMap.GetProperty("Source").GetString());
    Assert.Equal("goodyResult", goodyResultsMap.GetProperty("Container").GetString());
    var sourceResults = goodyResultsSource.Root!.Descendants("goodyResult")
        .ToDictionary(
            node => node.Element("ID")!.Value,
            node => node.Element("name")!.Value,
            StringComparer.Ordinal);
    var translatedResults = goodyResultsMap.GetProperty("Items").EnumerateArray()
        .ToDictionary(
            item => item.GetProperty("ID").GetString()!,
            item => item.GetProperty("Name").GetString()!,
            StringComparer.Ordinal);

    Assert.Equal(27, sourceResults.Count);
    Assert.True(sourceResults.Keys.OrderBy(id => id, StringComparer.Ordinal).SequenceEqual(
        translatedResults.Keys.OrderBy(id => id, StringComparer.Ordinal), StringComparer.Ordinal));
    Assert.Equal("在城市遗迹中，你的[EXPLORER]发现了一群[TRADER:S]，希望加入你！",
        translatedResults["GOODY_RESULT_TRADER"]);

    foreach (var sourceResult in sourceResults)
    {
        var translation = translatedResults[sourceResult.Key];
        Assert.True(ReadRichTextKeys(sourceResult.Value).OrderBy(key => key, StringComparer.Ordinal)
            .SequenceEqual(ReadRichTextKeys(translation).OrderBy(key => key, StringComparer.Ordinal),
                StringComparer.Ordinal));
        var displayText = System.Text.RegularExpressions.Regex.Replace(translation, @"\[[^\]]+\]", "");
        Assert.False(System.Text.RegularExpressions.Regex.IsMatch(displayText, "[A-Za-z]"));
    }

    var fromDescriptions = goodyResultsSource.Root.Descendants("fromDescription").ToArray();
    Assert.Equal(31, fromDescriptions.Length);
    Assert.True(fromDescriptions.All(description =>
        StringComparer.Ordinal.Equals("from [Deserted Location|DESERTED-LOCATION]", description.Value)));
    var replacement = goodyResultsMap.GetProperty("CompositeReplacements").EnumerateArray().Single();
    Assert.Equal("descendant::fromDescription", replacement.GetProperty("XPath").GetString());
    Assert.Equal("from [Deserted Location|DESERTED-LOCATION]", replacement.GetProperty("OriginalValue").GetString());
    Assert.Equal("来自[废弃地点|DESERTED-LOCATION]", replacement.GetProperty("LocalizedValue").GetString());
    Assert.Equal(fromDescriptions.Length, replacement.GetProperty("ExpectedMatchCount").GetInt32());

    Assert.Equal(@"source\Content\Config\OnMap\GoodyHuts.original.xml",
        goodyHutsMap.GetProperty("Source").GetString());
    Assert.Equal("goodyHut", goodyHutsMap.GetProperty("Container").GetString());
    var sourceHutIds = goodyHutsSource.Root!.Elements("goodyHut")
        .Select(node => node.Element("ID")!.Value)
        .OrderBy(id => id, StringComparer.Ordinal)
        .ToArray();
    var translatedHuts = goodyHutsMap.GetProperty("Items").EnumerateArray()
        .ToDictionary(item => item.GetProperty("ID").GetString()!, StringComparer.Ordinal);
    Assert.Equal(5, sourceHutIds.Length);
    Assert.True(sourceHutIds.SequenceEqual(
        translatedHuts.Keys.OrderBy(id => id, StringComparer.Ordinal), StringComparer.Ordinal));
    foreach (var hut in translatedHuts)
    {
        var name = hut.Value.GetProperty("Name").GetString()!;
        var description = hut.Value.GetProperty("Description").GetString()!;
        Assert.False(System.Text.RegularExpressions.Regex.IsMatch(name, "[A-Za-z]"));
        Assert.True(description.Contains("[NEWLINE]", StringComparison.Ordinal));
        Assert.True(description.Contains("[EXPLORER]", StringComparison.Ordinal));
    }

    static string[] ReadRichTextKeys(string value) =>
        System.Text.RegularExpressions.Regex.Matches(value, @"\[([^\]]+)\]")
            .Select(match =>
            {
                var contents = match.Groups[1].Value;
                var separator = contents.IndexOf('|');
                return separator >= 0 ? contents[(separator + 1)..] : contents;
            })
            .ToArray();
}

static void RomanConceptTooltipLocalizesNestedConceptLinks()
{
    var repositoryRoot = FindRepositoryRoot();
    var mapPath = Path.Combine(repositoryRoot, "translations", "hardcoded-common-il-rewrite.json");
    var compositeRulesPath = Path.Combine(repositoryRoot, "translations", "composite-text-rules.json");
    var source = Path.Combine(repositoryRoot, "source", "AtTheGatesCommon.original.dll");
    const string MethodToken = "0x0600026a";
    const int IlOffset = 1458;
    const string Original = "There are two distinct and independently-run Roman Empires. Both are quite strong in the early going, and picking a fight with them is very dangerous. In time you'll grow much stronger and the Romans weaker, but for now it's probably best to stay on their good side.[BLANK-LINE]Your [ultimate goal|WINNING] in AtG is to defeat the Romans by capturing the [Capital City|CAPITAL] of either half of the Empire, or take the empire over from within by becoming Magister Militum.";
    const string Translation = "世界上有两个彼此独立运作的罗马帝国。它们在前期都相当强大，贸然与其开战十分危险。随着时间推移，你会更强而罗马人会更弱；但眼下最好还是与他们保持良好关系。[BLANK-LINE]你在 AtG 中的[最终目标|WINNING]，是通过攻占帝国任一半部的[首都|CAPITAL]来击败罗马人，或成为军务长官，从内部接管帝国。";

    Assert.True(LdstrCatalog.Read(source).Any(candidate =>
        candidate.MethodToken == MethodToken &&
        candidate.IlOffset == IlOffset &&
        candidate.Value == Original));

    var spec = RewriteMap.Load(mapPath).Single(candidate =>
        candidate.MethodToken == MethodToken &&
        candidate.IlOffset == IlOffset &&
        candidate.Original == Original);
    Assert.Equal(Translation, spec.Translation);

    using var compositeRules = System.Text.Json.JsonDocument.Parse(File.ReadAllText(compositeRulesPath));
    var compositeRule = compositeRules.RootElement.GetProperty("Entries").EnumerateArray().Single(entry =>
        entry.GetProperty("EntryPointId").GetString() ==
        "managed-map:hardcoded-common-il-rewrite.json:0x0600026a:IL_05B2");
    Assert.Equal(Translation, compositeRule.GetProperty("LocalizedFormat").GetString());

    static string[] ReadRichTextKeys(string value) =>
        System.Text.RegularExpressions.Regex.Matches(value, @"\[([^\]]+)\]")
            .Select(match =>
            {
                var contents = match.Groups[1].Value;
                var separator = contents.IndexOf('|');
                return separator >= 0 ? contents[(separator + 1)..] : contents;
            })
            .ToArray();

    Assert.True(ReadRichTextKeys(Original).OrderBy(key => key, StringComparer.Ordinal)
        .SequenceEqual(ReadRichTextKeys(Translation).OrderBy(key => key, StringComparer.Ordinal),
            StringComparer.Ordinal));
    Assert.False(Translation.Contains("ultimate goal", StringComparison.Ordinal));
    Assert.False(Translation.Contains("Capital City", StringComparison.Ordinal));

    using var temp = new TempDirectory();
    var output = Path.Combine(temp.Path, "AtTheGatesCommon.dll");
    Assert.Equal(1, ManagedAssemblyRewriter.Rewrite(source, output, [spec]).RewrittenCount);
    Assert.True(LdstrCatalog.Read(output).Any(candidate =>
        candidate.MethodToken == MethodToken && candidate.IlOffset == IlOffset &&
        candidate.Value == Translation));
}

static void FactionConceptTooltipLocalizesNestedConceptLinks()
{
    var repositoryRoot = FindRepositoryRoot();
    var mapPath = Path.Combine(repositoryRoot, "translations", "hardcoded-common-il-rewrite.json");
    var compositeRulesPath = Path.Combine(repositoryRoot, "translations", "composite-text-rules.json");
    var source = Path.Combine(repositoryRoot, "source", "AtTheGatesCommon.original.dll");
    const string MethodToken = "0x0600026a";
    const int IlOffset = 1567;
    const string Original = "Factions are the different kinds of tribes, kingdoms, and empires to be found throughout the world.[BLANK-LINE]Different Factions all start in different situations, and are at different level of advancement, except for the human player, who always starts with a single [SETTLEMENT] and 3 [Clans|CLAN].[BLANK-LINE]You start the game only able to play as the Goths, but more can be unlocked by conquering the [Capital|CAPITAL] of another Faction, or forming an [Alliance|ALLIANCE] with it.[BLANK-LINE]Special, non-playable Factions include the [Romans|ROME], the [Bandits|BANDIT], and [Neutral|NEUTRAL] minor tribes.";
    const string Translation = "派系代表世界各地不同的部族、王国和帝国。[BLANK-LINE]不同派系开局形势和发展水平各不相同；人类玩家例外，总是以一个[SETTLEMENT]和3个[氏族|CLAN]开局。[BLANK-LINE]游戏开始时你只能扮演哥特人，但可以通过征服其他派系的[首都|CAPITAL]，或与其结成[同盟|ALLIANCE]来解锁更多派系。[BLANK-LINE]特殊的非可玩派系包括[罗马人|ROME]、[强盗|BANDIT]和[中立|NEUTRAL]小部族。";

    Assert.True(LdstrCatalog.Read(source).Any(candidate =>
        candidate.MethodToken == MethodToken &&
        candidate.IlOffset == IlOffset &&
        candidate.Value == Original));

    var spec = RewriteMap.Load(mapPath).Single(candidate =>
        candidate.MethodToken == MethodToken &&
        candidate.IlOffset == IlOffset &&
        candidate.Original == Original);
    Assert.Equal(Translation, spec.Translation);

    using var compositeRules = System.Text.Json.JsonDocument.Parse(File.ReadAllText(compositeRulesPath));
    var compositeRule = compositeRules.RootElement.GetProperty("Entries").EnumerateArray().Single(entry =>
        entry.GetProperty("EntryPointId").GetString() ==
        "managed-map:hardcoded-common-il-rewrite.json:0x0600026a:IL_061F");
    Assert.Equal(Translation, compositeRule.GetProperty("LocalizedFormat").GetString());

    static string[] ReadRichTextKeys(string value) =>
        System.Text.RegularExpressions.Regex.Matches(value, @"\[([^\]]+)\]")
            .Select(match =>
            {
                var contents = match.Groups[1].Value;
                var separator = contents.IndexOf('|');
                return separator >= 0 ? contents[(separator + 1)..] : contents;
            })
            .ToArray();

    Assert.True(ReadRichTextKeys(Original).OrderBy(key => key, StringComparer.Ordinal)
        .SequenceEqual(ReadRichTextKeys(Translation).OrderBy(key => key, StringComparer.Ordinal),
            StringComparer.Ordinal));
    Assert.False(System.Text.RegularExpressions.Regex.IsMatch(
        System.Text.RegularExpressions.Regex.Replace(Translation, @"\[[^\]]+\]", ""), "[A-Za-z]"));

    using var temp = new TempDirectory();
    var output = Path.Combine(temp.Path, "AtTheGatesCommon.dll");
    Assert.Equal(1, ManagedAssemblyRewriter.Rewrite(source, output, [spec]).RewrittenCount);
    Assert.True(LdstrCatalog.Read(output).Any(candidate =>
        candidate.MethodToken == MethodToken && candidate.IlOffset == IlOffset &&
        candidate.Value == Translation));
}

static void ConceptTooltipCatalogCoversEveryStaticRegistration()
{
    var repositoryRoot = FindRepositoryRoot();
    var source = Path.Combine(repositoryRoot, "source", "AtTheGatesCommon.original.dll");
    var catalog = ConceptTooltipCatalog.Read(source);

    Assert.Equal("AtTheGatesCommon.ns_UI.Concepts", catalog.TypeFullName);
    Assert.Equal("0x0600026a", catalog.StaticConstructorToken);
    Assert.Equal(111, catalog.Entries.Count);
    Assert.Equal(111, catalog.Entries.Select(entry => entry.Key).Distinct(StringComparer.Ordinal).Count());
    Assert.True(catalog.Entries.All(entry => entry.IsComplete));

    var expectedRegistrationOnlyKeys = new[] { "DEFEND", "ENEMY", "FOOD", "FRIEND" };
    var mapPath = Path.Combine(repositoryRoot, "translations", "concept-key-translations.json");
    using var map = System.Text.Json.JsonDocument.Parse(File.ReadAllText(mapPath));
    var mapKeys = map.RootElement.GetProperty("Concepts")
        .EnumerateArray()
        .Select(entry => entry.GetProperty("Key").GetString()!)
        .ToHashSet(StringComparer.Ordinal);
    var registrationOnlyKeys = catalog.Entries
        .Select(entry => entry.Key)
        .Where(key => !mapKeys.Contains(key))
        .OrderBy(key => key, StringComparer.Ordinal)
        .ToArray();
    Assert.Equal(string.Join("|", expectedRegistrationOnlyKeys), string.Join("|", registrationOnlyKeys));

    var food = catalog.Entries.Single(entry => entry.RegistrationOffset == "IL_0578");
    var bandit = catalog.Entries.Single(entry => entry.RegistrationOffset == "IL_05fa");
    Assert.Equal("FOOD", food.Key);
    Assert.Equal("BANDIT", bandit.Key);

    var social = catalog.Entries.Single(entry => entry.Key == "SOCIAL");
    Assert.Equal("Concat", social.Composition);
    Assert.True(social.Parts.Any(part =>
        part.IlOffset == "<dynamic>" && part.Value == "{font-icon:Social}"));
}

static void FlaxDepositTooltipsCoverAllFieldSizes()
{
    var repositoryRoot = FindRepositoryRoot();
    var sourcePath = Path.Combine(repositoryRoot, "source", "Content", "Config", "OnMap",
        "Deposits.original.xml");
    var mapPath = Path.Combine(repositoryRoot, "translations", "config-node-onmap-strings.json");
    var flaxIds = new[] { "DEPOSIT_FLAX", "DEPOSIT_FLAX_LARGE", "DEPOSIT_FLAX_VAST" };
    var expectedTranslations = new Dictionary<string, string>(StringComparer.Ordinal)
    {
        ["DEPOSIT_FLAX"] = "亚麻田可由[REAPER]或[FLAX-FARM-1][采收|HARVEST]，以[产出|PRODUCE][FLAX]。[BLANK-LINE]当[地块|TILE]变为[寒冷|COLD]时，亚麻无法继续采收。",
        ["DEPOSIT_FLAX_LARGE"] = "亚麻田可由[REAPER]或[FLAX-FARM-1][采收|HARVEST]，以[产出|PRODUCE][FLAX]。[BLANK-LINE]当[地块|TILE]变为[寒冷|COLD]时，亚麻无法继续采收。[BLANK-LINE]这是一大片亚麻田！",
        ["DEPOSIT_FLAX_VAST"] = "亚麻田可由[REAPER]或[FLAX-FARM-1][采收|HARVEST]，以[产出|PRODUCE][FLAX]。[BLANK-LINE]当[地块|TILE]变为[寒冷|COLD]时，亚麻无法继续采收。[BLANK-LINE]这是迄今发现的最大亚麻田之一！"
    };

    var source = System.Xml.Linq.XDocument.Load(sourcePath);
    using var map = System.Text.Json.JsonDocument.Parse(File.ReadAllText(mapPath));
    var depositsMap = map.RootElement.GetProperty(@"Content\Config\OnMap\Deposits.xml");
    Assert.Equal(@"source\Content\Config\OnMap\Deposits.original.xml",
        depositsMap.GetProperty("Source").GetString());
    Assert.Equal("deposit", depositsMap.GetProperty("Container").GetString());

    var sourceDescriptions = source.Root!.Element("Plants")!.Elements("deposit")
        .Where(node => flaxIds.Contains(node.Element("ID")!.Value, StringComparer.Ordinal))
        .ToDictionary(
            node => node.Element("ID")!.Value,
            node => node.Element("description")!.Value,
            StringComparer.Ordinal);
    var translatedDescriptions = depositsMap.GetProperty("Items").EnumerateArray()
        .Where(item => flaxIds.Contains(item.GetProperty("ID").GetString(), StringComparer.Ordinal))
        .ToDictionary(
            item => item.GetProperty("ID").GetString()!,
            item => item.GetProperty("Description").GetString()!,
            StringComparer.Ordinal);

    Assert.True(flaxIds.OrderBy(id => id, StringComparer.Ordinal).SequenceEqual(
        sourceDescriptions.Keys.OrderBy(id => id, StringComparer.Ordinal), StringComparer.Ordinal));
    Assert.True(flaxIds.OrderBy(id => id, StringComparer.Ordinal).SequenceEqual(
        translatedDescriptions.Keys.OrderBy(id => id, StringComparer.Ordinal), StringComparer.Ordinal));

    foreach (var id in flaxIds)
    {
        var translation = translatedDescriptions[id];
        Assert.Equal(expectedTranslations[id], translation);
        Assert.True(ReadFlaxRichTextKeys(sourceDescriptions[id]).OrderBy(key => key, StringComparer.Ordinal)
            .SequenceEqual(ReadFlaxRichTextKeys(translation).OrderBy(key => key, StringComparer.Ordinal),
                StringComparer.Ordinal));

        var displayText = System.Text.RegularExpressions.Regex.Replace(translation, @"\[[^\]]+\]", "");
        Assert.False(System.Text.RegularExpressions.Regex.IsMatch(displayText, "[A-Za-z]"));
    }

    static string[] ReadFlaxRichTextKeys(string value) =>
        System.Text.RegularExpressions.Regex.Matches(value, @"\[([^\]]+)\]")
            .Select(match =>
            {
                var contents = match.Groups[1].Value;
                var separator = contents.IndexOf('|');
                return separator >= 0 ? contents[(separator + 1)..] : contents;
            })
            .ToArray();
}

static void SheepDepositTooltipsCoverAllHerdSizes()
{
    var repositoryRoot = FindRepositoryRoot();
    var sourcePath = Path.Combine(repositoryRoot, "source", "Content", "Config", "OnMap",
        "Deposits.original.xml");
    var mapPath = Path.Combine(repositoryRoot, "translations", "config-node-onmap-strings.json");
    var sheepIds = new[] { "DEPOSIT_SHEEP", "DEPOSIT_SHEEP_LARGE", "DEPOSIT_SHEEP_VAST" };
    var expectedTranslations = new Dictionary<string, string>(StringComparer.Ordinal)
    {
        ["DEPOSIT_SHEEP"] = "[SHEEP]可由[HUNTER]或[TRAPPER][采收|HARVEST]：前者获得[MEAT]，后者获得[PARCHMENT]或[CLOTH]；还可在其上[建造|CONSTRUCT][SHEEP-PASTURE-1]，将其纳入你的[库存|STOCKPILE]，供采集[WOOL]、制作[CLOTH]等其他用途使用。",
        ["DEPOSIT_SHEEP_LARGE"] = "[SHEEP]可由[HUNTER]或[TRAPPER][采收|HARVEST]：前者获得[MEAT]，后者获得[PARCHMENT]或[CLOTH]；还可在其上[建造|CONSTRUCT][SHEEP-PASTURE-1]，将其纳入你的[库存|STOCKPILE]，供采集[WOOL]、制作[CLOTH]等其他用途使用。[BLANK-LINE]这是一大群羊！",
        ["DEPOSIT_SHEEP_VAST"] = "[SHEEP]可由[HUNTER]或[TRAPPER][采收|HARVEST]：前者获得[MEAT]，后者获得[PARCHMENT]或[CLOTH]；还可在其上[建造|CONSTRUCT][SHEEP-PASTURE-1]，将其纳入你的[库存|STOCKPILE]，供采集[WOOL]、制作[CLOTH]等其他用途使用。[BLANK-LINE]这是迄今发现的最大羊群之一！"
    };

    var source = System.Xml.Linq.XDocument.Load(sourcePath);
    using var map = System.Text.Json.JsonDocument.Parse(File.ReadAllText(mapPath));
    var depositsMap = map.RootElement.GetProperty(@"Content\Config\OnMap\Deposits.xml");
    var sourceDescriptions = source.Root!.Element("Animals")!.Elements("deposit")
        .Where(node => sheepIds.Contains(node.Element("ID")!.Value, StringComparer.Ordinal))
        .ToDictionary(
            node => node.Element("ID")!.Value,
            node => node.Element("description")!.Value,
            StringComparer.Ordinal);
    var translatedDescriptions = depositsMap.GetProperty("Items").EnumerateArray()
        .Where(item => sheepIds.Contains(item.GetProperty("ID").GetString(), StringComparer.Ordinal))
        .ToDictionary(
            item => item.GetProperty("ID").GetString()!,
            item => item.GetProperty("Description").GetString()!,
            StringComparer.Ordinal);

    Assert.True(sheepIds.OrderBy(id => id, StringComparer.Ordinal).SequenceEqual(
        sourceDescriptions.Keys.OrderBy(id => id, StringComparer.Ordinal), StringComparer.Ordinal));
    Assert.True(sheepIds.OrderBy(id => id, StringComparer.Ordinal).SequenceEqual(
        translatedDescriptions.Keys.OrderBy(id => id, StringComparer.Ordinal), StringComparer.Ordinal));

    foreach (var id in sheepIds)
    {
        var translation = translatedDescriptions[id];
        Assert.Equal(expectedTranslations[id], translation);
        Assert.True(ReadSheepRichTextKeys(sourceDescriptions[id]).OrderBy(key => key, StringComparer.Ordinal)
            .SequenceEqual(ReadSheepRichTextKeys(translation).OrderBy(key => key, StringComparer.Ordinal),
                StringComparer.Ordinal));

        var displayText = System.Text.RegularExpressions.Regex.Replace(translation, @"\[[^\]]+\]", "");
        Assert.False(System.Text.RegularExpressions.Regex.IsMatch(displayText, "[A-Za-z]"));
    }

    static string[] ReadSheepRichTextKeys(string value) =>
        System.Text.RegularExpressions.Regex.Matches(value, @"\[([^\]]+)\]")
            .Select(match =>
            {
                var contents = match.Groups[1].Value;
                var separator = contents.IndexOf('|');
                return separator >= 0 ? contents[(separator + 1)..] : contents;
            })
            .ToArray();
}

static void ClanFeudTooltipsAndPackWarningUseExactSafeMappings()
{
    var repositoryRoot = FindRepositoryRoot();
    var uiMapPath = Path.Combine(repositoryRoot, "translations", "hardcoded-ui-il-rewrite.json");
    var uiSourcePath = Path.Combine(repositoryRoot, "source", "AtTheGatesUI.original.dll");
    var uiSpecs = RewriteMap.Load(uiMapPath);
    var expectedUiMappings = new[]
    {
        (Original: "\n\nWhen a ", Translation: "\n\n当一个", MethodToken: "0x06000122", IlOffset: 1043),
        (Original: "WARNING: This will result in the current ", Translation: "警告：这会导致当前", MethodToken: "0x0600038a", IlOffset: 529),
    };

    var selectedUiSpecs = expectedUiMappings.Select(expected => uiSpecs.Single(candidate =>
        candidate.MethodToken == expected.MethodToken && candidate.IlOffset == expected.IlOffset &&
        candidate.Original == expected.Original && candidate.Translation == expected.Translation)).ToArray();
    using (var temp = new TempDirectory())
    {
        var output = Path.Combine(temp.Path, "AtTheGatesUI.dll");
        Assert.Equal(selectedUiSpecs.Length,
            ManagedAssemblyRewriter.Rewrite(uiSourcePath, output, selectedUiSpecs).RewrittenCount);
        var rewritten = LdstrCatalog.Read(output);
        foreach (var expected in expectedUiMappings)
        {
            Assert.True(rewritten.Any(candidate => candidate.MethodToken == expected.MethodToken &&
                candidate.IlOffset == expected.IlOffset && candidate.Value == expected.Translation));
        }
    }

    var feudIds = new[]
    {
        "DESIRE_Feud_HatesBadlyBehaved",
        "DESIRE_Feud_SharingTile",
        "DESIRE_Feud_HatesUnpure",
        "DESIRE_Feud_HatesCriminals",
        "DESIRE_Feud_PersonalityClash_TooDemanding",
        "DESIRE_Feud_DramaQueen",
        "DESIRE_Feud_PersonalityClash_Immorality",
        "DESIRE_Feud_PersonalityClash_TooNosy",
        "DESIRE_Feud_PersonalityClash_Competition",
    };
    var configMapPath = Path.Combine(repositoryRoot, "translations", "config-node-strings.json");
    var sourceConfigPath = Path.Combine(repositoryRoot, "source", "Content", "Config", "Primary",
        "ClanDesires.original.xml");
    var sourceConfig = System.Xml.Linq.XDocument.Load(sourceConfigPath);
    using var configMap = System.Text.Json.JsonDocument.Parse(File.ReadAllText(configMapPath));
    var feudMap = configMap.RootElement.GetProperty(@"Content\Config\Primary\ClanDesires.xml");
    Assert.Equal(@"source\Content\Config\Primary\ClanDesires.original.xml",
        feudMap.GetProperty("Source").GetString());
    Assert.Equal("clanDesire", feudMap.GetProperty("Container").GetString());
    var translatedDescriptions = feudMap.GetProperty("Items").EnumerateArray()
        .ToDictionary(
            item => item.GetProperty("ID").GetString()!,
            item => item.GetProperty("Description").GetString()!,
            StringComparer.Ordinal);
    var sourceDescriptions = sourceConfig.Descendants("clanDesire")
        .Where(node => feudIds.Contains(node.Element("ID")!.Value, StringComparer.Ordinal))
        .ToDictionary(
            node => node.Element("ID")!.Value,
            node => node.Element("description")!.Value,
            StringComparer.Ordinal);

    Assert.True(feudIds.OrderBy(id => id, StringComparer.Ordinal).SequenceEqual(
        translatedDescriptions.Keys.OrderBy(id => id, StringComparer.Ordinal), StringComparer.Ordinal));
    Assert.True(feudIds.OrderBy(id => id, StringComparer.Ordinal).SequenceEqual(
        sourceDescriptions.Keys.OrderBy(id => id, StringComparer.Ordinal), StringComparer.Ordinal));
    foreach (var translation in translatedDescriptions.Values)
    {
        Assert.True(translation.Contains("(FEUD-DESC)", StringComparison.Ordinal));
        Assert.True(translation.Contains("(NAME)", StringComparison.Ordinal));
        Assert.True(translation.Contains("(NAME2)", StringComparison.Ordinal));
        Assert.True(translation.Contains("[SETTLEMENT]", StringComparison.Ordinal));
        var displayText = System.Text.RegularExpressions.Regex.Replace(
            translation, @"\([A-Z0-9-]+\)|\[[A-Z-]+\]", "");
        Assert.False(System.Text.RegularExpressions.Regex.IsMatch(displayText, "[A-Za-z]"));
    }

    var intensitiesSourcePath = Path.Combine(repositoryRoot, "source", "Content", "Config", "Misc",
        "Intensities.original.xml");
    var intensitiesMap = configMap.RootElement.GetProperty(@"Content\Config\Misc\Intensities.xml");
    Assert.Equal(@"source\Content\Config\Misc\Intensities.original.xml",
        intensitiesMap.GetProperty("Source").GetString());
    Assert.Equal("intensity", intensitiesMap.GetProperty("Container").GetString());
    var expectedFeudDescriptions = new Dictionary<string, string>(StringComparer.Ordinal)
    {
        ["INTENSITY_CURIOUS"] = "轻微争执",
        ["INTENSITY_INTERESTED"] = "轻微争执",
        ["INTENSITY_DISTRACTED"] = "轻微争执",
        ["INTENSITY_OBSESSED"] = "[COLOR:BAD-RED]名为争执，实为战争[/COLOR]",
    };
    var translatedFeudDescriptions = intensitiesMap.GetProperty("Items").EnumerateArray()
        .ToDictionary(
            item => item.GetProperty("ID").GetString()!,
            item => item.GetProperty("Nodes").EnumerateArray().Single().GetProperty("Value").GetString()!,
            StringComparer.Ordinal);
    var sourceIntensities = System.Xml.Linq.XDocument.Load(intensitiesSourcePath)
        .Descendants("intensity")
        .Where(node => expectedFeudDescriptions.ContainsKey(node.Element("ID")!.Value))
        .ToDictionary(
            node => node.Element("ID")!.Value,
            node => node.Element("feudDescription")!.Value,
            StringComparer.Ordinal);

    Assert.True(expectedFeudDescriptions.Keys.OrderBy(id => id, StringComparer.Ordinal).SequenceEqual(
        translatedFeudDescriptions.Keys.OrderBy(id => id, StringComparer.Ordinal), StringComparer.Ordinal));
    foreach (var expected in expectedFeudDescriptions)
    {
        Assert.Equal(expected.Value, translatedFeudDescriptions[expected.Key]);
    }
    Assert.True(expectedFeudDescriptions.Keys.OrderBy(id => id, StringComparer.Ordinal).SequenceEqual(
        sourceIntensities.Keys.OrderBy(id => id, StringComparer.Ordinal), StringComparer.Ordinal));
    foreach (var value in translatedFeudDescriptions.Values)
    {
        var displayText = System.Text.RegularExpressions.Regex.Replace(value, @"\[[^\]]+\]", "");
        Assert.False(System.Text.RegularExpressions.Regex.IsMatch(displayText, "[A-Za-z]"));
    }
}

static void BesiegeTooltipMapsEveryComposedLiteral()
{
    var repositoryRoot = FindRepositoryRoot();
    var mapPath = Path.Combine(repositoryRoot, "translations", "hardcoded-ui-il-rewrite.json");
    var specs = RewriteMap.Load(mapPath);
    var source = Path.Combine(repositoryRoot, "source", "AtTheGatesUI.original.dll");
    const string methodToken = "0x06000384";

    var sourceStrings = LdstrCatalog.Read(source)
        .Where(candidate => candidate.MethodToken == methodToken)
        .OrderBy(candidate => candidate.IlOffset)
        .ToArray();
    Assert.Equal(16, sourceStrings.Length);

    var familySpecs = specs.Where(candidate =>
        candidate.MethodToken == methodToken && sourceStrings.Any(sourceString =>
            sourceString.IlOffset == candidate.IlOffset && sourceString.Value == candidate.Original))
        .ToArray();
    Assert.Equal(sourceStrings.Length, familySpecs.Length);

    foreach (var sourceString in sourceStrings)
    {
        Assert.True(familySpecs.Any(candidate =>
            candidate.IlOffset == sourceString.IlOffset && candidate.Original == sourceString.Value));
    }

    using var temp = new TempDirectory();
    var output = Path.Combine(temp.Path, "AtTheGatesUI.dll");
    var result = ManagedAssemblyRewriter.Rewrite(source, output, familySpecs);
    Assert.Equal(sourceStrings.Length, result.RewrittenCount);

    var rewritten = LdstrCatalog.Read(output);
    foreach (var spec in familySpecs)
    {
        Assert.True(rewritten.Any(candidate =>
            candidate.MethodToken == methodToken && candidate.IlOffset == spec.IlOffset &&
            candidate.Value == spec.Translation));
    }
}

static void RewriteCoordinatorCachesJobs()
{
    using var temp = new TempDirectory();
    var source = typeof(RewriteFixture).Assembly.Location;
    var entry = LdstrCatalog.Read(source).Single(x => x.Value == RewriteFixture.Value());
    var map = temp.Write("map.json", $$"""
        [{
          "MethodToken": "{{entry.MethodToken}}",
          "ILOffset": {{entry.IlOffset}},
          "Original": "{{entry.Value}}",
          "Translation": "协调器译文"
        }]
        """);
    var output = System.IO.Path.Combine(temp.Path, "output.dll");
    var cache = new BuildCache(System.IO.Path.Combine(temp.Path, "build-cache.json"));
    var job = new RewriteJob("fixture", source, output, map);

    var first = ManagedRewriteCoordinator.RunAsync([job], cache).GetAwaiter().GetResult();
    var second = ManagedRewriteCoordinator.RunAsync([job], cache).GetAwaiter().GetResult();

    Assert.Equal(1, first.Single().RewrittenCount);
    Assert.False(first.Single().CacheHit);
    Assert.True(second.Single().CacheHit);
}

static void RepositoryRewritePlanDiscoversAssemblies()
{
    using var temp = new TempDirectory();
    temp.Write("source/AtTheGatesUI.original.dll", "fixture");
    temp.Write("translations/hardcoded-ui-il-rewrite.json", "[]");
    temp.Write("source/ElfTools.original.dll", "fixture");
    temp.Write("translations/hardcoded-elftools-il-rewrite.json", "[]");

    var jobs = RepositoryRewritePlan.Create(temp.Path);

    Assert.Equal(2, jobs.Count);
    Assert.Equal("ui", jobs[0].Name);
    Assert.Equal("elftools", jobs[1].Name);
    Assert.True(jobs.All(job => job.OutputPath.StartsWith(
        Path.Combine(temp.Path, ".cache", "managed-rewrite"),
        StringComparison.OrdinalIgnoreCase)));
}

static void ManagedRewriterRedirectsCall()
{
    using var temp = new TempDirectory();
    var source = typeof(CallRedirectFixture).Assembly.Location;
    var output = Path.Combine(temp.Path, "redirected.dll");
    var calls = ManagedCallCatalog.Read(source);
    var sourceCall = calls.Single(call =>
        call.CallerType.EndsWith(nameof(CallRedirectFixture), StringComparison.Ordinal) &&
        call.CallerMethod == nameof(CallRedirectFixture.Invoke) &&
        call.TargetFullName.Contains("System.String::Trim()", StringComparison.Ordinal));
    var target = ManagedMethodCatalog.Read(source).Single(method =>
        method.DeclaringType.EndsWith(nameof(CallRedirectTarget), StringComparison.Ordinal) &&
        method.Name == nameof(CallRedirectTarget.Trim));

    var result = ManagedCallRedirector.Redirect(source, output, source,
    [
        new CallRedirectSpec(sourceCall.TargetFullName, target.MetadataToken, 1,
            sourceCall.CallerToken, sourceCall.IlOffset),
    ]);

    Assert.Equal(1, result.RedirectedCount);
    var redirected = ManagedCallCatalog.Read(output).Single(call =>
        call.CallerType.EndsWith(nameof(CallRedirectFixture), StringComparison.Ordinal) &&
        call.CallerMethod == nameof(CallRedirectFixture.Invoke));
    Assert.True(redirected.TargetFullName.Contains(nameof(CallRedirectTarget), StringComparison.Ordinal));
    Assert.Equal("call", redirected.OpCode);
}

static void ManagedRewriterRegistersReturnedValue()
{
    using var temp = new TempDirectory();
    var source = typeof(ReturnRegistrationFixture).Assembly.Location;
    var output = Path.Combine(temp.Path, "registered.dll");
    var caller = ManagedMethodCatalog.Read(source).Single(method =>
        method.DeclaringType.EndsWith(nameof(ReturnRegistrationFixture), StringComparison.Ordinal) &&
        method.Name == nameof(ReturnRegistrationFixture.Get));
    var target = ManagedMethodCatalog.Read(source).Single(method =>
        method.DeclaringType.EndsWith(nameof(ReturnRegistrationTarget), StringComparison.Ordinal) &&
        method.Name == nameof(ReturnRegistrationTarget.RegisterAndReturn));

    var result = ManagedReturnValueRegistrar.Register(source, output, source,
    [
        new ReturnValueRegistrationSpec(caller.MetadataToken, target.MetadataToken,
            "SegoeUI_15_Bold", 15f, true, 1),
    ]);

    Assert.Equal(1, result.RegisteredCount);
    var outputCaller = ManagedMethodCatalog.Read(output).Single(method =>
        method.DeclaringType.EndsWith(nameof(ReturnRegistrationFixture), StringComparison.Ordinal) &&
        method.Name == nameof(ReturnRegistrationFixture.Get));
    Assert.Equal(caller.MetadataToken, outputCaller.MetadataToken);
    var call = ManagedCallCatalog.Read(output).Single(entry =>
        entry.CallerType.EndsWith(nameof(ReturnRegistrationFixture), StringComparison.Ordinal) &&
        entry.CallerMethod == nameof(ReturnRegistrationFixture.Get));
    if (!call.TargetFullName.Contains(nameof(ReturnRegistrationTarget), StringComparison.Ordinal))
        throw new InvalidOperationException($"Registration call targets '{call.TargetFullName}'.");
    var strings = LdstrCatalog.Read(output);
    if (!strings.Any(entry => entry.TypeFullName.EndsWith(nameof(ReturnRegistrationFixture), StringComparison.Ordinal) &&
        entry.MethodName == nameof(ReturnRegistrationFixture.Get) && entry.Value == "SegoeUI_15_Bold"))
        throw new InvalidOperationException($"Injected font name was not found in caller {caller.MetadataToken}. " +
            string.Join("; ", strings.Where(entry => entry.Value == "SegoeUI_15_Bold")
                .Select(entry => $"{entry.TypeFullName}.{entry.MethodName} {entry.MethodToken}")));
}

static void ManagedRewriterRedirectsConstructedGenericCall()
{
    using var temp = new TempDirectory();
    var source = typeof(GenericCallFixture).Assembly.Location;
    var output = Path.Combine(temp.Path, "generic-redirected.dll");
    var sourceCall = ManagedCallCatalog.Read(source).Single(call =>
        call.CallerType.EndsWith(nameof(GenericCallFixture), StringComparison.Ordinal) &&
        call.CallerMethod == nameof(GenericCallFixture.Invoke) &&
        call.TargetFullName.Contains("Identity<System.String>", StringComparison.Ordinal));
    var target = ManagedMethodCatalog.Read(source).Single(method =>
        method.DeclaringType.EndsWith(nameof(GenericCallTarget), StringComparison.Ordinal) &&
        method.Name == nameof(GenericCallTarget.Pass));

    var result = ManagedCallRedirector.Redirect(source, output, source,
    [
        new CallRedirectSpec(sourceCall.TargetFullName, target.MetadataToken, 1,
            sourceCall.CallerToken, sourceCall.IlOffset),
    ]);

    Assert.Equal(1, result.RedirectedCount);
}

static void ManagedRewriterFiltersStringField()
{
    using var temp = new TempDirectory();
    var source = typeof(FieldFilterFixture).Assembly.Location;
    var output = Path.Combine(temp.Path, "field-filtered.dll");
    var caller = ManagedMethodCatalog.Read(source).Single(method =>
        method.DeclaringType.EndsWith(nameof(FieldFilterFixture), StringComparison.Ordinal) &&
        method.Name == nameof(FieldFilterFixture.Process));
    var target = ManagedMethodCatalog.Read(source).Single(method =>
        method.DeclaringType.EndsWith(nameof(FieldFilterTarget), StringComparison.Ordinal) &&
        method.Name == nameof(FieldFilterTarget.Filter));
    var fieldName = "System.String " + typeof(FieldFilterFixture).FullName + "::RawText";

    var result = ManagedStringFieldFilterInjector.Inject(source, output, source,
    [
        new StringFieldFilterSpec(caller.MetadataToken, fieldName, target.MetadataToken, 1),
    ]);

    Assert.Equal(1, result.InjectedCount);
    var injected = ManagedCallCatalog.Read(output).Single(call =>
        call.CallerType.EndsWith(nameof(FieldFilterFixture), StringComparison.Ordinal) &&
        call.CallerMethod == nameof(FieldFilterFixture.Process));
    Assert.True(injected.TargetFullName.Contains(nameof(FieldFilterTarget), StringComparison.Ordinal));
}

static void ManagedRewriterFiltersStringReturn()
{
    using var temp = new TempDirectory();
    var source = typeof(ReturnFilterFixture).Assembly.Location;
    var output = Path.Combine(temp.Path, "return-filtered.dll");
    var caller = ManagedMethodCatalog.Read(source).Single(method =>
        method.DeclaringType.EndsWith(nameof(ReturnFilterFixture), StringComparison.Ordinal) &&
        method.Name == nameof(ReturnFilterFixture.Get));
    var target = ManagedMethodCatalog.Read(source).Single(method =>
        method.DeclaringType.EndsWith(nameof(ReturnFilterTarget), StringComparison.Ordinal) &&
        method.Name == nameof(ReturnFilterTarget.Filter));

    var result = ManagedStringReturnFilterInjector.Inject(source, output, source,
    [
        new StringReturnFilterSpec(caller.MetadataToken, target.MetadataToken, 1),
    ]);

    Assert.Equal(1, result.InjectedCount);
    var injected = ManagedCallCatalog.Read(output).Single(call =>
        call.CallerType.EndsWith(nameof(ReturnFilterFixture), StringComparison.Ordinal) &&
        call.CallerMethod == nameof(ReturnFilterFixture.Get));
    Assert.True(injected.TargetFullName.Contains(nameof(ReturnFilterTarget), StringComparison.Ordinal));
}

static void ManagedRewriterFiltersOneExplicitCallResult()
{
    using var temp = new TempDirectory();
    var source = typeof(CallResultFilterFixture).Assembly.Location;
    var output = Path.Combine(temp.Path, "call-result-filtered.dll");
    var methods = ManagedMethodCatalog.Read(source);
    var caller = methods.Single(method =>
        method.DeclaringType.EndsWith(nameof(CallResultFilterFixture), StringComparison.Ordinal) &&
        method.Name == nameof(CallResultFilterFixture.BuildLabel));
    var target = methods.Single(method =>
        method.DeclaringType.EndsWith(nameof(CallResultFilterTarget), StringComparison.Ordinal) &&
        method.Name == nameof(CallResultFilterTarget.Filter));
    var sourceCall = ManagedCallCatalog.Read(source).Single(call =>
        call.CallerToken == caller.MetadataToken &&
        call.TargetFullName.Contains(nameof(CallResultFilterFixture.GetFactionName), StringComparison.Ordinal));

    var result = ManagedCallResultFilterInjector.Inject(source, output, source,
    [
        new CallResultFilterSpec(caller.MetadataToken, sourceCall.IlOffset,
            sourceCall.TargetFullName, target.MetadataToken, 1),
    ]);

    Assert.Equal(1, result.InjectedCount);
    var outputCalls = ManagedCallCatalog.Read(output)
        .Where(call => call.CallerToken == caller.MetadataToken)
        .OrderBy(call => call.IlOffset)
        .ToArray();
    var sourceIndex = Array.FindIndex(outputCalls, call =>
        call.TargetFullName.Contains(nameof(CallResultFilterFixture.GetFactionName), StringComparison.Ordinal));
    Assert.True(sourceIndex >= 0 && sourceIndex + 1 < outputCalls.Length);
    Assert.True(outputCalls[sourceIndex + 1].TargetFullName.Contains(
        nameof(CallResultFilterTarget.Filter), StringComparison.Ordinal));
}

static void ManagedRewriterFiltersMethodArgument()
{
    using var temp = new TempDirectory();
    var source = typeof(ArgumentFilterFixture).Assembly.Location;
    var output = Path.Combine(temp.Path, "argument-filtered.dll");
    var methods = ManagedMethodCatalog.Read(source);
    var stringCaller = methods.Single(method =>
        method.DeclaringType.EndsWith(nameof(ArgumentFilterFixture), StringComparison.Ordinal) &&
        method.Name == nameof(ArgumentFilterFixture.RewriteString));
    var builderCaller = methods.Single(method =>
        method.DeclaringType.EndsWith(nameof(ArgumentFilterFixture), StringComparison.Ordinal) &&
        method.Name == nameof(ArgumentFilterFixture.RewriteBuilder));
    var stringTarget = methods.Single(method =>
        method.DeclaringType.EndsWith(nameof(ArgumentFilterTarget), StringComparison.Ordinal) &&
        method.Name == nameof(ArgumentFilterTarget.FilterString));
    var builderTarget = methods.Single(method =>
        method.DeclaringType.EndsWith(nameof(ArgumentFilterTarget), StringComparison.Ordinal) &&
        method.Name == nameof(ArgumentFilterTarget.FilterBuilder));

    var result = ManagedMethodArgumentFilterInjector.Inject(source, output, source,
    [
        new MethodArgumentFilterSpec(stringCaller.MetadataToken, 0, stringTarget.MetadataToken, 1),
        new MethodArgumentFilterSpec(builderCaller.MetadataToken, 0, builderTarget.MetadataToken, 1),
    ]);

    Assert.Equal(2, result.InjectedCount);
    var calls = ManagedCallCatalog.Read(output);
    Assert.True(calls.Any(call =>
        call.CallerType.EndsWith(nameof(ArgumentFilterFixture), StringComparison.Ordinal) &&
        call.CallerMethod == nameof(ArgumentFilterFixture.RewriteString) &&
        call.TargetFullName.Contains(nameof(ArgumentFilterTarget.FilterString), StringComparison.Ordinal)));
    Assert.True(calls.Any(call =>
        call.CallerType.EndsWith(nameof(ArgumentFilterFixture), StringComparison.Ordinal) &&
        call.CallerMethod == nameof(ArgumentFilterFixture.RewriteBuilder) &&
        call.TargetFullName.Contains(nameof(ArgumentFilterTarget.FilterBuilder), StringComparison.Ordinal)));
}

static void ManagedRewriterInjectsMethodEntryHook()
{
    using var temp = new TempDirectory();
    var source = typeof(MethodEntryFixture).Assembly.Location;
    var output = Path.Combine(temp.Path, "method-entry-hooked.dll");
    var caller = ManagedMethodCatalog.Read(source).Single(method =>
        method.DeclaringType.EndsWith(nameof(MethodEntryFixture), StringComparison.Ordinal) &&
        method.Name == nameof(MethodEntryFixture.Draw));
    var target = ManagedMethodCatalog.Read(source).Single(method =>
        method.DeclaringType.EndsWith(nameof(MethodEntryTarget), StringComparison.Ordinal) &&
        method.Name == nameof(MethodEntryTarget.BeginFrame));

    var result = ManagedMethodEntryInjector.Inject(source, output, source,
    [
        new MethodEntryHookSpec(caller.MetadataToken, target.MetadataToken, 1),
    ]);

    Assert.Equal(1, result.InjectedCount);
    var injected = ManagedCallCatalog.Read(output).Single(call =>
        call.CallerType.EndsWith(nameof(MethodEntryFixture), StringComparison.Ordinal) &&
        call.CallerMethod == nameof(MethodEntryFixture.Draw) &&
        call.TargetFullName.Contains(nameof(MethodEntryTarget), StringComparison.Ordinal));
    Assert.Equal("call", injected.OpCode);
}

static void ManagedRewriterInjectsInstanceEntryHook()
{
    using var temp = new TempDirectory();
    var source = typeof(MethodEntryFixture).Assembly.Location;
    var output = Path.Combine(temp.Path, "instance-entry-hooked.dll");
    var caller = ManagedMethodCatalog.Read(source).Single(method =>
        method.DeclaringType.EndsWith(nameof(MethodEntryFixture), StringComparison.Ordinal) &&
        method.Name == nameof(MethodEntryFixture.LoadContent));
    var target = ManagedMethodCatalog.Read(source).Single(method =>
        method.DeclaringType.EndsWith(nameof(MethodEntryTarget), StringComparison.Ordinal) &&
        method.Name == nameof(MethodEntryTarget.PrepareStartupGraphics));

    var result = ManagedMethodEntryInjector.Inject(source, output, source,
    [
        new MethodEntryHookSpec(caller.MetadataToken, target.MetadataToken, 1, PassCallerInstance: true),
    ]);

    Assert.Equal(1, result.InjectedCount);
    using var module = ModuleDefMD.Load(output);
    var hookedCaller = module.GetTypes().SelectMany(type => type.Methods).Single(method =>
        method.MDToken.Raw == uint.Parse(caller.MetadataToken[2..], System.Globalization.NumberStyles.HexNumber));
    Assert.Equal(OpCodes.Ldarg_0, hookedCaller.Body.Instructions[0].OpCode);
    Assert.Equal(OpCodes.Call, hookedCaller.Body.Instructions[1].OpCode);
}

static void RuntimeDisplayMapPreservesConceptKeys()
{
    using var temp = new TempDirectory();
    var map = temp.Write("runtime-display.json", """
        {
          "Exact": [{ "Original": "Close", "Translation": "\u5173\u95ed" }],
          "PlainText": [{ "Original": "Train ", "Translation": "\u8bad\u7ec3" }],
          "PlainTextFragments": [{ "Original": "engage in ", "Translation": "\u5377\u5165" }],
          "RichTextFragments": [{ "Original": "[Clan|CLAN] in the [Turn|TURN]", "Translation": "[Clan|CLAN]\uFF0C\u6240\u5C5E\u4E3A[Turn|TURN]" }],
          "Templates": [{ "Original": "Leader Trait ({arg:0})", "Translation": "\u9886\u8896\u7279\u8D28\uFF08{arg:0}\uFF09" }],
          "ConceptDisplay": [{ "ConceptKey": "CLAN", "Original": "Clan", "Translation": "\u6c0f\u65cf" }]
        }
        """);
    var output = Path.Combine(temp.Path, "AtG.RuntimeText.tsv");

    var result = RuntimeDisplayMapBuilder.Build(
        typeof(RuntimeMapConceptFixture).Assembly.Location,
        typeof(RuntimeMapConceptFixture).FullName!, map, output);

    Assert.True(result.ConceptKeyCount >= 2);
    var lines = File.ReadAllLines(output);
    Assert.True(lines.Any(line => line == "K\t" + RuntimeMapConceptFixture.Encode("CLAN")));
    Assert.True(lines.Any(line => line == "K\t" + RuntimeMapConceptFixture.Encode("TURN")));
    Assert.True(lines.Any(line => line == "C\t" + RuntimeMapConceptFixture.Encode("CLAN") + "\t" +
        RuntimeMapConceptFixture.Encode("Clan") + "\t" + RuntimeMapConceptFixture.Encode("\u6c0f\u65cf")));
    Assert.Equal(1, result.PlainTextFragmentCount);
    Assert.Equal(1, result.RichTextFragmentCount);
    Assert.True(lines.Any(line => line == "F\t" + RuntimeMapConceptFixture.Encode("engage in ") + "\t" +
        RuntimeMapConceptFixture.Encode("\u5377\u5165")));
    Assert.True(lines.Any(line => line == "R\t" + RuntimeMapConceptFixture.Encode("[Clan|CLAN] in the [Turn|TURN]") + "\t" +
        RuntimeMapConceptFixture.Encode("[Clan|CLAN]\uFF0C\u6240\u5C5E\u4E3A[Turn|TURN]")));
    Assert.True(lines.Any(line => line == "T\t" + RuntimeMapConceptFixture.Encode("Leader Trait ({arg:0})") + "\t" +
        RuntimeMapConceptFixture.Encode("\u9886\u8896\u7279\u8D28\uFF08{arg:0}\uFF09")));
}

static void RuntimeDisplayMapImportsConceptTags()
{
    using var temp = new TempDirectory();
    temp.Write("approved-concepts.json", """
        {
          "[Clan|CLAN]": "[\u6c0f\u65cf|CLAN]",
          "[Turn|TURN]": "[\u56de\u5408|TURN]",
          "Click [Clan|CLAN]": "\u70b9\u51fb[\u6c0f\u65cf|CLAN]"
        }
        """);
    var map = temp.Write("runtime-display.json", """
        {
          "ConceptDisplaySources": ["approved-concepts.json"]
        }
        """);
    var output = Path.Combine(temp.Path, "AtG.RuntimeText.tsv");

    var result = RuntimeDisplayMapBuilder.Build(
        typeof(RuntimeMapConceptFixture).Assembly.Location,
        typeof(RuntimeMapConceptFixture).FullName!, map, output);

    Assert.Equal(2, result.ConceptDisplayCount);
    var lines = File.ReadAllLines(output);
    Assert.True(lines.Any(line => line == "C\t" + RuntimeMapConceptFixture.Encode("CLAN") + "\t" +
        RuntimeMapConceptFixture.Encode("Clan") + "\t" +
        RuntimeMapConceptFixture.Encode("\u6c0f\u65cf")));
    Assert.True(lines.Any(line => line == "C\t" + RuntimeMapConceptFixture.Encode("TURN") + "\t" +
        RuntimeMapConceptFixture.Encode("Turn") + "\t" +
        RuntimeMapConceptFixture.Encode("\u56de\u5408")));
}

static void RuntimeDisplayMapImportsCompositeExactEntries()
{
    using var temp = new TempDirectory();
    temp.Write("composite-text-rules.json", """
        {
          "Entries": [
            {
              "EntryPointId": "managed:fixture:IL_0001",
              "Source": { "Kind": "Managed" },
              "OriginalFormat": "A Clan is idle.",
              "LocalizedFormat": "\u6709\u6C0F\u65CF\u5904\u4E8E\u7A7A\u95F2\u72B6\u6001\u3002",
              "Classification": "DisplayComposite",
              "Status": "Mapped",
              "RuleId": "runtime-display-exact",
              "Stale": false
            },
            {
              "EntryPointId": "managed:stale:IL_0002",
              "Source": { "Kind": "Managed" },
              "OriginalFormat": "Stale text.",
              "LocalizedFormat": "\u8FC7\u671F\u6587\u672C\u3002",
              "Classification": "DisplayComposite",
              "Status": "Stale",
              "RuleId": "runtime-display-exact",
              "Stale": true
            }
          ]
        }
        """);
    var map = temp.Write("runtime-display.json", """
        {
          "CompositeExactSources": ["composite-text-rules.json"]
        }
        """);
    var output = Path.Combine(temp.Path, "AtG.RuntimeText.tsv");

    var result = RuntimeDisplayMapBuilder.Build(
        typeof(RuntimeMapConceptFixture).Assembly.Location,
        typeof(RuntimeMapConceptFixture).FullName!, map, output);

    Assert.Equal(1, result.ExactCount);
    var lines = File.ReadAllLines(output);
    Assert.True(lines.Any(line => line == "E\t" + RuntimeMapConceptFixture.Encode("A Clan is idle.") +
        "\t" + RuntimeMapConceptFixture.Encode("\u6709\u6C0F\u65CF\u5904\u4E8E\u7A7A\u95F2\u72B6\u6001\u3002")));
    Assert.False(lines.Any(line => line.Contains(RuntimeMapConceptFixture.Encode("Stale text."),
        StringComparison.Ordinal)));
}

static void RuntimeDisplayMapImportsUniformCompositeFragments()
{
    using var temp = new TempDirectory();
    temp.Write("composite-text-rules.json", """
        {
          "Entries": [
            {
              "EntryPointId": "managed:one",
              "Source": { "Kind": "Managed" },
              "Parts": [
                { "Position": 0, "Kind": "Literal", "Value": "Can explore " },
                { "Position": 1, "Kind": "Argument", "Value": "" }
              ]
            },
            {
              "EntryPointId": "managed:two",
              "Source": { "Kind": "Managed" },
              "Parts": [
                { "Position": 0, "Kind": "Literal", "Value": "Can explore " },
                { "Position": 1, "Kind": "Argument", "Value": "" }
              ]
            },
            {
              "EntryPointId": "managed:conflict",
              "Source": { "Kind": "Managed" },
              "Parts": [
                { "Position": 0, "Kind": "Literal", "Value": "Cannot " },
                { "Position": 1, "Kind": "Argument", "Value": "" }
              ]
            },
            {
              "EntryPointId": "managed:empty",
              "Source": { "Kind": "Managed" },
              "Parts": [
                { "Position": 0, "Kind": "Literal", "Value": "Already " },
                { "Position": 1, "Kind": "Argument", "Value": "" }
              ]
            },
            {
              "EntryPointId": "managed:generic-the",
              "Source": { "Kind": "Managed" },
              "Parts": [
                { "Position": 0, "Kind": "Literal", "Value": "The " },
                { "Position": 1, "Kind": "Argument", "Value": "" }
              ]
            },
            {
              "EntryPointId": "rewrite:one",
              "Source": { "Kind": "ManagedRewriteMap" },
              "OriginalFormat": "Can explore ",
              "LocalizedFormat": "\u53ef\u63a2\u7d22",
              "Stale": false
            },
            {
              "EntryPointId": "rewrite:two",
              "Source": { "Kind": "ManagedRewriteMap" },
              "OriginalFormat": "Cannot ",
              "LocalizedFormat": "\u65e0\u6cd5",
              "Stale": false
            },
            {
              "EntryPointId": "rewrite:three",
              "Source": { "Kind": "ManagedRewriteMap" },
              "OriginalFormat": "Cannot ",
              "LocalizedFormat": "\u5f53\u524d\u65e0\u6cd5",
              "Stale": false
            },
            {
              "EntryPointId": "rewrite:empty",
              "Source": { "Kind": "ManagedRewriteMap" },
              "OriginalFormat": "Already ",
              "LocalizedFormat": "",
              "Stale": false
            },
            {
              "EntryPointId": "rewrite:generic-the",
              "Source": { "Kind": "ManagedRewriteMap" },
              "OriginalFormat": "The ",
              "LocalizedFormat": "\u8BE5",
              "Stale": false
            }
          ]
        }
        """);
    var map = temp.Write("runtime-display.json", """
        {
          "CompositeFragmentSources": ["composite-text-rules.json"]
        }
        """);
    var output = Path.Combine(temp.Path, "AtG.RuntimeText.tsv");

    var result = RuntimeDisplayMapBuilder.Build(
        typeof(RuntimeMapConceptFixture).Assembly.Location,
        typeof(RuntimeMapConceptFixture).FullName!, map, output);

    Assert.Equal(1, result.PlainTextFragmentCount);
    var lines = File.ReadAllLines(output);
    Assert.True(lines.Any(line => line == "F\t" + RuntimeMapConceptFixture.Encode("Can explore ") +
        "\t" + RuntimeMapConceptFixture.Encode("\u53ef\u63a2\u7d22")));
    Assert.False(lines.Any(line => line.Contains(RuntimeMapConceptFixture.Encode("Cannot "),
        StringComparison.Ordinal)));
    Assert.False(lines.Any(line => line.StartsWith("F\t" +
        RuntimeMapConceptFixture.Encode("Already ") + "\t", StringComparison.Ordinal)));
    Assert.False(lines.Any(line => line.StartsWith("F\t" +
        RuntimeMapConceptFixture.Encode("The ") + "\t", StringComparison.Ordinal)));
}

static void RuntimeDisplayMapRejectsGenericCompositeTemplates()
{
    using var temp = new TempDirectory();
    temp.Write("composite-text-rules.json", """
        {
          "Entries": [
            {
              "EntryPointId": "managed:unsafe",
              "Source": { "Kind": "Managed" },
              "OriginalFormat": "{arg:0} {arg:2}",
              "LocalizedFormat": "{arg:0}\u7ea7{arg:2}",
              "RuleId": "runtime-display-template",
              "Stale": false
            },
            {
              "EntryPointId": "managed:safe",
              "Source": { "Kind": "Managed" },
              "OriginalFormat": "Cannot {arg:1} Right Now",
              "LocalizedFormat": "\u5f53\u524d\u65e0\u6cd5{arg:1}",
              "RuleId": "runtime-display-template",
              "Stale": false
            }
          ]
        }
        """);
    var map = temp.Write("runtime-display.json", """
        {
          "CompositeTemplateSources": ["composite-text-rules.json"]
        }
        """);
    var output = Path.Combine(temp.Path, "AtG.RuntimeText.tsv");

    RuntimeDisplayMapBuilder.Build(
        typeof(RuntimeMapConceptFixture).Assembly.Location,
        typeof(RuntimeMapConceptFixture).FullName!, map, output);

    var lines = File.ReadAllLines(output);
    Assert.False(lines.Any(line => line == "T\t" +
        RuntimeMapConceptFixture.Encode("{arg:0} {arg:2}") + "\t" +
        RuntimeMapConceptFixture.Encode("{arg:0}\u7ea7{arg:2}")));
    Assert.True(lines.Any(line => line == "T\t" +
        RuntimeMapConceptFixture.Encode("Cannot {arg:1} Right Now") + "\t" +
        RuntimeMapConceptFixture.Encode("\u5f53\u524d\u65e0\u6cd5{arg:1}")));
}

static void CompositeCatalogDiscoversTemplatesAndPreservesRules()
{
    using var temp = new TempDirectory();
    var sourceAssembly = typeof(CompositeCatalogFixture).Assembly.Location;
    var sourcePath = Path.Combine(temp.Path, "source", "AtTheGatesUI.original.dll");
    Directory.CreateDirectory(Path.GetDirectoryName(sourcePath)!);
    File.Copy(sourceAssembly, sourcePath);
    temp.Write("source/Fixture.original.xml", """
        <root>
          <entry>[Producing|PRODUCE] during [Turn|TURN]: {0}</entry>
          <plural>|Turn|Turns|</plural>
        </root>
        """);
    temp.Write("patch/Content/Fixture.xml", """
        <root>
          <entry>每[回合|TURN]产出{0} [产出|PRODUCE]</entry>
          <plural>|回合|回合|</plural>
        </root>
        """);

    var rulesPath = Path.Combine(temp.Path, "translations", "composite-text-rules.json");
    var result = CompositeTextCatalog.Build(temp.Path, rulesPath);
    Assert.True(result.ManagedEntryCount >= 4);

    var first = ReadCompositeCatalog(rulesPath);

    foreach (var callKind in new[] { "String.Concat", "String.Format", "String.Join", "StringBuilder.Append" })
        Assert.True(first.Entries.Any(entry => entry.Source.Kind == "Managed" &&
            entry.Source.CallKind == callKind));
    var xmlEntry = first.Entries.Single(entry => entry.Source.Kind == "Xml" &&
        entry.OriginalFormat.Contains("[Producing|PRODUCE]", StringComparison.Ordinal));
    Assert.Equal("每[回合|TURN]产出{0} [产出|PRODUCE]", xmlEntry.LocalizedFormat);
    Assert.True(first.Entries.Any(entry => entry.Source.Kind == "Xml" &&
        entry.OriginalFormat == "|Turn|Turns|" && entry.LocalizedFormat == "|回合|回合|"));

    CompositeTextCatalog.Validate(
    [
        new CompositeTextEntry
        {
            EntryPointId = "fixture:legacy-ennoble",
            OriginalFormat = "[Ennoble]",
            LocalizedFormat = "[册封|NOBLE]",
        },
        new CompositeTextEntry
        {
            EntryPointId = "fixture:plain-respect",
            OriginalFormat = "[Respect|RESPECT]",
            LocalizedFormat = "尊重",
        },
    ], []);

    xmlEntry.RuleId = "fixture-manual";
    xmlEntry.Status = "Approved";
    xmlEntry.Notes = "Fixture validates manual composite format preservation.";
    first.Rules.Add(new CompositeLocalizationRule
    {
        RuleId = "fixture-manual",
        Kind = "ManualTemplate",
        Status = "Active",
        EntryPointId = xmlEntry.EntryPointId,
        Description = "Fixture manual rule must survive regeneration.",
        Source = "tests",
    });
    WriteCompositeCatalog(rulesPath, first);

    CompositeTextCatalog.Build(temp.Path, rulesPath);
    var regenerated = ReadCompositeCatalog(rulesPath);
    var preserved = regenerated.Entries.Single(entry => entry.EntryPointId == xmlEntry.EntryPointId);
    Assert.Equal("fixture-manual", preserved.RuleId);
    Assert.Equal("Approved", preserved.Status);
    Assert.True(regenerated.Rules.Any(rule => rule.RuleId == "fixture-manual" &&
        rule.Description == "Fixture manual rule must survive regeneration."));

    preserved.LocalizedFormat = "[错误|WRONG]{0}";
    WriteCompositeCatalog(rulesPath, regenerated);
    var rejected = false;
    try
    {
        CompositeTextCatalog.Build(temp.Path, rulesPath);
    }
    catch (InvalidDataException)
    {
        rejected = true;
    }
    Assert.True(rejected);
}

static void CompositeCatalogRefreshesRuntimeMapTranslations()
{
    using var temp = new TempDirectory();
    const string mapPath = "translations/runtime-display-strings.json";
    var rulesPath = Path.Combine(temp.Path, "translations", "composite-text-rules.json");

    temp.Write(mapPath, """
        {
          "PlainTextFragments": [
            { "Original": "Make War", "Translation": "\u5BA3\u6218" }
          ]
        }
        """);
    CompositeTextCatalog.Build(temp.Path, rulesPath);

    temp.Write(mapPath, """
        {
          "PlainTextFragments": [
            { "Original": "Make War", "Translation": "\u6311\u8D77\u6218\u4E89" }
          ]
        }
        """);
    CompositeTextCatalog.Build(temp.Path, rulesPath);

    var regenerated = ReadCompositeCatalog(rulesPath);
    var entry = regenerated.Entries.Single(candidate =>
        candidate.Source.Kind == "RuntimeMap" &&
        candidate.OriginalFormat == "Make War");
    Assert.Equal("\u6311\u8D77\u6218\u4E89", entry.LocalizedFormat);
}

static void CompositeCatalogPermitsBareRuntimeDisplayReplacements()
{
    CompositeTextCatalog.Validate(
    [
        new CompositeTextEntry
        {
            EntryPointId = "runtime-map:RichTextFragments:fixture-score",
            OriginalFormat = "[SCORE]",
            LocalizedFormat = "得分",
        },
    ], []);

    var rejected = false;
    try
    {
        CompositeTextCatalog.Validate(
        [
            new CompositeTextEntry
            {
                EntryPointId = "runtime-map:RichTextFragments:fixture-score",
                OriginalFormat = "[SCORE]",
                LocalizedFormat = "[得分|SCORE]",
            },
        ], []);
    }
    catch (InvalidDataException)
    {
        rejected = true;
    }
    Assert.True(rejected);
}

static CompositeCatalogDocument ReadCompositeCatalog(string path) =>
    System.Text.Json.JsonSerializer.Deserialize<CompositeCatalogDocument>(File.ReadAllText(path))
    ?? throw new InvalidDataException("Composite catalog fixture could not be read.");

static void WriteCompositeCatalog(string path, CompositeCatalogDocument document) =>
    File.WriteAllText(path, System.Text.Json.JsonSerializer.Serialize(document,
        new System.Text.Json.JsonSerializerOptions { WriteIndented = true }));

static void LoadLifecyclePatchReleasesOwnedResources()
{
    using var temp = new TempDirectory();
    var repositoryRoot = FindRepositoryRoot();
    var source = Path.Combine(repositoryRoot, "source", "ElfTools.original.dll");
    var output = Path.Combine(temp.Path, "ElfTools.dll");

    GameLoadResourceLifecyclePatcher.PatchElfTools(source, output);

    using var module = ModuleDefMD.Load(output);
    var type = module.GetTypes().Single(candidate =>
        candidate.FullName == "ElfTools.Graphics.ElfSpriteBatch.IdBatch.IdSpriteBatch");
    var method = type.Methods.Single(candidate =>
        candidate.Name == "Dispose" && candidate.MethodSig?.Params.Count == 1);
    var instructions = method.Body?.Instructions
        ?? throw new InvalidOperationException("Patched IdSpriteBatch.Dispose body is missing.");

    Assert.True(instructions.Any(instruction =>
        instruction.Operand is IField field && field.Name == "indexBuf"));
    Assert.False(instructions.Any(instruction =>
        instruction.Operand is IField field && field.Name == "_defaultEffect"));
    Assert.Equal(1, instructions.Count(instruction =>
        instruction.Operand is IMethod called &&
        called.FullName == "System.Void Microsoft.Xna.Framework.Graphics.GraphicsResource::Dispose()"));
}

static void LoadLifecyclePatchClearsStaleWorldRoots()
{
    using var temp = new TempDirectory();
    var repositoryRoot = FindRepositoryRoot();
    var source = Path.Combine(repositoryRoot, "source", "AtTheGatesGame.original.exe");
    var output = Path.Combine(temp.Path, "At The Gates.exe");

    GameLoadResourceLifecyclePatcher.PatchGame(source, output);

    if (!IsLargeAddressAware(output))
        throw new InvalidOperationException(
            "Patched x86 game executable must be large-address aware.");
    using var sourceModule = ModuleDefMD.Load(source);
    using var module = ModuleDefMD.Load(output);
    if (module.GetAssemblyRefs().Any(reference =>
            reference.Name == "System.Private.CoreLib"))
        throw new InvalidOperationException(
            "The .NET Framework game patch must not reference System.Private.CoreLib.");
    var application = module.GetTypes().Single(candidate =>
        candidate.FullName == "AtTheGatesGame.ns_UIControllers.ATGApplication");
    var method = application.Methods.Single(candidate => candidate.Name == "LoadGame_Step2");
    var instructions = method.Body?.Instructions
        ?? throw new InvalidOperationException("Patched LoadGame_Step2 body is missing.");

    var createIndex = FindCall(instructions, "ATGApplication::CreateWorldScreen()");
    var disposeIndex = FindCall(instructions, "IdSpriteBatch::Dispose(System.Boolean)");
    var clearRootsIndex = FindCall(instructions, "DebugConsole::AtGClearWorldReferences()");
    var loadIndex = FindCall(instructions, "ATGApplication::LoadFromFile(System.String)");
    if (!(createIndex >= 0 && disposeIndex > createIndex &&
          clearRootsIndex > disposeIndex && loadIndex > clearRootsIndex))
        throw new InvalidOperationException(
            $"Unexpected teardown order: create={createIndex}, dispose={disposeIndex}, " +
            $"clear={clearRootsIndex}, load={loadIndex}.");

    var debugConsole = module.GetTypes().Single(candidate =>
        candidate.FullName == "AtTheGatesGame.DebugConsoleNS.DebugConsole");
    var clearRoots = debugConsole.Methods.Single(candidate =>
        candidate.Name == "AtGClearWorldReferences");
    if (!clearRoots.IsPublic || !clearRoots.IsStatic)
        throw new InvalidOperationException(
            $"AtGClearWorldReferences must be public static; attributes={clearRoots.Attributes}.");
    var clearInstructions = clearRoots.Body?.Instructions
        ?? throw new InvalidOperationException("AtGClearWorldReferences body is missing.");
    var sourceApplication = sourceModule.GetTypes().Single(candidate =>
        candidate.FullName == "AtTheGatesGame.ns_UIControllers.ATGApplication");
    var sourceLoadGame = sourceApplication.Methods.Single(candidate =>
        candidate.Name == "LoadGame_Step2");
    var sourceInstructions = sourceLoadGame.Body?.Instructions
        ?? throw new InvalidOperationException("Original LoadGame_Step2 body is missing.");
    foreach (var fieldName in new[] { "WSC", "Human", "MouseoverTile", "SelectedObject" })
    {
        if (!HasNullStaticFieldStoreBetween(
                clearInstructions, fieldName, -1, clearInstructions.Count))
            throw new InvalidOperationException(
                $"AtGClearWorldReferences does not clear DebugConsole.{fieldName}.");
        var originalDirectStores = sourceInstructions.Count(instruction =>
            instruction.OpCode == OpCodes.Stsfld &&
            instruction.Operand is IField field && field.Name == fieldName);
        var patchedDirectStores = instructions.Count(instruction =>
            instruction.OpCode == OpCodes.Stsfld &&
            instruction.Operand is IField field && field.Name == fieldName);
        if (patchedDirectStores != originalDirectStores)
            throw new InvalidOperationException(
                $"LoadGame_Step2 changed direct DebugConsole.{fieldName} stores: " +
                $"original={originalDirectStores}, patched={patchedDirectStores}.");
    }

    var clearBatchIndex = FindCall(instructions, "ATGGAME::set_IdSpriteBatch(");
    if (!(clearBatchIndex > disposeIndex && clearBatchIndex < loadIndex))
        throw new InvalidOperationException(
            $"Unexpected IdSpriteBatch clear order: dispose={disposeIndex}, " +
            $"clearBatch={clearBatchIndex}, load={loadIndex}.");

    var loadWorld = application.Methods.Single(candidate => candidate.Name == "LoadWorld");
    var loadWorldInstructions = loadWorld.Body?.Instructions
        ?? throw new InvalidOperationException("Patched LoadWorld body is missing.");
    var initIndex = FindCall(loadWorldInstructions, "WorldCore::Init_Load_First()");
    var collectIndex = FindCall(loadWorldInstructions, "System.GC::Collect()");
    var loadDataIndex = FindCall(loadWorldInstructions, "WorldCore::LoadData(ElfTools.Serialize.Loader)");
    if (!(initIndex >= 0 && collectIndex > initIndex && loadDataIndex > collectIndex))
        throw new InvalidOperationException(
            $"Unexpected forced collection order: init={initIndex}, collect={collectIndex}, " +
            $"loadData={loadDataIndex}.");
}

static int FindCall(IList<Instruction> instructions, string targetFragment)
{
    for (var index = 0; index < instructions.Count; index++)
    {
        if (instructions[index].Operand is IMethod method &&
            method.FullName.Contains(targetFragment, StringComparison.Ordinal))
            return index;
    }
    return -1;
}

static bool HasNullStaticFieldStoreBetween(
    IList<Instruction> instructions,
    string fieldName,
    int startIndex,
    int endIndex)
{
    for (var index = Math.Max(startIndex + 1, 1); index < Math.Min(endIndex, instructions.Count); index++)
    {
        if (instructions[index].OpCode != OpCodes.Stsfld ||
            instructions[index].Operand is not IField field ||
            field.Name != fieldName)
            continue;
        if (instructions[index - 1].OpCode == OpCodes.Ldnull)
            return true;
    }
    return false;
}

static bool IsLargeAddressAware(string path)
{
    var bytes = File.ReadAllBytes(path);
    var peHeader = BitConverter.ToInt32(bytes, 0x3c);
    var characteristics = BitConverter.ToUInt16(bytes, peHeader + 22);
    return (characteristics & 0x20) != 0;
}

static string FindRepositoryRoot()
{
    var directory = new DirectoryInfo(AppContext.BaseDirectory);
    while (directory is not null)
    {
        if (File.Exists(Path.Combine(directory.FullName, "AtG.Patch.sln")))
            return directory.FullName;
        directory = directory.Parent;
    }
    throw new DirectoryNotFoundException("AtG.Patch.sln was not found above the test output directory.");
}

static class RewriteFixture
{
    public static string Value() => "rewrite-fixture-original";
}

static class CallRedirectFixture
{
    public static string Invoke(string value) => value.Trim();
}

static class CallRedirectTarget
{
    public static string Trim(string value) => value.Trim();
}

static class ReturnRegistrationFixture
{
    public static string Get() => "registered-value";
}

static class ReturnRegistrationTarget
{
    public static string RegisterAndReturn(string value, string name, float size, bool bold) => value;
}

static class GenericCallFixture
{
    public static string Invoke(string value) => Identity<string>(value);
    private static T Identity<T>(T value) => value;
}

static class GenericCallTarget
{
    public static string Pass(string value) => value;
}

sealed class FieldFilterFixture
{
    public string RawText = "before";
    public string Process() => RawText;
}

static class FieldFilterTarget
{
    public static string Filter(string value) => "filtered:" + value;
}

sealed class ReturnFilterFixture
{
    public string Get() => "before";
}

static class ReturnFilterTarget
{
    public static string Filter(string value) => "filtered:" + value;
}

static class CallResultFilterFixture
{
    public static string BuildLabel() => " of " + GetFactionName();

    public static string GetFactionName() => "Eastern Roman Empire";
}

static class CallResultFilterTarget
{
    public static string Filter(string value) => "localized:" + value;
}

sealed class ArgumentFilterFixture
{
    public void RewriteString(string value) => _ = value.Length;

    public void RewriteBuilder(System.Text.StringBuilder value) => _ = value.Length;
}

static class ArgumentFilterTarget
{
    public static string FilterString(string value) => value;

    public static void FilterBuilder(System.Text.StringBuilder value)
    {
    }
}

sealed class MethodEntryFixture
{
    public static void Draw()
    {
    }

    public void LoadContent()
    {
    }
}

static class MethodEntryTarget
{
    public static void BeginFrame()
    {
    }

    public static void PrepareStartupGraphics(object game)
    {
    }
}

static class RuntimeMapConceptFixture
{
    public static readonly string[] Values = ["[Clan|CLAN]", "TURN"];
    public static string Encode(string value) =>
        Convert.ToBase64String(System.Text.Encoding.UTF8.GetBytes(value));
}

static class CompositeCatalogFixture
{
    public static string Concat(string clan) => string.Concat("Clan ", clan);

    public static string Format(string clan) => string.Format("Clan {0}", clan);

    public static string Join(string[] clans) => string.Join(", ", clans);

    public static string Append(string clan)
    {
        var builder = new System.Text.StringBuilder();
        builder.Append("Clan ");
        builder.Append(clan);
        return builder.ToString();
    }
}

static class Assert
{
    public static void True(bool value)
    {
        if (!value) throw new InvalidOperationException("Expected true.");
    }

    public static void False(bool value) => True(!value);

    public static void Equal<T>(T expected, T actual)
    {
        if (!EqualityComparer<T>.Default.Equals(expected, actual))
            throw new InvalidOperationException($"Expected '{expected}', actual '{actual}'.");
    }

    public static void NotEqual<T>(T left, T right)
    {
        if (EqualityComparer<T>.Default.Equals(left, right))
            throw new InvalidOperationException($"Expected values to differ, both were '{left}'.");
    }
}

sealed class TempDirectory : IDisposable
{
    public string Path { get; } = System.IO.Path.Combine(
        System.IO.Path.GetTempPath(), "atg-patch-tests", Guid.NewGuid().ToString("N"));

    public TempDirectory() => Directory.CreateDirectory(Path);

    public string Write(string relativePath, string content)
    {
        var path = System.IO.Path.Combine(Path, relativePath);
        Directory.CreateDirectory(System.IO.Path.GetDirectoryName(path)!);
        File.WriteAllText(path, content);
        return path;
    }

    public void Dispose()
    {
        if (Directory.Exists(Path)) Directory.Delete(Path, recursive: true);
    }
}
