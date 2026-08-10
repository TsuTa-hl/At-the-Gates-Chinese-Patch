using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;
using System.Xml.Linq;
using dnlib.DotNet;
using dnlib.DotNet.Emit;

namespace AtG.ManagedRewrite;

public sealed class CompositeCatalogDocument
{
    public int SchemaVersion { get; set; } = 7;
    public string GeneratedAtUtc { get; set; } = "";
    public string RepositoryRoot { get; set; } = "";
    public List<CompositeTextEntry> Entries { get; set; } = [];
    public List<CompositeLocalizationRule> Rules { get; set; } = [];
}

public sealed class CompositeTextEntry
{
    public string EntryPointId { get; set; } = "";
    public CompositeTextSource Source { get; set; } = new();
    public string OriginalFormat { get; set; } = "";
    public string? LocalizedFormat { get; set; }
    public string Classification { get; set; } = "Unreviewed";
    public string Status { get; set; } = "Unreviewed";
    public string? RuleId { get; set; }
    public string AuditStatus { get; set; } = "Unreviewed";
    public string RuleScope { get; set; } = "None";
    public string Confidence { get; set; } = "Partial";
    public List<CompositeTextPart> Parts { get; set; } = [];
    public List<string> StructuralFlags { get; set; } = [];
    public string? Notes { get; set; }
    public bool Stale { get; set; }
}

public sealed class CompositeTextSource
{
    public string Kind { get; set; } = "";
    public string RelativePath { get; set; } = "";
    public string? TypeFullName { get; set; }
    public string? MethodName { get; set; }
    public string? MethodToken { get; set; }
    public int? ILOffset { get; set; }
    public string? XPath { get; set; }
    public string? CallKind { get; set; }
}

public sealed class CompositeTextPart
{
    public int Position { get; set; }
    public string Kind { get; set; } = "";
    public string Value { get; set; } = "";
    public CompositeKnownTextReference? KnownTextReference { get; set; }
    public string? KnownTextReferenceExclusionReason { get; set; }
}

/// <summary>
/// Stable source identity for a literal that participates in a composite display.
/// This deliberately does not store a SQLite occurrence ID: catalog IDs are local and
/// replaceable, while the source file plus a source locator remains reproducible.
/// </summary>
public sealed class CompositeKnownTextReference
{
    public string SourceFile { get; set; } = "";
    public string Original { get; set; } = "";
    public string? MethodToken { get; set; }
    public int? ILOffset { get; set; }
    public string? XPath { get; set; }
    public string? TextKey { get; set; }
    public string? ConfigId { get; set; }
    public string? ConfigXPath { get; set; }
    public int? ConfigIndex { get; set; }
    public string? RuntimeMapSection { get; set; }
    public string? RuntimeMapOriginal { get; set; }
    public string? RuntimeMapConceptKey { get; set; }
}

public sealed class CompositeLocalizationRule
{
    public string RuleId { get; set; } = "";
    public string Kind { get; set; } = "";
    public string Status { get; set; } = "Active";
    public string EntryPointId { get; set; } = "";
    public string Description { get; set; } = "";
    public string Source { get; set; } = "";
}

public sealed class CompositeEntrySpecificRuleDocument
{
    public int SchemaVersion { get; set; } = 1;
    public List<CompositeEntrySpecificRule> Entries { get; set; } = [];
}

public sealed class CompositeEntrySpecificRule
{
    public string EntryPointId { get; set; } = "";
    public string LocalizedFormat { get; set; } = "";
    public string? Notes { get; set; }
}

public sealed record CompositeCatalogResult(
    int EntryCount,
    int RuleCount,
    int ManagedEntryCount,
    int XmlEntryCount,
    int RuntimeMapEntryCount,
    string RulesPath);

public static class CompositeTextCatalog
{
    private const string RuntimeDisplayMapSourceFile = "translations/runtime-display-strings.json";
    private static readonly Regex RichTextLink = new(
        @"\[[^\]|]+\|([A-Z][A-Z0-9-]*)\]", RegexOptions.CultureInvariant);
    // A few legacy source strings contain a split link such as
    // `[Researching]|STUDY]`. Treat the trailing key as the intended concept
    // link for structural validation while allowing the patch to repair the
    // malformed display markup.
    private static readonly Regex MalformedRichTextLink = new(
        @"\[[^\]]+\]\|([A-Z][A-Z0-9-]*)\]", RegexOptions.CultureInvariant);
    private static readonly Regex Placeholder = new(
        @"\{(?:arg:)?\d+\}", RegexOptions.CultureInvariant);
    private static readonly Regex BracketToken = new(
        @"\[[^\]]+\]", RegexOptions.CultureInvariant);
    private static readonly Regex BareRuntimeDisplayToken = new(
        @"^\[[A-Z][A-Z0-9-]*\]$", RegexOptions.CultureInvariant);
    private static readonly Regex AsciiWord = new(
        @"[A-Za-z]{2,}", RegexOptions.CultureInvariant);
    private static readonly Regex MachineToken = new(
        @"^\s*[A-Za-z0-9_.:-]+\s*$", RegexOptions.CultureInvariant);
    private static readonly IReadOnlyDictionary<string, string> ConceptKeyAliases =
        new Dictionary<string, string>(StringComparer.Ordinal)
        {
            // The game source uses the legacy plural key in one Clan-list
            // tooltip, while the registered concept target is UPGRADE.
            ["UPGRADES"] = "UPGRADE",
        };
    // These are source literals shared by every managed composite that references
    // them. They deliberately live at the final-display boundary: the source
    // program continues to use identifiers, paths, hotkeys, and tags unchanged.
    // A missing prose literal is an audit failure, not a legacy safety exclusion.
    private static readonly IReadOnlyDictionary<string, string> CompositeLiteralTranslations =
        new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["     in Active [Professions|PROFESSION] leave the [SETTLEMENT] and appear on the map (as opposed to [Settled|SETTLED] Professions). Some Clans have Traits that make them prefer or dislike such Professions."] =
                " 主动[Professions|PROFESSION]会离开[SETTLEMENT]并出现在地图上（与[Settled|SETTLED]职业相对）。有些氏族特质会使其偏好或厌恶这类职业。",
            ["     in Settled [Professions|PROFESSION] remain inside the [SETTLEMENT] (as opposed to [Active|ACTIVE] Professions). Some Clans have Traits that make them prefer or dislike such Professions."] =
                " 定居[Professions|PROFESSION]会留在[SETTLEMENT]内（与[Active|ACTIVE]职业相对）。有些氏族特质会使其偏好或厌恶这类职业。",
            ["     in some [Active|ACTIVE] [Civilian|CIVILIAN] [Professions|PROFESSION] like [FARMER] and [MINER] can Construct [Structures|STRUCTURE] to [Harvest|HARVEST] [Resources|RESOURCE] from [Deposits|DEPOSIT] or [Dense Forests|FOREST]. This requires either [TIMBER] or [STONE-BLOCKS], and is generally not something you'll start doing until a year or two into the game."] =
                " 某些主动的[Civilian|CIVILIAN][Professions|PROFESSION]，如[FARMER]和[MINER]，可以建造[Structures|STRUCTURE]，从[Deposits|DEPOSIT]或[Dense Forests|FOREST]中[Harvest|HARVEST][Resources|RESOURCE]。这需要[TIMBER]或[STONE-BLOCKS]，通常要到游戏一两年后才会开始进行。",
            ["     to [Identify|UNIDENTIFIED] "] = " 用于[Identify|UNIDENTIFIED] ",
            ["    MORE  LINES  HIDDEN   ]"] = "    已隐藏更多行   ]",
            ["   [PARCHMENT]."] = "   [PARCHMENT]。",
            ["   [Turns|TURN] remaining)."] = "   剩余[Turns|TURN]）。",
            ["   and remove all [Crimes|CRIME] from this [Clan|CLAN] (can only be performed in the [SETTLEMENT] when you have an [INSTRUCTOR])."] =
                "，并清除该[Clan|CLAN]的所有[Crimes|CRIME]（仅可在拥有[INSTRUCTOR]的[SETTLEMENT]中执行）。",
            ["   and remove this [Trait|CLAN-TRAIT] from this [Clan|CLAN] (can only be performed in the [SETTLEMENT] when you have an [INSTRUCTOR])."] =
                "，并移除该[Clan|CLAN]的此项[Trait|CLAN-TRAIT]（仅可在拥有[INSTRUCTOR]的[SETTLEMENT]中执行）。",
            ["   as a playable [Faction|FACTION]! You will be able to choose them to play from the main menu in future games."] =
                "，成为可游玩的[Faction|FACTION]！今后的游戏可从主菜单选择该派系。",
            ["   can be [Trained|TRAIN] in."] = " 可在此接受[Trained|TRAIN]。",
            ["   icon, and are exclusively found in the [HONOR] and [DISCOVERY] [Disciplines|DISCIPLINE]."] =
                "图标，且仅见于[HONOR]和[DISCOVERY][Disciplines|DISCIPLINE]。",
            ["  % bonus to [Combat Power|POWER]"] = " 对[Combat Power|POWER]加成 %",
            ["  % bonus to [Resource Production|PRODUCE]"] = " 对[Resource Production|PRODUCE]加成 %",
            ["  % the normal rate after a [Deposit|DEPOSIT] has [Degraded|DEPLETE] once, and then becomes permanently exhausted and shuts down after Degrading a second time."] =
                "首次[Degraded|DEPLETE]后按正常速率的 % 产出；第二次枯竭后将永久耗尽并停工。",
            ["  (or another similar [Resource|RESOURCE])"] = "（或其他类似的[Resource|RESOURCE]）",
            ["  ] contains only one Tag Display Text value. When one is defined both must be in order to do plural testing."] =
                " ]仅包含一个标签显示文本值。进行复数测试时，若定义其中一个则必须同时定义两个。",
            ["  ] has been captured and is now 'Occupied'."] = " ]已被占领，现在处于“已占领”状态。",
            ["  ] is not a valid tag:"] = " ]不是有效标签：",
            ["  ] is setting HorizontalAlign to its existing value, which has no effect and is probably unintentional."] =
                " ]正将 HorizontalAlign 设为现有值；这不会产生效果，可能并非有意如此。",
            ["  ] is setting ShrinkToFitText to its existing value, which has no effect and is probably unintentional."] =
                " ]正将 ShrinkToFitText 设为现有值；这不会产生效果，可能并非有意如此。",
            ["  ] on this  "] = " ]位于此",
            ["  ] signed numeric value delimiter '+' can only immediately follow the '[' character which starts a new tag."] =
                " ]带符号数值分隔符“+”只能紧跟在开始新标签的“[”之后。",
            ["  ] to  "] = " ]到",
            ["  ] to mirror."] = " ]以镜像显示。",
            ["  ] when calculating CalcNumTooltipsAboveUs()"] = " ]，计算 CalcNumTooltipsAboveUs() 时",
            ["  ] with every  "] = " ]，每个",
            ["  ], but it lacks a River which can flood!"] = " ]，但它缺少可泛滥的河流！",
            ["  ]. Doing so"] = " ]。这样做",
            ["  ]'s XML is expecting CONFIG values but the internal list is undefined."] = " ]的 XML 需要 CONFIG 值，但内部列表未定义。",
            ["  ]'s XML is expecting NUMBER values but the internal list is undefined."] = " ]的 XML 需要 NUMBER 值，但内部列表未定义。",
            ["  ]'s XML is expecting TEXT values but the internal list is undefined."] = " ]的 XML 需要 TEXT 值，但内部列表未定义。",
            ["  can ONLY be healed by using the 'Heal' Command while a [Clan|CLAN] is on the same [Tile|TILE] as your [SETTLEMENT]"] =
                "只能在[Clan|CLAN]与[SETTLEMENT]处于同一[Tile|TILE]时，使用“Heal”命令治疗。",
            ["  can provide you with [Resources|RESOURCE] useful in [Training|TRAIN], [Construction|CONSTRUCT], and trade. You can [Harvest|HARVEST] them through [Foraging|FORAGE] or by Constructing [Structures|STRUCTURE] on them."] =
                "可提供用于[Training|TRAIN]、[Construction|CONSTRUCT]和贸易的[Resources|RESOURCE]。可通过[Foraging|FORAGE]或在其上建造[Structures|STRUCTURE]来[Harvest|HARVEST]。",
            ["  from [SETTLEMENT:NO-ICON]"] = "，来自[SETTLEMENT:NO-ICON]",
            ["  needed to [Identify|UNIDENTIFIED] "] = "，需要[Identify|UNIDENTIFIED] ",
            ["  's previous [Desire|DESIRE] or [Feud|FEUD] has faded away."] = "此前的[Desire|DESIRE]或[Feud|FEUD]已消退。",
            ["  suffered after [Retreating|RETREAT]"] = "在[Retreating|RETREAT]后遭受了",
            ["  when fighting [Bandits|BANDIT]"] = "与[Bandits|BANDIT]作战时",
            ["  when fighting [Romans|ROME]"] = "与[Romans|ROME]作战时",
            [" \n\n[COLOR:BAD-RED]This Desire has been granted![/COLOR]"] = "\n\n[COLOR:BAD-RED]该愿望已获满足！[/COLOR]",
            [" % from number of [Families|FAMILY] in [Clan|CLAN]"] = " %，取决于[Clan|CLAN]中的[Families|FAMILY]数量",
            [" ... Panels[COLLAPSED] cannot contain the Panels[EXPANDED]."] = "……Panels[COLLAPSED]不能包含 Panels[EXPANDED]。",
            [" ... Panels[COLLAPSED] cannot contain the ToggleButton[EXPANDED]."] = "……Panels[COLLAPSED]不能包含 ToggleButton[EXPANDED]。",
            [" ... Panels[EXPANDED] and Panels[COLLAPSED] cannot be the same object."] = "……Panels[EXPANDED]与 Panels[COLLAPSED]不能是同一对象。",
            [" ... Panels[EXPANDED] and Panels[COLLAPSED] cannot contain the same object."] = "……Panels[EXPANDED]与 Panels[COLLAPSED]不能包含同一对象。",
            [" ... Panels[EXPANDED] cannot contain the Panels[COLLAPSED]."] = "……Panels[EXPANDED]不能包含 Panels[COLLAPSED]。",
            [" ... Panels[EXPANDED] cannot contain the ToggleButton[COLLAPSED]."] = "……Panels[EXPANDED]不能包含 ToggleButton[COLLAPSED]。",
            [" ... The HEIGHT of a horizontally-aligned Panels[EXPANDED] and its Panels[COLLAPSED] must match."] =
                "……横向对齐的 Panels[EXPANDED]与其 Panels[COLLAPSED]高度必须一致。",
            [" ... The WIDTH of a vertically-aligned Panels[EXPANDED] and its Panels[COLLAPSED] must match."] =
                "……纵向对齐的 Panels[EXPANDED]与其 Panels[COLLAPSED]宽度必须一致。",
            [" ... ToggleButton[COLLAPSED] and ToggleButton[EXPANDED] cannot be the same object."] = "……ToggleButton[COLLAPSED]与 ToggleButton[EXPANDED]不能是同一对象。",
            [" [  ] is not a valid edge."] = "[  ]不是有效边。",
            [" allows it to [Move|MOVE-POINT] around the map like an   ."] = "使其能像 一样在地图上[Move|MOVE-POINT]。",
            [" Beaches with only 2 edges must always have a [UsagePercentWhenValid] of 100."] =
                "仅有两条边的海滩必须始终具有 100 的[UsagePercentWhenValid]。",
            [" Clicked"] = "已点击",
            [" Disabled"] = "已禁用",
            [" en route to joining you! You can harvest it by having a [Clan|CLAN]    from or [Construct|CONSTRUCT] a [Structure|STRUCTURE] on it."] =
                "正在前来加入你！可让[Clan|CLAN] 从中采集，或在其上[Construct|CONSTRUCT][Structure|STRUCTURE]。",
            [" MousedOver"] = "鼠标悬停",
            [" Normal"] = "普通",
            [" Walk"] = "步行",
            [" XML contains duplicate entry for [   ]."] = "XML 中包含重复条目：[   ]。",
            ["! You can [Harvest|HARVEST] it by having a [Clan|CLAN]    from or [Construct|CONSTRUCT] a [Structure|STRUCTURE] on it."] =
                "！可让[Clan|CLAN] 从中[Harvest|HARVEST]，或在其上[Construct|CONSTRUCT][Structure|STRUCTURE]。",
            ["[Clan|CLAN] has a [Suppy|SUPPLY] deficit of   ."] = "[Clan|CLAN]的[Suppy|SUPPLY]短缺 。",
            ["[Clan|CLAN] has suffered    [Damage|DAMAGE] due to combat or lack of [Supply|SUPPLY]."] =
                "[Clan|CLAN]因战斗或缺少[Supply|SUPPLY]而受到 [Damage|DAMAGE]。",
            ["[HOTKEY:Comma] Cycles BACKWARDS through idle   ."] = "[HOTKEY:Comma]向后切换空闲的 。",
            ["[HOTKEY:Ctrl-F] - Forage Until Out of  "] = "[HOTKEY:Ctrl-F] - 持续觅食，直到耗尽",
            ["[HOTKEY:Ctrl-I] - Identify Until Out of  "] = "[HOTKEY:Ctrl-I] - 持续鉴定，直到耗尽",
            ["[HOTKEY:Period] Cycles through idle   ."] = "[HOTKEY:Period]切换空闲的 。",
            ["ATGUnit.HasTrait() ... Trait [  ] does not exist."] = "ATGUnit.HasTrait() ……特质 [  ]不存在。",
            ["BaseObject.GetProperty() call for [  ] failed to find a valid match."] = "BaseObject.GetProperty() 调用未能为 [  ]找到有效匹配。",
            ["Found a [null] HarvestData on tile  "] = "在地块 上发现了 [null] HarvestData。",
            ["Highlighted tiles containing Deposit Type [  ]"] = "已高亮显示含有资源点类型 [  ]的地块",
            ["Highlighted tiles containing Food, except for [  ]"] = "已高亮显示含有食物但不包括 [  ]的地块",
            ["Highlighted tiles containing Zone Trait [  ]"] = "已高亮显示含有区域特质 [  ]的地块",
            ["Highlighted tiles where Zone Trait [  ] could have been placed."] = "已高亮显示可放置区域特质 [  ]的地块。",
            ["Invalid map size: [  ]"] = "无效地图尺寸：[  ]",
            ["No loading logic for event type [  ]"] = "事件类型 [  ]没有加载逻辑",
            ["No matching Object Property ID for [  ]"] = "没有与 [  ]匹配的对象属性 ID",
            ["Pillaging takes 1 [Turn|TURN] and provides a lump sum of [Resources|RESOURCE] as plunder, but damages the target [Structure|STRUCTURE] until it's Repaired. Pillaging a [Farm|FARM] or [SETTLEMENT] also provides free   ."] =
                "劫掠耗时 1 [Turn|TURN]，可获得一笔[Resources|RESOURCE]战利品，但会损坏目标[Structure|STRUCTURE]，直至修复。劫掠[Farm|FARM]或[SETTLEMENT]还会提供免费的 。",
            ["Unable to find Stance enum match for [  ]."] = "找不到与 [  ]匹配的姿态枚举。",
            ["Unable to open or locate  [ Settings.xml ]  from the expected location:\n\n "] = "无法在预期位置打开或找到 [ Settings.xml ]：\n\n",
            ["Unexpected XML block in Climate data for [  ]"] = "[  ]的气候数据中出现意外 XML 块",
            ["Was unable to find a month associated with index [  ]."] = "找不到与索引 [  ]关联的月份。",
            ["Was unable to find a month associated with name [  ]."] = "找不到与名称 [  ]关联的月份。",
            ["Was unable to find the Priority for [  ]. Did you misspell something?"] = "找不到 [  ]的优先级。是否拼写有误？",
            ["Was unable to find the Situation for [  ]. Did you misspell something?"] = "找不到 [  ]的情境。是否拼写有误？",
            ["Was unable to find the Priority for ["] = "找不到 [",
            ["Was unable to find the Situation for ["] = "找不到 [",
            ["]. Did you misspell something?"] = "]。是否拼写有误？",
            ["No loading logic for event type ["] = "事件类型[",
            ["XML contains duplicate entry for ["] = "XML 中包含重复条目：[",
            ["Unable to find Stance enum match for ["] = "找不到与[",
            ["] is not a valid edge."] = "]不是有效边。",
            ["Unexpected XML block in Climate data for ["] = "[",
            ["XML text error with ["] = "[",
            ["] ... Text Entry cannot start with a space. If trying to indent use tabs instead."] =
                "]……文本条目不能以空格开头。若需缩进，请改用制表符。",
            ["] ... Text Entry cannot end with a space. If trying to indent use tabs instead."] =
                "]……文本条目不能以空格结尾。若需缩进，请改用制表符。",
            ["XML text error ... Multiple copies of TextKey ["] = "XML 文本错误……TextKey[",
            ["] ... TextKey must start with [TEXT.]."] = " ]……TextKey 必须以 [TEXT.]开头。",
            ["] ... TextKey cannot contain spaces."] = "]……TextKey 不能包含空格。",
            ["] ... TextKey must contain at least two [.] periods surrounding a brief descriptor of the text's context (e.g. MainMenu, Terrain)."] =
                "]……TextKey 至少须包含两个 [.]，以包围描述文本上下文的简短说明（例如 MainMenu、Terrain）。",
            ["Was unable to find a month associated with name ["] = "找不到与名称[",
            ["Was unable to find a month associated with index ["] = "找不到与索引[",
            ["No matching Object Property ID for ["] = "没有与[",
            ["Invalid map size: ["] = "无效地图尺寸：[",
            ["Highlighted tiles containing Food, except for ["] = "已高亮显示含有食物但不包括[",
            ["Highlighted tiles containing Deposit Type ["] = "已高亮显示含有资源点类型[",
            ["Highlighted tiles where Zone Trait ["] = "已高亮显示可放置区域特质[",
            ["] could have been placed."] = "]的地块。",
            ["Highlighted tiles containing Zone Trait ["] = "已高亮显示含有区域特质[",
            ["BaseObject.GetProperty() call for ["] = "BaseObject.GetProperty() 调用未能为[",
            ["] failed to find a valid match."] = "]找到有效匹配。",
            ["ATGUnit.HasTrait() ... Trait ["] = "ATGUnit.HasTrait() ……特质[",
            ["] does not exist."] = "]不存在。",
            ["XML text error ... Multiple copies of TextKey [  ]."] = "XML 文本错误……TextKey [  ]存在多个副本。",
            ["XML text error with [  ] ... Text Entry cannot end with a space. If trying to indent use tabs instead."] =
                "[  ]发生 XML 文本错误……文本条目不能以空格结尾。若需缩进，请改用制表符。",
            ["XML text error with [  ] ... Text Entry cannot start with a space. If trying to indent use tabs instead."] =
                "[  ]发生 XML 文本错误……文本条目不能以空格开头。若需缩进，请改用制表符。",
            ["XML text error with [  ] ... TextKey cannot contain spaces."] = "[  ]发生 XML 文本错误……TextKey 不能包含空格。",
            ["XML text error with [  ] ... TextKey must contain at least two [.] periods surrounding a brief descriptor of the text's context (e.g. MainMenu, Terrain)."] =
                "[  ]发生 XML 文本错误……TextKey 至少须包含两个 [.]，以包围描述文本上下文的简短说明（例如 MainMenu、Terrain）。",
            ["XML text error with [  ] ... TextKey must start with [TEXT.]."] = "[  ]发生 XML 文本错误……TextKey 必须以 [TEXT.]开头。",
        };
    private static readonly Regex PipeDelimitedAlias = new(
        @"^\|[^|]+\|[^|]+\|$", RegexOptions.CultureInvariant);
    private static readonly HashSet<string> NonConceptDisplayKeys = new(StringComparer.Ordinal)
    {
        "RESPECT",
        "RELATIONS",
    };
    private static readonly HashSet<string> RuntimeMapSections = new(StringComparer.Ordinal)
    {
        "Exact",
        "PlainText",
        "PlainTextFragments",
        "RichTextFragments",
        "Templates",
        "ConceptDisplay",
    };
    private static readonly IReadOnlyDictionary<string, string> LegacyBareConceptAliases =
        new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["Ennoble"] = "NOBLE",
        };

    public static CompositeCatalogResult Build(string repositoryRoot, string? rulesPath = null)
    {
        var root = Path.GetFullPath(repositoryRoot);
        rulesPath ??= Path.Combine(root, "translations", "composite-text-rules.json");
        rulesPath = Path.GetFullPath(rulesPath);

        var existing = LoadExisting(rulesPath);
        var entries = new List<CompositeTextEntry>();
        entries.AddRange(ScanManagedAssemblies(root));
        entries.AddRange(ScanXmlFiles(root));
        entries.AddRange(ReadRuntimeMapEntries(root));
        entries.AddRange(ReadManagedRewriteMapEntries(root));

        var merged = Merge(entries, existing);
        ApplyEntrySpecificRules(merged, Path.Combine(root, "translations",
            "composite-entry-specific-rules.json"));
        ApplyStaticAudit(merged, ReadKnownSafetyRejections(root));
        var rules = BuildRules(merged, existing?.Rules);
        Validate(merged, rules);

        var document = new CompositeCatalogDocument
        {
            // This catalog is a committed build input. Keeping its generation
            // timestamp stable prevents an otherwise identical verification
            // build from dirtying main and blocking release publication.
            GeneratedAtUtc = existing?.GeneratedAtUtc ?? string.Empty,
            RepositoryRoot = ".",
            Entries = merged.OrderBy(entry => entry.EntryPointId, StringComparer.Ordinal).ToList(),
            Rules = rules.OrderBy(rule => rule.RuleId, StringComparer.Ordinal).ToList(),
        };
        Directory.CreateDirectory(Path.GetDirectoryName(rulesPath)!);
        File.WriteAllText(rulesPath, JsonSerializer.Serialize(document, JsonOptions));

        return new CompositeCatalogResult(
            document.Entries.Count,
            document.Rules.Count,
            document.Entries.Count(entry => entry.Source.Kind == "Managed"),
            document.Entries.Count(entry => entry.Source.Kind == "Xml"),
            document.Entries.Count(entry => entry.Source.Kind == "RuntimeMap"),
            rulesPath);
    }

    public static IReadOnlyList<CompositeTextEntry> ScanManagedAssemblies(string repositoryRoot)
    {
        var root = Path.GetFullPath(repositoryRoot);
        var source = Path.Combine(root, "source");
        var assemblies = new[]
        {
            "AtTheGatesUI.original.dll",
            "AtTheGatesCommon.original.dll",
            "AtTheGatesGame.original.exe",
            "ElfTools.original.dll",
        }.Select(name => Path.Combine(source, name))
            .Where(File.Exists)
            .ToArray();
        var result = new List<CompositeTextEntry>();
        foreach (var assemblyPath in assemblies)
        {
            using var module = ModuleDefMD.Load(assemblyPath);
            var relative = RelativePath(root, assemblyPath);
            foreach (var type in module.GetTypes())
            foreach (var method in type.Methods)
            {
                var instructions = method.Body?.Instructions;
                if (instructions is null) continue;
                for (var index = 0; index < instructions.Count; index++)
                {
                    var instruction = instructions[index];
                    if ((instruction.OpCode != OpCodes.Call && instruction.OpCode != OpCodes.Callvirt) ||
                        instruction.Operand is not IMethod target ||
                        !TryGetCompositeCallKind(target, out var callKind))
                        continue;

                    var token = method.MDToken.Raw.ToString("X8");
                    var methodToken = "0x" + token;
                    var parts = ExtractParts(instructions, index, target, callKind, relative, methodToken);
                    var original = BuildOriginalFormat(parts, callKind);
                    var entryId = $"managed:{relative}:{token}:IL_{instruction.Offset:X4}";
                    result.Add(NewEntry(entryId, new CompositeTextSource
                    {
                        Kind = "Managed",
                        RelativePath = relative,
                        TypeFullName = type.FullName,
                        MethodName = method.Name,
                        MethodToken = methodToken,
                        ILOffset = checked((int)instruction.Offset),
                        CallKind = callKind,
                    }, original, parts, Classify(original, callKind),
                        EstimateConfidence(parts, callKind)));
                }
            }
        }
        return result;
    }

    public static IReadOnlyList<CompositeTextEntry> ScanXmlFiles(string repositoryRoot)
    {
        var root = Path.GetFullPath(repositoryRoot);
        var sourceRoot = Path.Combine(root, "source");
        if (!Directory.Exists(sourceRoot)) return [];
        var englishSourcePath = Path.Combine(sourceRoot, "English.original.xml");
        var englishPatchPath = GetPatchXmlPath(root, englishSourcePath);
        var englishSourceText = File.Exists(englishSourcePath)
            ? ReadTextKeyValues(englishSourcePath)
            : new Dictionary<string, string>(StringComparer.Ordinal);
        var englishPatchText = File.Exists(englishPatchPath)
            ? ReadTextKeyValues(englishPatchPath)
            : new Dictionary<string, string>(StringComparer.Ordinal);
        var result = new List<CompositeTextEntry>();
        foreach (var sourcePath in Directory.EnumerateFiles(sourceRoot, "*.original.xml",
                     SearchOption.AllDirectories).OrderBy(path => path, StringComparer.OrdinalIgnoreCase))
        {
            var relative = RelativePath(root, sourcePath);
            var patchPath = GetPatchXmlPath(root, sourcePath);
            var patchValues = File.Exists(patchPath)
                ? ReadXmlValues(patchPath).ToDictionary(value => value.XPath, StringComparer.Ordinal)
                : new Dictionary<string, XmlValue>(StringComparer.Ordinal);
            foreach (var value in ReadXmlValues(sourcePath))
            {
                if (!LooksComposite(value.Value)) continue;
                var entryId = "xml:" + relative + ":" + ShortHash(value.XPath);
                var parts = new List<CompositeTextPart>
                {
                    new()
                    {
                        Position = 0,
                        Kind = "Literal",
                        Value = value.Value,
                        KnownTextReference = NewXmlKnownTextReference(relative, value),
                    },
                };
                var entry = NewEntry(entryId, new CompositeTextSource
                {
                    Kind = "Xml",
                    RelativePath = relative,
                    XPath = value.XPath,
                    CallKind = "XmlTemplate",
                }, value.Value, parts, Classify(value.Value, "XmlTemplate"), "Exact");
                if (patchValues.TryGetValue(value.XPath, out var localized) &&
                    !StringComparer.Ordinal.Equals(value.Value, localized.Value))
                {
                    entry.LocalizedFormat = localized.Value;
                    entry.Status = "ExistingRule";
                    entry.RuleId = "xml-existing-translation";
                    entry.Notes = "Generated from the matching patch XML node.";
                }
                else if (IsTextKeyReference(value.Value) &&
                         englishPatchText.TryGetValue(value.Value, out var textKeyTarget))
                {
                    var sourceTextFound = englishSourceText.TryGetValue(value.Value,
                        out var sourceTextTarget);
                    if (!sourceTextFound || !StringComparer.Ordinal.Equals(sourceTextTarget,
                            textKeyTarget))
                    {
                        // The XML node contains the runtime key, not the displayed text. Keep
                        // the key intact and record the independently verified patch target;
                        // substituting the target here would compare its markup against a key.
                        entry.LocalizedFormat = value.Value;
                        entry.Status = "ExistingRule";
                        entry.RuleId = "xml-text-key-translation";
                        entry.Notes = "The TEXT.* reference resolves to the localized English.xml entry in the patch.";
                    }
                    else if (IsLocalizationNeutralTextKeyTarget(textKeyTarget))
                    {
                        entry.LocalizedFormat = value.Value;
                        entry.Status = "ExistingRule";
                        entry.RuleId = "xml-text-key-structural";
                        entry.Notes = "The TEXT.* reference resolves to a numeric or placeholder-only English.xml entry; no Chinese prose is present to translate.";
                    }
                    else
                    {
                        entry.Notes = "The TEXT.* reference resolves to an unchanged English.xml value and requires localization.";
                    }
                }
                else if (!string.IsNullOrWhiteSpace(value.TextKey) &&
                         IsLocalizationNeutralTextKeyTarget(value.Value))
                {
                    entry.LocalizedFormat = value.Value;
                    entry.Status = "ExistingRule";
                    entry.RuleId = "xml-text-key-structural";
                    entry.Notes = "The English.xml text-key value contains only runtime placeholders; no Chinese prose is present to translate.";
                }
                result.Add(entry);
            }
        }
        return result;
    }

    public static void Validate(IEnumerable<CompositeTextEntry> entries,
        IEnumerable<CompositeLocalizationRule> rules)
    {
        var entryList = entries.ToList();
        var duplicate = entryList.GroupBy(entry => entry.EntryPointId, StringComparer.Ordinal)
            .FirstOrDefault(group => group.Count() > 1);
        if (duplicate is not null)
            throw new InvalidDataException($"Duplicate composite entry point '{duplicate.Key}'.");
        var ruleIds = new HashSet<string>(rules.Select(rule => rule.RuleId), StringComparer.Ordinal);
        var errors = new List<string>();
        foreach (var entry in entryList)
        {
            if (!string.IsNullOrWhiteSpace(entry.RuleId) && !ruleIds.Contains(entry.RuleId))
            {
                errors.Add($"Composite entry '{entry.EntryPointId}' references unknown RuleId '{entry.RuleId}'.");
                continue;
            }
            if (entry.LocalizedFormat is not null)
            {
                try
                {
                    ValidateStructure(entry.OriginalFormat, entry.LocalizedFormat, entry.EntryPointId);
                }
                catch (InvalidDataException exception)
                {
                    errors.Add(exception.Message);
                }
            }
            foreach (var part in entry.Parts)
            {
                var reference = part.KnownTextReference;
                var exclusionReason = part.KnownTextReferenceExclusionReason;
                if (reference is null)
                {
                    if (StringComparer.Ordinal.Equals(part.Kind, "Literal") &&
                        string.IsNullOrWhiteSpace(exclusionReason))
                    {
                        errors.Add($"Composite entry '{entry.EntryPointId}' has a literal part without a KnownText reference or explicit exclusion.");
                    }
                    continue;
                }
                if (!StringComparer.Ordinal.Equals(part.Kind, "Literal"))
                {
                    errors.Add($"Composite entry '{entry.EntryPointId}' gives a non-literal part a KnownTextReference.");
                    continue;
                }
                if (!string.IsNullOrWhiteSpace(exclusionReason))
                {
                    errors.Add($"Composite entry '{entry.EntryPointId}' gives part {part.Position} both a KnownTextReference and an exclusion.");
                    continue;
                }
                if (!StringComparer.Ordinal.Equals(reference.Original, part.Value))
                {
                    errors.Add($"Composite entry '{entry.EntryPointId}' has a KnownTextReference whose original differs from part {part.Position}.");
                    continue;
                }
                var hasManagedLocator = !string.IsNullOrWhiteSpace(reference.MethodToken) ||
                    reference.ILOffset is not null;
                var hasXmlLocator = !string.IsNullOrWhiteSpace(reference.XPath);
                var hasTextKey = !string.IsNullOrWhiteSpace(reference.TextKey);
                var hasConfigLocator = !string.IsNullOrWhiteSpace(reference.ConfigId) ||
                    !string.IsNullOrWhiteSpace(reference.ConfigXPath) || reference.ConfigIndex is not null;
                var hasRuntimeMapLocator = !string.IsNullOrWhiteSpace(reference.RuntimeMapSection) ||
                    !string.IsNullOrWhiteSpace(reference.RuntimeMapOriginal) ||
                    !string.IsNullOrWhiteSpace(reference.RuntimeMapConceptKey);
                var hasValidRuntimeMapSource = StringComparer.Ordinal.Equals(
                    reference.SourceFile.Replace('\\', '/'), RuntimeDisplayMapSourceFile);
                var runtimeMapIsConceptDisplay = StringComparer.Ordinal.Equals(
                    reference.RuntimeMapSection, "ConceptDisplay");
                if (string.IsNullOrWhiteSpace(reference.SourceFile) ||
                    (hasManagedLocator ? 1 : 0) + (hasXmlLocator ? 1 : 0) +
                    (hasTextKey ? 1 : 0) + (hasConfigLocator ? 1 : 0) +
                    (hasRuntimeMapLocator ? 1 : 0) != 1 ||
                    hasManagedLocator && (string.IsNullOrWhiteSpace(reference.MethodToken) || reference.ILOffset is null) ||
                    hasTextKey && !IsTextKeyReference(reference.TextKey!) ||
                    hasConfigLocator && (string.IsNullOrWhiteSpace(reference.ConfigId) ||
                        string.IsNullOrWhiteSpace(reference.ConfigXPath)) ||
                    hasRuntimeMapLocator && (!hasValidRuntimeMapSource ||
                        string.IsNullOrWhiteSpace(reference.RuntimeMapSection) ||
                        string.IsNullOrWhiteSpace(reference.RuntimeMapOriginal) ||
                        !RuntimeMapSections.Contains(reference.RuntimeMapSection) ||
                        runtimeMapIsConceptDisplay &&
                            string.IsNullOrWhiteSpace(reference.RuntimeMapConceptKey) ||
                        !runtimeMapIsConceptDisplay &&
                            !string.IsNullOrWhiteSpace(reference.RuntimeMapConceptKey)))
                {
                    errors.Add($"Composite entry '{entry.EntryPointId}' has an incomplete KnownTextReference for part {part.Position}.");
                }
            }
        }
        if (errors.Count > 0)
        {
            var limit = 40;
            var message = string.Join(Environment.NewLine, errors.Take(limit));
            if (errors.Count > limit)
                message += Environment.NewLine + $"... and {errors.Count - limit} more composite validation errors.";
            throw new InvalidDataException(message);
        }
    }

    private static List<CompositeTextEntry> Merge(IEnumerable<CompositeTextEntry> discovered,
        CompositeCatalogDocument? existing)
    {
        var oldEntries = (existing?.Entries ?? []).ToDictionary(entry => entry.EntryPointId,
            StringComparer.Ordinal);
        var merged = new List<CompositeTextEntry>();
        foreach (var entry in discovered.GroupBy(item => item.EntryPointId, StringComparer.Ordinal)
                     .Select(group => group.First()))
        {
            if (oldEntries.TryGetValue(entry.EntryPointId, out var old))
            {
                // Source-owned XML, managed-map, and runtime-map translations are
                // regenerated from the current patch sources. Prefer that value when the
                // previous row was also source-owned, so corrected tags or
                // wording cannot be masked forever by a stale generated row.
                // Manually supplied fixture/rule values remain durable and are
                // still validated on regeneration.
                var oldIsSourceOwned =
                    (StringComparer.Ordinal.Equals(entry.Source.Kind, "Xml") &&
                        old.RuleId is "xml-existing-translation" or "xml-text-key-translation" or
                        "xml-text-key-structural") ||
                    StringComparer.Ordinal.Equals(entry.Source.Kind, "ManagedRewriteMap") ||
                    StringComparer.Ordinal.Equals(entry.Source.Kind, "RuntimeMap");
                if (old.LocalizedFormat is not null &&
                    (entry.LocalizedFormat is null || !oldIsSourceOwned))
                    entry.LocalizedFormat = old.LocalizedFormat;
                if (!string.IsNullOrWhiteSpace(old.RuleId)) entry.RuleId = old.RuleId;
                if (!string.IsNullOrWhiteSpace(old.Notes)) entry.Notes = old.Notes;
                if (!string.IsNullOrWhiteSpace(old.Status) &&
                    !StringComparer.Ordinal.Equals(old.Status, "Unreviewed"))
                    entry.Status = old.Status;
                entry.Stale = false;
            }
            merged.Add(entry);
        }
        foreach (var old in oldEntries.Values.Where(old =>
                     !merged.Any(entry => StringComparer.Ordinal.Equals(entry.EntryPointId, old.EntryPointId))))
        {
            // Runtime display-map bindings are a source-owned, current-state map.
            // Keeping deleted rows as stale entries makes the durable index claim
            // that inactive global fragments are still available at runtime.
            if (StringComparer.Ordinal.Equals(old.Source.Kind, "RuntimeMap"))
                continue;
            old.Status = "Stale";
            old.Stale = true;
            old.Notes = AppendNote(old.Notes,
                "Source was not rediscovered during the latest composite catalog scan.");
            merged.Add(old);
        }
        return merged;
    }

    private static void ApplyStaticAudit(IReadOnlyList<CompositeTextEntry> entries,
        IReadOnlyList<CompositeSafetyRejection> safetyRejections)
    {
        var rewriteTranslations = entries
            .Where(entry => !entry.Stale &&
                StringComparer.Ordinal.Equals(entry.Source.Kind, "ManagedRewriteMap") &&
                entry.LocalizedFormat is not null)
            .GroupBy(entry => entry.OriginalFormat, StringComparer.Ordinal)
            .ToDictionary(
                group => group.Key,
                group => group.Select(entry => entry.LocalizedFormat!)
                    .Distinct(StringComparer.Ordinal).ToArray(),
                StringComparer.Ordinal);

        foreach (var entry in entries)
        {
            entry.Notes = RemoveRetiredAuditNotes(entry.Notes);
            if (entry.Stale)
            {
                entry.AuditStatus = "Stale";
                entry.RuleScope = "None";
                continue;
            }
            if (TryFindSafetyRejection(entry, safetyRejections, out var rejection))
            {
                if (!string.IsNullOrWhiteSpace(entry.RuleId) || entry.LocalizedFormat is not null)
                    throw new InvalidDataException(
                        $"Composite entry '{entry.EntryPointId}' is localized despite a canonical safety rejection.");
                entry.Status = "RejectedBySafetyRecord";
                entry.AuditStatus = "RejectedBySafetyRecord";
                entry.RuleScope = "None";
                entry.Notes = AppendNote(entry.Notes,
                    $"Static audit: localization intentionally omitted by the canonical safety registry ({rejection.Reason}).");
                continue;
            }
            if (!string.IsNullOrWhiteSpace(entry.RuleId) || entry.LocalizedFormat is not null)
            {
                entry.AuditStatus = "Localized";
                entry.RuleScope = GetRuleScope(entry.RuleId, entry.Source.Kind);
                continue;
            }
            if (!StringComparer.Ordinal.Equals(entry.Source.Kind, "Managed"))
            {
                entry.AuditStatus = "NotManagedComposition";
                entry.RuleScope = "None";
                continue;
            }
            if (entry.Parts.Count <= 1)
            {
                entry.AuditStatus = "NotConcatenation";
                entry.RuleScope = "None";
                continue;
            }

            var translations = new Dictionary<string, string>(StringComparer.Ordinal);
            var requiresDisplayTemplate = false;
            var unmatchedLiterals = new List<string>();
            foreach (var part in entry.Parts.Where(part =>
                         StringComparer.Ordinal.Equals(part.Kind, "Literal")))
            {
                if (translations.ContainsKey(part.Value)) continue;
                if (TryGetCompositeLiteralTranslation(part.Value, rewriteTranslations,
                        out var translation, out var changesDisplayText))
                {
                    translations[part.Value] = translation;
                    requiresDisplayTemplate |= changesDisplayText;
                    continue;
                }
                unmatchedLiterals.Add(part.Value);
            }
            if (unmatchedLiterals.Count == 0)
            {
                entry.LocalizedFormat = LocalizeLiteralParts(entry, translations);
                entry.Status = "ExistingRule";
                entry.RuleId = requiresDisplayTemplate
                    ? "runtime-display-template"
                    : "runtime-display-argument-only";
                entry.AuditStatus = "Localized";
                entry.RuleScope = requiresDisplayTemplate
                    ? "UniformLiteralTemplate"
                    : "ArgumentOrTokenOnly";
                entry.Notes = AppendNote(entry.Notes,
                    requiresDisplayTemplate
                        ? "Static audit: every literal has one shared Chinese translation across all mapped callers; the final-display template preserves arguments and rich-text structure."
                        : "Static audit: this composition contains only arguments, punctuation, or non-linguistic operands; no runtime template is registered because an argument-only template would match unrelated display text.");
                continue;
            }

            if (TryApplyEntrySpecificRewrite(entry, entries, out var localized, out var ruleId))
            {
                entry.LocalizedFormat = localized;
                entry.Status = "ExistingRule";
                entry.RuleId = ruleId;
                entry.AuditStatus = "Localized";
                entry.RuleScope = "EntrySpecific";
                entry.Notes = AppendNote(entry.Notes,
                    "Static audit: conflicting fragment grammar is covered by the nearest exact entry-specific IL rewrite.");
                continue;
            }

            entry.AuditStatus = "Unreviewed";
            entry.RuleScope = "None";
            entry.Notes = AppendNote(entry.Notes,
                "Static audit: missing a shared literal translation: " +
                string.Join(" | ", unmatchedLiterals.OrderBy(value => value, StringComparer.Ordinal)));
        }
    }

    private static bool TryGetCompositeLiteralTranslation(string value,
        IReadOnlyDictionary<string, string[]> rewriteTranslations, out string translation,
        out bool changesDisplayText)
    {
        if (rewriteTranslations.TryGetValue(value, out var candidates) && candidates.Length == 1)
        {
            translation = candidates[0];
            changesDisplayText = !StringComparer.Ordinal.Equals(value, translation);
            return true;
        }
        if (CompositeLiteralTranslations.TryGetValue(value, out translation!))
        {
            changesDisplayText = !StringComparer.Ordinal.Equals(value, translation);
            return true;
        }
        var trimmedOriginal = value.Trim();
        var trimmedMatches = CompositeLiteralTranslations
            .Where(pair => StringComparer.Ordinal.Equals(pair.Key.Trim(), trimmedOriginal))
            .Select(pair => pair.Value.Trim())
            .Distinct(StringComparer.Ordinal)
            .ToArray();
        if (trimmedMatches.Length == 1)
        {
            var leadingLength = value.Length - value.TrimStart().Length;
            var trailingLength = value.Length - value.TrimEnd().Length;
            translation = value[..leadingLength] + trimmedMatches[0] +
                (trailingLength == 0 ? "" : value[^trailingLength..]);
            changesDisplayText = !StringComparer.Ordinal.Equals(value, translation);
            return true;
        }
        if (IsNonLinguisticCompositeLiteral(value))
        {
            translation = value;
            changesDisplayText = false;
            return true;
        }
        translation = "";
        changesDisplayText = false;
        return false;
    }

    private static bool IsNonLinguisticCompositeLiteral(string value)
    {
        if (string.IsNullOrWhiteSpace(value)) return true;
        var trimmed = value.Trim();
        if (trimmed.IndexOfAny(['/', '\\']) >= 0 || MachineToken.IsMatch(trimmed)) return true;
        if (trimmed.StartsWith("[", StringComparison.Ordinal) &&
            trimmed.EndsWith("]", StringComparison.Ordinal) &&
            !trimmed.Contains(' ')) return true;
        return trimmed.All(character => !char.IsLetter(character) ||
            char.IsUpper(character) || char.IsDigit(character) ||
            character is '_' or '.' or ':' or '[' or ']' or '-' or '+' or '*');
    }

    private static string? RemoveRetiredAuditNotes(string? notes)
    {
        if (string.IsNullOrWhiteSpace(notes)) return notes;
        foreach (var retired in new[]
        {
            "Static audit: entry contains only structural, tag, identifier, or non-English parts.",
            "Static audit: no uniform display-safe translation or exact entry-specific rewrite was proven; retained without a localization rule.",
            "Static audit: no shared literal translation or exact entry template is currently available.",
        })
        {
            notes = notes.Replace(retired, "", StringComparison.Ordinal);
        }
        if (Regex.IsMatch(notes,
                @"\b(?:trial|needstrial|batch)\b|\b20\d{2}-\d{2}-\d{2}\b",
                RegexOptions.IgnoreCase))
        {
            // Historic exploratory-batch provenance is intentionally retained
            // only in localization-safety-registry.json. Active entries keep
            // their exact source locators, safety class, and current mapping.
            return "Accepted mapping; exact source locator is authoritative.";
        }
        notes = Regex.Replace(notes, @"\s{2,}", " ").Trim();
        return notes.Length == 0 ? null : notes;
    }

    private static void ApplyEntrySpecificRules(IReadOnlyList<CompositeTextEntry> entries,
        string rulesPath)
    {
        if (!File.Exists(rulesPath)) return;
        var document = JsonSerializer.Deserialize<CompositeEntrySpecificRuleDocument>(
            File.ReadAllText(rulesPath),
            new JsonSerializerOptions { PropertyNameCaseInsensitive = true })
            ?? throw new InvalidDataException($"Entry-specific rule document is empty: {rulesPath}");
        var duplicates = document.Entries.GroupBy(rule => rule.EntryPointId,
                StringComparer.Ordinal).FirstOrDefault(group => group.Count() > 1);
        if (duplicates is not null)
            throw new InvalidDataException(
                $"Duplicate entry-specific rule for '{duplicates.Key}'.");
        var entryById = entries.ToDictionary(entry => entry.EntryPointId,
            StringComparer.Ordinal);
        foreach (var rule in document.Entries)
        {
            if (string.IsNullOrWhiteSpace(rule.EntryPointId) ||
                string.IsNullOrWhiteSpace(rule.LocalizedFormat))
                throw new InvalidDataException(
                    "Entry-specific rules require EntryPointId and LocalizedFormat.");
            if (!entryById.TryGetValue(rule.EntryPointId, out var entry))
                throw new InvalidDataException(
                    $"Entry-specific rule references unknown entry '{rule.EntryPointId}'.");
            if (!StringComparer.Ordinal.Equals(entry.Source.Kind, "Managed"))
                throw new InvalidDataException(
                    $"Entry-specific rule '{rule.EntryPointId}' must target a managed composition.");
            entry.LocalizedFormat = rule.LocalizedFormat;
            entry.Status = "ExistingRule";
            entry.RuleId = "runtime-display-template";
            entry.AuditStatus = "Localized";
            entry.RuleScope = "EntrySpecific";
            entry.Notes = AppendNote(entry.Notes,
                rule.Notes ?? "Static entry-specific display template.");
        }
    }

    private static bool TryApplyEntrySpecificRewrite(CompositeTextEntry entry,
        IReadOnlyList<CompositeTextEntry> entries, out string localized, out string ruleId)
    {
        localized = "";
        ruleId = "";
        var partTranslations = new Dictionary<string, string>(StringComparer.Ordinal);
        var ruleIds = new HashSet<string>(StringComparer.Ordinal);
        foreach (var part in entry.Parts.Where(part =>
                     StringComparer.Ordinal.Equals(part.Kind, "Literal") &&
                     IsLocalizableTextLiteral(part.Value)))
        {
            var candidate = entries
                .Where(map => !map.Stale &&
                    StringComparer.Ordinal.Equals(map.Source.Kind, "ManagedRewriteMap") &&
                    RewriteMapTargetsAssembly(map.Source.RelativePath, entry.Source.RelativePath) &&
                    StringComparer.Ordinal.Equals(map.Source.MethodToken, entry.Source.MethodToken) &&
                    StringComparer.Ordinal.Equals(map.OriginalFormat, part.Value) &&
                    map.LocalizedFormat is not null &&
                    map.Source.ILOffset is not null && entry.Source.ILOffset is not null &&
                    map.Source.ILOffset <= entry.Source.ILOffset)
                .OrderByDescending(map => map.Source.ILOffset)
                .FirstOrDefault();
            if (candidate is null || entry.Source.ILOffset - candidate.Source.ILOffset > 128 ||
                string.IsNullOrWhiteSpace(candidate.RuleId))
                return false;
            partTranslations[part.Value] = candidate.LocalizedFormat!;
            ruleIds.Add(candidate.RuleId);
        }
        if (partTranslations.Count == 0 || ruleIds.Count != 1) return false;
        localized = LocalizeLiteralParts(entry, partTranslations);
        ruleId = ruleIds.Single();
        return true;
    }

    private static bool RewriteMapTargetsAssembly(string mapPath, string sourcePath)
    {
        if (sourcePath.Contains("AtTheGatesCommon", StringComparison.OrdinalIgnoreCase))
            return mapPath.Contains("hardcoded-common", StringComparison.OrdinalIgnoreCase);
        if (sourcePath.Contains("AtTheGatesUI", StringComparison.OrdinalIgnoreCase))
            return mapPath.Contains("hardcoded-ui", StringComparison.OrdinalIgnoreCase);
        if (sourcePath.Contains("AtTheGatesGame", StringComparison.OrdinalIgnoreCase))
            return mapPath.Contains("hardcoded-game", StringComparison.OrdinalIgnoreCase);
        if (sourcePath.Contains("ElfTools", StringComparison.OrdinalIgnoreCase))
            return mapPath.Contains("hardcoded-elftools", StringComparison.OrdinalIgnoreCase);
        return false;
    }

    private static string LocalizeLiteralParts(CompositeTextEntry entry,
        IReadOnlyDictionary<string, string> translations)
    {
        var builder = new StringBuilder();
        var searchStart = 0;
        foreach (var part in entry.Parts.OrderBy(part => part.Position))
        {
            if (!StringComparer.Ordinal.Equals(part.Kind, "Literal") ||
                !translations.TryGetValue(part.Value, out var replacement))
                continue;
            var index = entry.OriginalFormat.IndexOf(part.Value, searchStart,
                StringComparison.Ordinal);
            if (index < 0) throw new InvalidDataException(
                $"Cannot localize composite literal '{part.Value}' in '{entry.EntryPointId}'.");
            builder.Append(entry.OriginalFormat, searchStart, index - searchStart);
            builder.Append(replacement);
            searchStart = index + part.Value.Length;
        }
        builder.Append(entry.OriginalFormat, searchStart,
            entry.OriginalFormat.Length - searchStart);
        return builder.ToString();
    }

    private static string GetRuleScope(string? ruleId, string sourceKind)
    {
        if (ruleId is not null && ruleId.StartsWith("il-rewrite-", StringComparison.Ordinal))
            return "EntrySpecific";
        if (StringComparer.Ordinal.Equals(ruleId, "xml-text-key-translation"))
            return "TextKeyReference";
        if (StringComparer.Ordinal.Equals(ruleId, "xml-text-key-structural"))
            return "TextKeyStructural";
        if (StringComparer.Ordinal.Equals(ruleId, "runtime-display-fragment"))
            return "UniformFragment";
        if (StringComparer.Ordinal.Equals(ruleId, "runtime-display-argument-only"))
            return "ArgumentOrTokenOnly";
        return StringComparer.Ordinal.Equals(sourceKind, "RuntimeMap")
            ? "RuntimeMap"
            : "EntrySpecific";
    }

    private static List<CompositeLocalizationRule> BuildRules(IEnumerable<CompositeTextEntry> entries,
        IEnumerable<CompositeLocalizationRule>? existingRules)
    {
        var rules = new Dictionary<string, CompositeLocalizationRule>(StringComparer.Ordinal)
        {
            ["runtime-richtext-final-process"] = new()
            {
                RuleId = "runtime-richtext-final-process",
                Kind = "RuntimeFinalDisplay",
                Status = "Active",
                EntryPointId = "AtTheGatesCommon.ns_Text.TextFormatter::Process",
                Description = "Final rich-text localization preserves concept keys and recursive hover structure.",
                Source = "tools/AtG.RuntimeText/DisplayStringLocalizer.cs",
            },
            ["concept-tooltip-static-registration"] = new()
            {
                RuleId = "concept-tooltip-static-registration",
                Kind = "ManagedTooltipRegistration",
                Status = "Active",
                EntryPointId = "AtTheGatesCommon.ns_UI.Concepts::.cctor -> Concepts.c(key, label, description)",
                Description = "Concept hover text is registered from literal, concatenated, and XML-key operands in the Concepts static constructor, then localized at the final rich-text display boundary.",
                Source = "tools/AtG.ManagedRewrite/ConceptTooltipCatalog.cs; translations/hardcoded-common-il-rewrite.json; translations/concept-key-translations.json",
            },
            ["runtime-display-exact"] = new()
            {
                RuleId = "runtime-display-exact",
                Kind = "RuntimeDisplayMap",
                Status = "Active",
                EntryPointId = "runtime-map:Exact",
                Description = "Exact final display strings are localized without token rewriting.",
                Source = "translations/runtime-display-strings.json",
            },
            ["runtime-display-plain"] = new()
            {
                RuleId = "runtime-display-plain",
                Kind = "RuntimeDisplayMap",
                Status = "Active",
                EntryPointId = "runtime-map:PlainText",
                Description = "Plain final display strings are localized at the rich-text display boundary.",
                Source = "translations/runtime-display-strings.json",
            },
            ["runtime-display-fragment"] = new()
            {
                RuleId = "runtime-display-fragment",
                Kind = "RuntimeDisplayMap",
                Status = "Active",
                EntryPointId = "runtime-map:PlainTextFragments",
                Description = "Legacy display fragments are applied only after the final rich-text boundary.",
                Source = "translations/runtime-display-strings.json",
            },
            ["runtime-display-richtext-fragment"] = new()
            {
                RuleId = "runtime-display-richtext-fragment",
                Kind = "RuntimeDisplayMap",
                Status = "Active",
                EntryPointId = "runtime-map:RichTextFragments",
                Description = "Scoped rich-text fragments are replaced before parsing so their concept keys and recursive hovers remain intact.",
                Source = "translations/runtime-display-strings.json",
            },
            ["runtime-display-template"] = new()
            {
                RuleId = "runtime-display-template",
                Kind = "RuntimeDisplayTemplate",
                Status = "Active",
                EntryPointId = "runtime-map:Templates",
                Description = "Entry-specific display templates preserve every runtime argument and rich-text structure.",
                Source = "translations/runtime-display-strings.json; translations/composite-entry-specific-rules.json",
            },
            ["runtime-display-argument-only"] = new()
            {
                RuleId = "runtime-display-argument-only",
                Kind = "CompositeArgumentPassthrough",
                Status = "Active",
                EntryPointId = "runtime-map:ArgumentsOnly",
                Description = "Argument-only and non-linguistic composite operands need no display template; registering an all-argument template would match unrelated text.",
                Source = "tools/AtG.ManagedRewrite/CompositeTextCatalog.cs",
            },
            ["runtime-display-concept"] = new()
            {
                RuleId = "runtime-display-concept",
                Kind = "RuntimeDisplayMap",
                Status = "Active",
                EntryPointId = "runtime-map:ConceptDisplay",
                Description = "Only concept-link display text changes; the concept key remains intact.",
                Source = "translations/runtime-display-strings.json",
            },
            ["xml-existing-translation"] = new()
            {
                RuleId = "xml-existing-translation",
                Kind = "XmlDisplayTemplate",
                Status = "Active",
                EntryPointId = "patch:xml",
                Description = "Existing patch XML supplies the localized display format for the same source node.",
                Source = "patch/Content",
            },
            ["xml-text-key-translation"] = new()
            {
                RuleId = "xml-text-key-translation",
                Kind = "XmlTextKeyReference",
                Status = "Active",
                EntryPointId = "patch:Content/Text/English.xml",
                Description = "A Composite TEXT.* reference resolves to a localized English.xml text key in the patch.",
                Source = "patch/Content/Text/English.xml",
            },
            ["xml-text-key-structural"] = new()
            {
                RuleId = "xml-text-key-structural",
                Kind = "XmlTextKeyReference",
                Status = "Active",
                EntryPointId = "patch:Content/Text/English.xml",
                Description = "A Composite TEXT.* reference resolves to an intentionally language-neutral numeric or placeholder-only text key.",
                Source = "patch/Content/Text/English.xml",
            },
        };
        foreach (var existing in existingRules ?? [])
        {
            if (string.IsNullOrWhiteSpace(existing.RuleId) || rules.ContainsKey(existing.RuleId))
                continue;
            rules[existing.RuleId] = new CompositeLocalizationRule
            {
                RuleId = existing.RuleId,
                Kind = existing.Kind,
                Status = existing.Status,
                EntryPointId = existing.EntryPointId,
                Description = existing.Description,
                Source = existing.Source,
            };
        }
        foreach (var entry in entries)
        {
            if (string.IsNullOrWhiteSpace(entry.RuleId)) continue;
            if (rules.ContainsKey(entry.RuleId)) continue;
            rules[entry.RuleId] = new CompositeLocalizationRule
            {
                RuleId = entry.RuleId,
                Kind = entry.Source.Kind == "ManagedRewriteMap" ? "ManagedIlRewrite" : "Manual",
                Status = entry.Status,
                EntryPointId = entry.EntryPointId,
                Description = entry.Notes ?? "Preserved generated or manually maintained localization binding.",
                Source = entry.Source.RelativePath,
            };
        }
        return rules.Values.ToList();
    }

    private static IEnumerable<CompositeTextEntry> ReadRuntimeMapEntries(string root)
    {
        var path = Path.Combine(root, "translations", "runtime-display-strings.json");
        if (!File.Exists(path)) yield break;
        using var document = OpenJson(path);
        if (document.RootElement.ValueKind != JsonValueKind.Object) yield break;
        foreach (var section in new[] { "Exact", "PlainText", "PlainTextFragments", "RichTextFragments", "Templates", "ConceptDisplay" })
        {
            if (!document.RootElement.TryGetProperty(section, out var values) ||
                values.ValueKind != JsonValueKind.Array) continue;
            foreach (var value in values.EnumerateArray())
            {
                if (!TryGetString(value, "Original", out var original) ||
                    !TryGetString(value, "Translation", out var translation)) continue;
                var key = section == "ConceptDisplay" && TryGetString(value, "ConceptKey", out var conceptKey)
                    ? conceptKey : null;
                var originalFormat = key is null ? original : $"[{original}|{key}]";
                var localizedFormat = key is null ? translation : $"[{translation}|{key}]";
                var entry = NewEntry($"runtime-map:{section}:{ShortHash((key ?? "") + "\u001f" + original)}",
                    new CompositeTextSource
                    {
                        Kind = "RuntimeMap",
                        RelativePath = "translations/runtime-display-strings.json",
                        CallKind = section,
                    }, originalFormat,
                    [new CompositeTextPart
                    {
                        Position = 0,
                        Kind = "Literal",
                        Value = originalFormat,
                        KnownTextReference = new CompositeKnownTextReference
                        {
                            SourceFile = RuntimeDisplayMapSourceFile,
                            Original = originalFormat,
                            RuntimeMapSection = section,
                            RuntimeMapOriginal = original,
                            RuntimeMapConceptKey = key,
                        },
                    }],
                    "DisplaySafe",
                    "Exact");
                entry.LocalizedFormat = localizedFormat;
                entry.Status = "ExistingRule";
                entry.RuleId = section switch
                {
                    "Exact" => "runtime-display-exact",
                    "PlainText" => "runtime-display-plain",
                    "PlainTextFragments" => "runtime-display-fragment",
                    "RichTextFragments" => "runtime-display-richtext-fragment",
                    "Templates" => "runtime-display-template",
                    _ => "runtime-display-concept",
                };
                entry.Notes = key is null ? "Generated from runtime display-map binding."
                    : $"Generated from runtime concept-display binding for key '{key}'.";
                yield return entry;
            }
        }
    }

    private static IReadOnlyList<CompositeSafetyRejection> ReadKnownSafetyRejections(string root)
    {
        var path = Path.Combine(root, "translations", "localization-safety-registry.json");
        if (!File.Exists(path)) return [];
        using var document = OpenJson(path);
        if (document.RootElement.ValueKind != JsonValueKind.Object ||
            !document.RootElement.TryGetProperty("RejectedOperands", out var values) ||
            values.ValueKind != JsonValueKind.Array)
            return [];

        var result = new List<CompositeSafetyRejection>();
        foreach (var value in values.EnumerateArray())
        {
            if (!TryGetString(value, "Assembly", out var assembly) ||
                !TryGetString(value, "MethodToken", out var methodToken) ||
                !TryGetString(value, "Original", out var original) ||
                !TryGetString(value, "Reason", out var reason) ||
                !value.TryGetProperty("ILOffset", out var offset) ||
                !offset.TryGetInt32(out var ilOffset))
                continue;
            var sourceFile = assembly switch
            {
                "UI" => "source/AtTheGatesUI.original.dll",
                "Common" => "source/AtTheGatesCommon.original.dll",
                "Game" => "source/AtTheGatesGame.original.exe",
                "ElfTools" => "source/ElfTools.original.dll",
                _ => "",
            };
            if (string.IsNullOrWhiteSpace(sourceFile)) continue;
            result.Add(new CompositeSafetyRejection(sourceFile, methodToken, ilOffset,
                original, reason));
        }
        return result;
    }

    private static bool TryFindSafetyRejection(CompositeTextEntry entry,
        IReadOnlyList<CompositeSafetyRejection> safetyRejections,
        out CompositeSafetyRejection rejection)
    {
        foreach (var part in entry.Parts)
        {
            var reference = part.KnownTextReference;
            if (reference is null) continue;
            var match = safetyRejections.FirstOrDefault(candidate =>
                StringComparer.Ordinal.Equals(candidate.SourceFile, reference.SourceFile) &&
                StringComparer.OrdinalIgnoreCase.Equals(candidate.MethodToken, reference.MethodToken) &&
                candidate.ILOffset == reference.ILOffset &&
                MatchesRecordedSmokeOriginal(candidate.Original, reference.Original));
            if (match is null) continue;
            rejection = match;
            return true;
        }
        rejection = null!;
        return false;
    }

    // A historic safety record normalized the leading space of one literal. The DLL
    // locator (assembly, method token, and IL offset) remains exact, so allow only
    // edge-space normalization when applying that rejected safety record.
    private static bool MatchesRecordedSmokeOriginal(string recorded, string current) =>
        StringComparer.Ordinal.Equals(recorded, current) ||
        StringComparer.Ordinal.Equals(recorded.Trim(), current.Trim());

    private static IEnumerable<CompositeTextEntry> ReadManagedRewriteMapEntries(string root)
    {
        var maps = new[]
        {
            ("hardcoded-ui-il-rewrite.json", "il-rewrite-ui"),
            ("hardcoded-common-il-rewrite.json", "il-rewrite-common"),
            ("hardcoded-game-il-rewrite.json", "il-rewrite-game"),
            ("hardcoded-elftools-il-rewrite.json", "il-rewrite-elftools"),
        };
        foreach (var (name, ruleId) in maps)
        {
            var path = Path.Combine(root, "translations", name);
            if (!File.Exists(path)) continue;
            using var document = OpenJson(path);
            if (document.RootElement.ValueKind != JsonValueKind.Array) continue;
            foreach (var value in document.RootElement.EnumerateArray())
            {
                if (!TryGetString(value, "Original", out var original) ||
                    !TryGetString(value, "Translation", out var translation)) continue;
                if (!TryGetString(value, "MethodToken", out var token) ||
                    !value.TryGetProperty("ILOffset", out var offsetElement) ||
                    !offsetElement.TryGetInt32(out var offset)) continue;
                var relative = "translations/" + name;
                var knownTextSource = GetManagedRewriteKnownTextSource(name);
                var entry = NewEntry($"managed-map:{name}:{token}:IL_{offset:X4}",
                    new CompositeTextSource
                    {
                        Kind = "ManagedRewriteMap",
                        RelativePath = relative,
                        TypeFullName = GetString(value, "TypeFullName"),
                        MethodName = GetString(value, "MethodName"),
                        MethodToken = token,
                        ILOffset = offset,
                        CallKind = "LdstrRewrite",
                    }, original,
                    [new CompositeTextPart
                    {
                        Position = 0,
                        Kind = "Literal",
                        Value = original,
                        KnownTextReference = NewManagedKnownTextReference(
                            knownTextSource, token, offset, original),
                    }],
                    ClassifyManagedRewrite(name), "Exact");
                entry.LocalizedFormat = translation;
                entry.Status = "ExistingRule";
                entry.RuleId = ruleId;
                entry.Notes = GetString(value, "Note") ?? "Generated from existing managed IL rewrite map.";
                yield return entry;
            }
        }
    }

    private static CompositeCatalogDocument? LoadExisting(string rulesPath)
    {
        if (!File.Exists(rulesPath)) return null;
        try
        {
            return JsonSerializer.Deserialize<CompositeCatalogDocument>(File.ReadAllText(rulesPath),
                JsonOptions);
        }
        catch (JsonException exception)
        {
            throw new InvalidDataException($"Composite rules JSON is invalid: {rulesPath}", exception);
        }
    }

    private static CompositeTextEntry NewEntry(string entryId, CompositeTextSource source,
        string original, List<CompositeTextPart> parts, string classification, string confidence)
    {
        return new CompositeTextEntry
        {
            EntryPointId = entryId,
            Source = source,
            OriginalFormat = original,
            Classification = classification,
            Confidence = confidence,
            Parts = parts,
            StructuralFlags = GetStructuralFlags(original),
        };
    }

    private static bool TryGetCompositeCallKind(IMethod method, out string kind)
    {
        var declaring = method.DeclaringType?.FullName ?? "";
        var name = method.Name;
        if (declaring == "System.String" &&
            (name == "Concat" || name == "Format" || name == "Join"))
        {
            kind = "String." + name;
            return true;
        }
        if (declaring == "System.Text.StringBuilder" &&
            (name.StartsWith("Append", StringComparison.Ordinal) || name == "Insert"))
        {
            kind = "StringBuilder." + name;
            return true;
        }
        if (declaring == "AtTheGatesCommon.ns_Text.TextFormatter" &&
            (name == "Process" || name.StartsWith("Format", StringComparison.Ordinal)))
        {
            kind = "TextFormatter." + name;
            return true;
        }
        kind = "";
        return false;
    }

    private static List<CompositeTextPart> ExtractParts(IList<Instruction> instructions,
        int callIndex, IMethod target, string callKind, string sourceFile, string methodToken)
    {
        if (callKind is "String.Format" or "StringBuilder.AppendFormat")
        {
            var format = FindFormatLiteral(instructions, callIndex, sourceFile, methodToken);
            if (format is not null)
                return [format];
        }
        var count = target.MethodSig?.Params.Count ?? 1;
        if (callKind.StartsWith("StringBuilder.", StringComparison.Ordinal)) count = Math.Max(1, count);
        count = Math.Clamp(count, 1, 8);
        var parts = new List<CompositeTextPart>();
        var examined = 0;
        for (var index = callIndex - 1; index >= 0 && parts.Count < count && examined < 32;
             index--, examined++)
        {
            var instruction = instructions[index];
            if (instruction.OpCode == OpCodes.Ldstr)
            {
                parts.Add(NewManagedLiteralPart((string)instruction.Operand, sourceFile,
                    methodToken, checked((int)instruction.Offset)));
                continue;
            }
            if (IsTransparentStackInstruction(instruction)) continue;
            if (instruction.OpCode.FlowControl is FlowControl.Branch or FlowControl.Cond_Branch or
                FlowControl.Return or FlowControl.Throw) break;
            parts.Add(new CompositeTextPart { Kind = "Argument", Value = "" });
        }
        parts.Reverse();
        if (parts.Count == 0) parts.Add(new CompositeTextPart { Kind = "Argument", Value = "" });
        for (var index = 0; index < parts.Count; index++) parts[index].Position = index;
        return parts;
    }

    private static bool IsTransparentStackInstruction(Instruction instruction) =>
        instruction.OpCode is var opcode && (opcode == OpCodes.Box || opcode == OpCodes.Castclass ||
            opcode == OpCodes.Conv_I || opcode == OpCodes.Conv_I4 || opcode == OpCodes.Conv_I8 ||
            opcode == OpCodes.Conv_R4 || opcode == OpCodes.Conv_R8 || opcode == OpCodes.Nop);

    private static CompositeTextPart? FindFormatLiteral(IList<Instruction> instructions, int callIndex,
        string sourceFile, string methodToken)
    {
        for (var index = callIndex - 1; index >= 0 && callIndex - index <= 24; index--)
        {
            var instruction = instructions[index];
            if (instruction.OpCode == OpCodes.Ldstr)
                return NewManagedLiteralPart((string)instruction.Operand, sourceFile,
                    methodToken, checked((int)instruction.Offset));
            if (instruction.OpCode.FlowControl is FlowControl.Branch or FlowControl.Cond_Branch or
                FlowControl.Return or FlowControl.Throw) break;
        }
        return null;
    }

    private static CompositeTextPart NewManagedLiteralPart(string value, string sourceFile,
        string methodToken, int ilOffset) => new()
    {
        Kind = "Literal",
        Value = value,
        KnownTextReference = NewManagedKnownTextReference(sourceFile, methodToken, ilOffset, value),
    };

    private static CompositeKnownTextReference NewManagedKnownTextReference(string sourceFile,
        string methodToken, int ilOffset, string original) => new()
    {
        SourceFile = sourceFile,
        MethodToken = methodToken,
        ILOffset = ilOffset,
        Original = original,
    };

    private static CompositeKnownTextReference NewXmlKnownTextReference(string sourceFile,
        XmlValue value)
    {
        var textKey = IsTextKeyReference(value.Value) ? value.Value : value.TextKey;
        if (!string.IsNullOrWhiteSpace(textKey))
        {
            return new CompositeKnownTextReference
            {
                SourceFile = "source/English.original.xml",
                Original = value.Value,
                TextKey = textKey,
            };
        }
        if (value.ConfigLocator is not null)
        {
            return new CompositeKnownTextReference
            {
                SourceFile = sourceFile,
                Original = value.Value,
                ConfigId = value.ConfigLocator.Id,
                ConfigXPath = value.ConfigLocator.XPath,
                ConfigIndex = value.ConfigLocator.Index,
            };
        }
        return new CompositeKnownTextReference
        {
            SourceFile = sourceFile,
            XPath = value.XPath,
            Original = value.Value,
        };
    }

    private static bool IsTextKeyReference(string value) =>
        Regex.IsMatch(value, "^(TEXT|TRAIT|FACTION|DISCIPLINE|UNIT|RESOURCE|TERRAIN|RIVER|BONUS|JOB|PROFESSION)[._]",
            RegexOptions.CultureInvariant);

    private static string GetManagedRewriteKnownTextSource(string mapName)
    {
        if (mapName.Contains("-ui-", StringComparison.OrdinalIgnoreCase))
            return "source/AtTheGatesUI.original.dll";
        if (mapName.Contains("-common-", StringComparison.OrdinalIgnoreCase))
            return "source/AtTheGatesCommon.original.dll";
        if (mapName.Contains("-game-", StringComparison.OrdinalIgnoreCase))
            return "source/AtTheGatesGame.original.exe";
        if (mapName.Contains("-elftools-", StringComparison.OrdinalIgnoreCase))
            return "source/ElfTools.original.dll";
        throw new InvalidDataException($"Cannot determine known-text source for managed rewrite map '{mapName}'.");
    }

    private static string BuildOriginalFormat(IEnumerable<CompositeTextPart> parts, string callKind)
    {
        var list = parts.ToList();
        if (callKind == "String.Join" && list.Count == 1 && list[0].Kind == "Literal")
            return list[0].Value + "{arg:0}";
        var builder = new StringBuilder();
        foreach (var part in list)
        {
            builder.Append(part.Kind == "Literal" ? part.Value : "{arg:" + part.Position + "}");
        }
        return builder.ToString();
    }

    private static string Classify(string original, string callKind)
    {
        if (callKind.StartsWith("TextFormatter.", StringComparison.Ordinal)) return "DisplayComposite";
        if (RichTextLink.IsMatch(original) || Placeholder.IsMatch(original) ||
            BracketToken.IsMatch(original) || original.Contains("{arg:", StringComparison.Ordinal) ||
            PipeDelimitedAlias.IsMatch(original)) return "DisplayComposite";
        if (callKind.StartsWith("String.", StringComparison.Ordinal) ||
            callKind.StartsWith("StringBuilder.", StringComparison.Ordinal)) return "DisplayComposite";
        if (original.Length == 0) return "Technical";
        return "DisplayComposite";
    }

    private static string ClassifyManagedRewrite(string mapName) =>
        mapName.Contains("common", StringComparison.OrdinalIgnoreCase) ||
        mapName.Contains("game", StringComparison.OrdinalIgnoreCase)
            ? "LogicSensitive" : "DisplaySafe";

    private static string EstimateConfidence(IEnumerable<CompositeTextPart> parts, string callKind)
    {
        var list = parts.ToList();
        if (callKind is "String.Format" or "StringBuilder.AppendFormat" &&
            list.Count == 1 && list[0].Kind == "Literal") return "Exact";
        return list.All(part => part.Kind == "Literal") ? "Exact" : "Partial";
    }

    private static bool LooksComposite(string value) =>
        Placeholder.IsMatch(value) || RichTextLink.IsMatch(value) || BracketToken.IsMatch(value) ||
        PipeDelimitedAlias.IsMatch(value) ||
        value.Contains("TEXT.", StringComparison.Ordinal) ||
        value.Contains(":PLURAL", StringComparison.Ordinal) ||
        value.Contains(":SINGULAR", StringComparison.Ordinal);

    private static bool IsLocalizableTextLiteral(string value)
    {
        if (string.IsNullOrWhiteSpace(value) ||
            value.IndexOfAny(['[', ']', '|']) >= 0)
            return false;
        if (value.IndexOfAny(['/', '\\']) >= 0 || MachineToken.IsMatch(value))
            return false;
        // A single ASCII token in a composition is an identifier, a path segment,
        // an input key, or a formatting marker in every remaining source occurrence.
        // Natural-language fragments have at least two words and are reviewed as
        // templates or shared fragments above; this does not consult legacy Safety
        // or ReasonCode classifications.
        return AsciiWord.Matches(value).Count >= 2;
    }

    private static List<string> GetStructuralFlags(string value)
    {
        var flags = new List<string>();
        if (RichTextLink.IsMatch(value)) flags.Add("ConceptLink");
        if (ContainsLegacyBareConceptAlias(value)) flags.Add("LegacyConceptAlias");
        if (Placeholder.IsMatch(value)) flags.Add("Placeholder");
        if (BracketToken.IsMatch(value)) flags.Add("RichTextMarkup");
        if (PipeDelimitedAlias.IsMatch(value)) flags.Add("PluralAlias");
        if (value.Contains("[HOTKEY", StringComparison.Ordinal)) flags.Add("Hotkey");
        if (value.Contains("TEXT.", StringComparison.Ordinal)) flags.Add("RuntimeKey");
        return flags;
    }

    private static void ValidateStructure(string original, string localized, string entryPointId)
    {
        // A small set of legacy runtime strings are bare display macros such as
        // [SCORE]. They are not registered concept links and the game renders
        // the token literally unless the final-display map replaces it. Permit
        // only a plain localized display replacement in this scoped map; all
        // actual concept links, hotkeys, and formatting remain strict.
        if (entryPointId.StartsWith("runtime-map:RichTextFragments:",
                StringComparison.Ordinal) &&
            BareRuntimeDisplayToken.IsMatch(original) &&
            !BracketToken.IsMatch(localized))
            return;
        // The base help text contains the one-off typo [Construct|CONSTURCT].
        // The patch deliberately normalizes it to the engine's real CONSTRUCT
        // concept key so it remains an interactive concept link. Keep this
        // catalog validation in step with Test-TextTags without broadening the
        // normal key-preservation rule.
        original = NormalizeKnownSourceConceptTypo(original);
        localized = NormalizeKnownSourceConceptTypo(localized);
        var originalKeys = GetConceptKeys(original)
            .OrderBy(value => value, StringComparer.Ordinal).ToArray();
        var localizedKeys = GetConceptKeys(localized)
            .OrderBy(value => value, StringComparer.Ordinal).ToArray();
        if (!originalKeys.SequenceEqual(localizedKeys, StringComparer.Ordinal))
            throw new InvalidDataException(
                $"Localized format changes concept-link keys for '{entryPointId}'.");
        var originalPlaceholders = Placeholder.Matches(original).Select(match => match.Value)
            .OrderBy(value => value, StringComparer.Ordinal).ToArray();
        var localizedPlaceholders = Placeholder.Matches(localized).Select(match => match.Value)
            .OrderBy(value => value, StringComparer.Ordinal).ToArray();
        if (!originalPlaceholders.SequenceEqual(localizedPlaceholders, StringComparer.Ordinal))
            throw new InvalidDataException(
                $"Localized format changes placeholders for '{entryPointId}'.");
        var originalProtectedTags = GetProtectedTagSignatures(original)
            .OrderBy(value => value, StringComparer.Ordinal).ToArray();
        var localizedProtectedTags = GetProtectedTagSignatures(localized)
            .OrderBy(value => value, StringComparer.Ordinal).ToArray();
        if (!originalProtectedTags.SequenceEqual(localizedProtectedTags, StringComparer.Ordinal))
            throw new InvalidDataException(
                $"Localized format changes markup or hotkeys for '{entryPointId}'.");
        if (ContainsFormattingTag(original) && HasBalancedFormattingTags(original) &&
            !HasBalancedFormattingTags(localized))
            throw new InvalidDataException(
                $"Localized format has invalid FONT/COLOR nesting for '{entryPointId}'.");
    }

    private static string NormalizeKnownSourceConceptTypo(string value) =>
        value.Replace("[Construct|CONSTURCT]", "[Construct|CONSTRUCT]",
            StringComparison.Ordinal);

    private static IEnumerable<string> GetProtectedTagSignatures(string value)
    {
        var malformedLinks = MalformedRichTextLink.Matches(value);
        foreach (Match match in BracketToken.Matches(value))
        {
            var token = match.Value;
            // The bracket prefix of a split legacy link is repaired together
            // with its trailing `|KEY]`; it is not an independent protected tag.
            if (malformedLinks.Cast<Match>().Any(link => link.Index == match.Index))
                continue;
            if (RichTextLink.IsMatch(token)) continue;
            var content = token[1..^1];
            if (LegacyBareConceptAliases.ContainsKey(content)) continue;
            if (TryGetPluralSelectorSignature(content, out var signature))
            {
                yield return signature;
                continue;
            }
            yield return "raw:" + token;
        }
    }

    private static IEnumerable<string> GetConceptKeys(string value)
    {
        foreach (Match match in RichTextLink.Matches(value))
        {
            var key = match.Groups[1].Value;
            if (!NonConceptDisplayKeys.Contains(key)) yield return NormalizeConceptKey(key);
        }
        foreach (Match match in MalformedRichTextLink.Matches(value))
        {
            var key = match.Groups[1].Value;
            if (!NonConceptDisplayKeys.Contains(key)) yield return NormalizeConceptKey(key);
        }
        foreach (Match match in BracketToken.Matches(value))
        {
            var content = match.Value[1..^1];
            if (LegacyBareConceptAliases.TryGetValue(content, out var key))
                yield return key;
        }
    }

    private static bool ContainsLegacyBareConceptAlias(string value) =>
        BracketToken.Matches(value).Cast<Match>()
            .Any(match => LegacyBareConceptAliases.ContainsKey(match.Value[1..^1]));

    private static string NormalizeConceptKey(string key) =>
        ConceptKeyAliases.TryGetValue(key, out var canonical) ? canonical : key;

    private static bool TryGetPluralSelectorSignature(string content, out string signature)
    {
        signature = "";
        var parts = content.Split('|');
        if (parts.Length < 2 || !parts[^1].StartsWith("###:", StringComparison.Ordinal))
            return false;
        if (parts.Take(parts.Length - 1).Any(part => part.Contains(':') || part.Contains('?')))
            return false;
        signature = $"plural:{parts.Length - 1}:{parts[^1]}";
        return true;
    }

    private static bool HasBalancedFormattingTags(string value)
    {
        var stack = new Stack<string>();
        foreach (Match match in BracketToken.Matches(value))
        {
            var content = match.Value[1..^1];
            if (content.StartsWith("/", StringComparison.Ordinal))
            {
                var closing = content[1..];
                if (closing is not ("FONT" or "COLOR")) continue;
                if (stack.Count == 0 || !StringComparer.Ordinal.Equals(stack.Pop(), closing))
                    return false;
                continue;
            }
            var separator = content.IndexOf(':');
            var opening = separator >= 0 ? content[..separator] : content;
            if (opening is "FONT" or "COLOR") stack.Push(opening);
        }
        return stack.Count == 0;
    }

    private static bool ContainsFormattingTag(string value) => BracketToken.Matches(value)
        .Select(match => match.Value[1..^1])
        .Any(content => content is "FONT" or "COLOR" or "/FONT" or "/COLOR" ||
            content.StartsWith("FONT:", StringComparison.Ordinal) ||
            content.StartsWith("COLOR:", StringComparison.Ordinal));

    private static bool IsEnglishSourcePath(string path)
    {
        var normalized = path.Replace('\\', '/');
        return normalized.EndsWith("/source/English.original.xml", StringComparison.OrdinalIgnoreCase) ||
            normalized.EndsWith("/patch/Content/Text/English.xml", StringComparison.OrdinalIgnoreCase);
    }

    private static bool IsConfigSourcePath(string path) => path.Replace('\\', '/')
        .Contains("/source/Content/Config/", StringComparison.OrdinalIgnoreCase);

    private static string? GetEnglishTextKey(string sourcePath, XElement element)
    {
        if (!IsEnglishSourcePath(sourcePath)) return null;
        var entry = element.AncestorsAndSelf().FirstOrDefault(candidate =>
            StringComparer.Ordinal.Equals(candidate.Name.LocalName, "e") &&
            candidate.Attributes().Any(attribute =>
                StringComparer.Ordinal.Equals(attribute.Name.LocalName, "ntry")));
        var key = entry?.Attributes().FirstOrDefault(attribute =>
            StringComparer.Ordinal.Equals(attribute.Name.LocalName, "ntry"))?.Value.Trim();
        return !string.IsNullOrWhiteSpace(key) && IsTextKeyReference(key) ? key : null;
    }

    private static ConfigTextLocator? GetConfigTextLocator(string sourcePath, XElement element)
    {
        if (!IsConfigSourcePath(sourcePath) || !IsConfigTextCandidate(element)) return null;
        var container = element.Ancestors().FirstOrDefault(HasDirectConfigId);
        if (container is null) return null;
        var id = GetDirectConfigId(container);
        if (string.IsNullOrWhiteSpace(id)) return null;
        var xpath = GetConfigRelativeXPath(element, container);
        if (string.IsNullOrWhiteSpace(xpath)) return null;
        return new ConfigTextLocator(id, xpath, GetConfigTextIndex(element, container, xpath));
    }

    private static bool IsConfigTextCandidate(XElement element) => element.Name.LocalName is
        "name" or "shortName" or "description" or "text" or "adjective";

    private static bool HasDirectConfigId(XElement element) => !string.IsNullOrWhiteSpace(
        GetDirectConfigId(element));

    private static string? GetDirectConfigId(XElement element) => element.Elements()
        .FirstOrDefault(child => StringComparer.Ordinal.Equals(child.Name.LocalName, "ID"))?
        .Value.Trim();

    private static string GetConfigRelativeXPath(XElement element, XElement container)
    {
        var parts = new List<string>();
        for (XElement? cursor = element; cursor is not null && cursor != container;
             cursor = cursor.Parent)
            parts.Add(cursor.Name.LocalName);
        parts.Reverse();
        return string.Join("/", parts);
    }

    private static int? GetConfigTextIndex(XElement element, XElement container, string xpath)
    {
        var matching = container.Descendants()
            .Where(IsConfigTextCandidate)
            .Where(candidate => StringComparer.Ordinal.Equals(
                GetConfigRelativeXPath(candidate, container), xpath))
            .ToArray();
        if (matching.Length <= 1) return null;
        var index = 0;
        foreach (var candidate in matching)
        {
            if (candidate == element) return index;
            if (!string.IsNullOrWhiteSpace(candidate.Value)) index++;
        }
        throw new InvalidDataException("Config text element was not found in its containing node.");
    }

    private static IEnumerable<XmlValue> ReadXmlValues(string path)
    {
        var document = XDocument.Load(path, LoadOptions.PreserveWhitespace);
        foreach (var element in document.Descendants())
        {
            if (!element.HasElements && !string.IsNullOrEmpty(element.Value))
                yield return new XmlValue(GetXPath(element), element.Value,
                    GetEnglishTextKey(path, element), GetConfigTextLocator(path, element));
            foreach (var attribute in element.Attributes().Where(attribute =>
                         !string.IsNullOrEmpty(attribute.Value)))
                yield return new XmlValue(GetXPath(attribute), attribute.Value, null, null);
        }
    }

    private static Dictionary<string, string> ReadTextKeyValues(string path) => ReadXmlValues(path)
        .Where(value => !string.IsNullOrWhiteSpace(value.TextKey))
        .ToDictionary(value => value.TextKey!, value => value.Value, StringComparer.Ordinal);

    private static bool IsLocalizationNeutralTextKeyTarget(string value)
    {
        var withoutMarkup = BracketToken.Replace(value, "");
        return !AsciiWord.IsMatch(withoutMarkup);
    }

    private static string GetXPath(XObject item)
    {
        if (item is XAttribute attribute)
            return GetXPath(attribute.Parent!) + "/@" + attribute.Name.LocalName;
        var element = (XElement)item;
        var parents = element.AncestorsAndSelf().Reverse().ToArray();
        var parts = new List<string>(parents.Length);
        foreach (var current in parents)
        {
            var index = current.Parent is null ? 1 : current.Parent.Elements(current.Name)
                .TakeWhile(sibling => sibling != current).Count() + 1;
            parts.Add(current.Name.LocalName + "[" + index + "]");
        }
        return "/" + string.Join("/", parts);
    }

    private static string GetPatchXmlPath(string root, string sourcePath)
    {
        var sourceRoot = Path.Combine(root, "source");
        var relative = Path.GetRelativePath(sourceRoot, sourcePath);
        if (StringComparer.OrdinalIgnoreCase.Equals(relative, "English.original.xml"))
            return Path.Combine(root, "patch", "Content", "Text", "English.xml");
        var patchRelative = relative.Replace(".original.xml", ".xml", StringComparison.OrdinalIgnoreCase);
        if (patchRelative.StartsWith("Content" + Path.DirectorySeparatorChar,
                StringComparison.OrdinalIgnoreCase) ||
            patchRelative.StartsWith("Content/", StringComparison.OrdinalIgnoreCase))
            patchRelative = patchRelative[("Content".Length + 1)..];
        return Path.Combine(root, "patch", "Content", patchRelative);
    }

    private static JsonDocument OpenJson(string path) => JsonDocument.Parse(File.ReadAllText(path),
        new JsonDocumentOptions { AllowTrailingCommas = true, CommentHandling = JsonCommentHandling.Skip });

    private static bool TryGetString(JsonElement value, string name, out string result)
    {
        result = "";
        if (!value.TryGetProperty(name, out var property) ||
            property.ValueKind != JsonValueKind.String) return false;
        result = property.GetString() ?? "";
        return true;
    }

    private static string? GetString(JsonElement value, string name) =>
        value.TryGetProperty(name, out var property) && property.ValueKind == JsonValueKind.String
            ? property.GetString() : null;

    private static string RelativePath(string root, string path) =>
        Path.GetRelativePath(root, path).Replace('\\', '/');

    private static string ShortHash(string value)
    {
        var hash = SHA256.HashData(Encoding.UTF8.GetBytes(value));
        return Convert.ToHexString(hash).Substring(0, 16).ToLowerInvariant();
    }

    private static string AppendNote(string? existing, string additional)
    {
        if (string.IsNullOrWhiteSpace(existing)) return additional;
        return existing.Contains(additional, StringComparison.Ordinal)
            ? existing
            : existing + " " + additional;
    }

    private sealed record CompositeSafetyRejection(string SourceFile, string MethodToken,
        int ILOffset, string Original, string Reason);

    private sealed record XmlValue(string XPath, string Value, string? TextKey,
        ConfigTextLocator? ConfigLocator);

    private sealed record ConfigTextLocator(string Id, string XPath, int? Index);

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        PropertyNameCaseInsensitive = true,
    };
}
