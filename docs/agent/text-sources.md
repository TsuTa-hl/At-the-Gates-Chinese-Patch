# Text Sources and Patch Priority

Use this guide when adding translations, fixing exposed keys, or deciding
whether a string is safe to patch.

For wording, tone, terms, and acceptable English remnants, use
`docs/agent/translation-style.md`. This file defines where text can be safely
written, not how the Chinese should sound.

## Primary Sources

- `source\English.original.xml` -> `translations\zh-CN.json` ->
  `patch\Content\Text\English.xml`
- `source\AtTheGatesUI.original.dll` ->
  `translations\hardcoded-strings.json`
- UI DLL scoped `ldstr` rewrite entries ->
  `translations\hardcoded-ui-il-rewrite.json`
- UI DLL `ldstr` entries ->
  `translations\hardcoded-ui-il-strings.json`
- Verified UI DLL offset strings ->
  `translations\hardcoded-ui-offsets.json`
- `source\AtTheGatesCommon.original.dll` ->
  `translations\hardcoded-common-strings.json`
- Common DLL scoped `ldstr` rewrite entries ->
  `translations\hardcoded-common-il-rewrite.json`
- `source\AtTheGatesGame.original.exe` scoped `ldstr` rewrite entries ->
  `translations\hardcoded-game-il-rewrite.json` -> `patch\At The Gates.exe`
- `source\ElfTools.original.dll` scoped `ldstr` rewrite entries ->
  `translations\hardcoded-elftools-il-rewrite.json` -> `patch\ElfTools.dll`
- Final display-only runtime templates and concept display text ->
  `translations\runtime-display-strings.json` ->
  `patch\Content\Text\AtG.RuntimeText.tsv`
- `source\Content\Config\Primary\ClanTraits.original.xml` ->
  `translations\config-node-strings.json` and
  `translations\config-node-extra-strings.json`
- `source\Content\Config\Primary\Techs.original.xml` ->
  `translations\config-node-extra-strings.json`
- `source\Content\Config\OnMap\Structures.original.xml` ->
  `translations\config-node-onmap-strings.json`
- `source\Content\Config\Primary\FactionTraits.original.xml` and
  `source\Content\Config\Primary\Factions.original.xml` are export-and-review
  sources. Do not bulk-replace them by default.

## XML Rules

- The generated text entry point is `Content\Text\English.xml`.
- The generated file must start directly with `<english>`.
- The generated file must not contain `<?xml ...?>`.
- Keep generated aliases for:
  - `TEXT.Name.Resource.*:SINGULAR`
  - `TEXT.Name.Resource.*:PLURAL`
  - `TEXT.Name.Profession.*:SINGULAR`
  - `TEXT.Name.Profession.*:PLURAL`
  - `TEXT.Name.Discipline.*:SINGULAR`
  - `TEXT.Name.Discipline.*:PLURAL`
  - `TEXT.Name.Structure.*:SINGULAR`
  - `TEXT.Name.Structure.*:PLURAL`
  - `TEXT.Name.Deposit.*:SINGULAR`
  - `TEXT.Name.Deposit.*:PLURAL`
  - `TEXT.Name.Terrain.*:SINGULAR`
  - `TEXT.Name.Terrain.*:PLURAL`

## Static Discovery

When new English text is found, first run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Export-StaticTextCandidates.ps1
```

Only auto-patch strings classified as `SafeDisplay` with stable `ID`, `XPath`,
or `Index` metadata. The static exporter scans `source\Content\Config`
recursively and should use the nearest XML element with a direct `ID` child as
the candidate container. This is required for files such as
`Content\Config\OnMap\Structures.xml`, where visible `structure/description`
text sits below category wrappers. Current static-candidate status:

- `ClanTraits.xml` `SafeDisplay` entries are covered.
- Remaining candidates are mostly `Factions.original.xml` `ManualOnly` faction
  names or labels and must not be force-patched by default.

For DLL strings, export a method-level `ldstr` catalog before byte searching:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Export-DllLdstrCatalog.ps1 -DllPath .\source\AtTheGatesUI.original.dll -OutputJson .\.tmp\ui-ldstr-catalog.json -OutputCsv .\.tmp\ui-ldstr-catalog.csv
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Export-DllLdstrCatalog.ps1 -DllPath .\source\AtTheGatesCommon.original.dll -OutputJson .\.tmp\common-ldstr-catalog.json -OutputCsv .\.tmp\common-ldstr-catalog.csv
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Export-DllLdstrCatalog.ps1 -DllPath .\source\ElfTools.original.dll -OutputJson .\.tmp\elftools-ldstr-catalog.json -OutputCsv .\.tmp\elftools-ldstr-catalog.csv
```

After the required SQLite catalog match step, use the generated DLL catalog to map
screenshot findings to DLL, type, method, token, and risk class before adding a
patch.

## Known Text Review Export

The generated catalog state store is ignored
`.cache\atg-catalog.sqlite`. It preserves every `SourceOccurrence`, groups
normalized text under `SemanticGroup`, and records `TranslationBinding` and
`Evidence` separately. Do not use Markdown or CSV as the mutable primary state
for new catalog tooling.

Query the primary store through the PowerShell 5.1-compatible CLI wrapper:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Invoke-AtGPatchCli.ps1 -Command catalog -CatalogAction search -CatalogText '<visible text>' -CatalogLimit 20
```

Use `-CatalogSource '<source fragment>'` to narrow a known assembly or file.
The workflow/agent context view is `docs\review\known-texts.md`; the human
spreadsheet view is `docs\review\known-texts.csv`. Regenerate the database and
both views with:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Export-KnownTextReview.ps1
```

The exporter prepares stable discovery caches under `docs\review\generated\`,
including static config candidates and UI/Common/Game/ElfTools `ldstr`
catalogs, imports all non-deduplicated occurrences into SQLite, then emits the
Markdown and CSV views. Do not depend on `.tmp` files for the committed review
outputs, and do not treat either generated view as mutable catalog state.

When a screenshot exposes English or a raw key, every workflow must first query
SQLite through `Invoke-AtGPatchCli.ps1` before direct source searches or patch
edits. Use `known-texts.md` afterward for surrounding source context and group
inspection. If the match points at a DLL source, use the exact generated
`ldstr` catalog value from
`docs\review\generated\*catalog*` for patching. Do not use normalized
`Original` text from `known-texts.md` or `known-texts.csv` as an IL rewrite
operand.

The default review outputs are intentionally not deduplicated. One row
represents one known source position or one patch-map record. The same English
text may appear many times with different method tokens, XML nodes, or patch
locators, and those rows must remain separate for review and future patch
selection. Use `-AggregateDuplicates` only for an ad-hoc compact view, not for
the committed review files.

For review, `ReviewState` replaces the older attempted/status/failure columns.
Allowed values are `Translated`, `NeedsTrial`, `Skipped`, `RecheckedSkipped`,
and `Rejected`. Use `Skipped` for skipped rows that have not been revisited in
the current review pass; use `RecheckedSkipped` for rows that were re-reviewed
and intentionally kept out of trial localization. `ReasonCode` is intentionally
coarse:
`TechnicalInternal`, `LogicSensitive`, `FragmentOrToken`, `OutOfScope`,
`PatchConflict`, or `RejectedByTest`. Keep detailed evidence and long failure
explanations in `docs\agent\trial-localization-state.json` or `Notes`, not in
the main review columns.

## DLL Patch Rules

- Prefer UI DLL rewrite entries in `hardcoded-ui-il-rewrite.json` for safe UI
  buttons, labels, and tooltip fragments. This dnlib path rewrites the `ldstr`
  instruction operand by `MethodToken + ILOffset + Original`, so translations
  do not need equal-length padding and do not need to fit the original `#US`
  heap entry.
- Rich tooltip links use `[display text|CONCEPT-KEY]`. Translate only the
  display text. The key must be registered by
  `AtTheGatesCommon.ns_UI.Concepts`; validate all rewritten maps with
  `tools\Test-ConceptLinkTargets.ps1` before building. A translated key that
  is not registered renders as raw markup or raises an `invalid CONCEPT` error
  instead of opening the next tooltip.
- Preserve raw runtime tags such as `[SETTLEMENT]`, `[FOOD]`,
  `[HUNTER:S]`, `[COLOR:*]`, `[FONT:*]`, `[HOTKEY:*]`, and `[BLANK-LINE]`.
  `tools\Test-RichTextTagPreservation.ps1` protects their structure. The
  shipped `[Upgrades|UPGRADES]` legacy alias must be written as
  `[升级|UPGRADE]`; `UPGRADES` is not a registered key. `RESPECT` and
  `RELATIONS` have no registered concepts, so render those two UI labels as
  ordinary Chinese instead of fabricated links.
- Do not trial-patch `AtTheGatesCommon.ns_Text.Text.ConvertTags`. The only
  reviewed display exception is its `[Ennoble]` alias, which must resolve as
  `[册封|NOBLE]` rather than a bare parser token.
- `tools\Build-IlRewritePatch.ps1` builds `tools\AtG.IlRewrite` with the
  repo-local `.tools\dotnet\dotnet.exe`, disables apphost generation, and runs
  `AtG.IlRewrite.dll`. Do not invoke `AtG.IlRewrite.exe`.
- `ElfTools.dll` can be patched only for scoped display strings with exact
  `MethodToken + ILOffset + Original` evidence. Current accepted classes are
  the nested hotkey tooltip in `ElfTools.Inputs.Hotkey.BuildTooltip`, generic
  collapsible-panel display tooltips in `ElfTools.Gui.CollapsibleContainer`,
  the dropdown prompt in `ElfTools.Gui.Dropdown`, and dialog hotkey labels in
  `ElfTools.Gui.TwoButtonDialog`. Do not treat this as permission to
  bulk-patch input handling, parser glue, diagnostics, or engine UI helpers.
- Keep `hardcoded-ui-il-strings.json` as the older in-place `#US` heap patch
  fallback. Its encoded translation must fit within the original user-string
  heap entry.
- Prefer complete UTF-16 string-boundary replacements.
- The translated string must not be longer than the original for byte fallback
  patches.
- Offset patches must verify both offset and original string per entry.
- Do not patch blindly from nearby bytes.
- Use byte patches in `hardcoded-strings.json` and verified offset patches as
  fallback for UI strings not migrated to IL rewrite. `Build-Patch.ps1` skips
  fallback entries already covered by the rewrite or in-place IL maps.
- Common DLL rewrite entries in `hardcoded-common-il-rewrite.json` are allowed
  only for scoped display strings with `MethodToken + ILOffset + Original`
  evidence and install/UI regression. Prefer them over Common byte fallback
  when equal-length padding would create visible spacing artifacts.
- Do not localize `AtTheGatesCommon.ns_GlobalSystems.UserSetting_*`
  description/comment strings through Common IL rewrite. These strings are
  serialized into `Settings\Settings.xml`; a 2026-07-02 trial with non-ASCII
  Chinese comments made the game show `Error Loading User Settings` on later
  launches. Leave them ASCII unless a separate XML-safe settings writer is
  implemented and regression-tested.
- Run `tools\Test-IlRewriteMapRisk.ps1` after adding IL rewrite entries. Short
  originals, whitespace fragments, punctuation fragments, and empty
  translations must carry `Safety` and `Note`; use `-Strict` when newly added
  risky entries also have `EvidenceScenario`.
- Keep `translations\hardcoded-common-offsets.json` disabled by default.
- `Build-Patch.ps1 -PatchCommonConceptTerms` is experimental and has caused
  initialization crashes.

## Known UI and Tooltip Sources

Main UI and notification fragments should use `hardcoded-ui-il-rewrite.json`
when a stable `MethodToken + ILOffset + Original` entry exists. Examples
include:

- `Settlement is Idle`
- `A Clan or your [SETTLEMENT] is idle.`
- `Click to see what `
- `Right-click to write a note to attach to this card.`
- Notification tooltip fragments such as `Click the Notification icon or `,
  `Click the Notification icon to cycle through them.`, and
  `Click the Notification icon to center the camera on it.`
- `AtTheGatesUI.ns_Notifications.Notification.GetEndTurnButtonLabel` contains
  display-only end-turn notification labels. The first trial fast-fail batch
  accepted `Give Leader Reply`, `Listen to Leader`, `Clan Has A Message`,
  `Visit Caravan`, `View Council`, and `Switch Disciplines` after new-game
  smoke; keep future entries scoped by token and offset.
- `AtTheGatesUI.HelpGuideTips.*` constructor titles and
  `HelpGuideTips.TipFromXML.Activate` prompt text are display-only UI strings.
  Help guide body content normally comes from `TEXT.Tip.*` in `English.xml`.
- `AtTheGatesUI.ns_InGame.ns_Popups.Popup_SystemMenu` contains safe scoped UI
  strings for labels, confirmation buttons, and save/load failure messages.
  Leave technical fragments such as version/date strings, save names, paths,
  and `MAP_SIZE_` identifiers untouched.
- `AtTheGatesUI.ns_InGame.SelectionPanel.AddButton_Pack` supplies the selected
  settlement/unit `Pack Up` command tooltip. Patch article and profession
  fragments here through exact UI IL rewrite entries; Chinese normally drops
  English articles such as `a` and should keep runtime tags like
  `[Profession|PROFESSION]`.
- `AtTheGatesUI.ns_InGame.SelectionPanel.AddLabel_Moves` supplies the selected
  unit/settlement movement tooltip. `TEXT.Name.Terrain.*:SINGULAR/PLURAL`
  aliases must exist because fragments such as `[MARSH:S]` resolve through
  terrain text keys.
- `AtTheGatesUI.ns_InGame.SelectionPanel.AddButton_SkipTurn` supplies selected
  unit/settlement skip-command tooltips. Keep `[SETTLEMENT]` as a runtime token
  instead of rewriting it to `[定居点|SETTLEMENT]`.
- `AtTheGatesGame.ns_GameCode.ResourcesMgr.RecalcPerTurnBase` supplies resource
  tooltip stockpile/production/consumption lines. A scoped `s` suffix after
  localized consumer names should translate to an empty string because Chinese
  has no plural suffix.

Clan-card tooltip labels and concept fragments use Common display patches.
Prefer `hardcoded-common-il-rewrite.json` for scoped strings and
`hardcoded-common-strings.json` only as fallback. Examples include:

- `Profession: `
- `Click to see what [Professions|PROFESSION] [Clan|CLAN] `
- ` can be [Trained|TRAIN] in.`
- `: NONE`, `:    NONE`, `:      NONE`
- `[Discipline|DISCIPLINE]`, `[Family|FAMILY]`, `[Turns|TURN]`
- `[Ennoble]`, `[Ennoble|NOBLE]`, and `[Ennobled|NOBLE]` display text,
  with the `NOBLE` concept identifier preserved.

Clan-screen action availability failures can come from the game EXE static
check methods rather than UI/Common DLLs. Use
`hardcoded-game-il-rewrite.json` only for scoped display fragments in
`AtTheGatesGame.ns_GameCode.ns_StaticChecks.*.PerformCheck`, such as
`You lack sufficient `, ` (`, ` (need `, ` more needed).`, and ` more).`.
These fragments are visible in action-button tooltips such as ennoble clan,
increase clan limit, and declare kingdom. Do not treat this as permission to
bulk-patch gameplay EXE text.

Knowledge-screen tooltip sources:

- `Content\Config\Primary\Techs.xml` discipline wrapper descriptions come from
  `source\Content\Config\Primary\Techs.original.xml` and are patched through
  `translations\config-node-extra-strings.json`.
- `TEXT.Name.Deposit.*:SINGULAR/PLURAL` aliases are generated by
  `tools\Build-ChineseXml.ps1`; missing aliases expose raw deposit keys in
  profession/upgrade tooltips.
- `AtTheGatesCommon.ns_Properties.PropertyBlueprint.BuildDetailsString`
  provides common property/upgrade tooltip fragments such as `Spend `,
  `Provides `, `Additional `, and ` per [Turn|TURN]`.
- `AtTheGatesCommon.ns_Config.GAME.BuildDescription_Abilities`,
  `BuildDescription_Production`, `BuildDescription_Consumption`, and
  `BuildDescription_Families` provide generated config description fragments
  for abilities, production, consumption, and family bonuses. Patch only
  scoped display fragments with exact catalog values; do not patch structural
  suffix fragments such as `:SINGULAR]`, raw deposit-key builders, or parser
  glue.
- `AtTheGatesCommon.ns_Config.Condition.ToString_Custom` and
  `Weight_BasicCondition.ToString` contain condition display fragments.
  Several originals include trailing spaces even when the review CSV hides
  them; use the DLL catalog `Value` exactly.
- `AtTheGatesCommon.ns_Text.Text.BuildCommaSeparatedListOfStrings` and
  `BuildCommaSeparatedListOfNames` provide display-only list conjunctions used
  by knowledge-screen prerequisites. Patch exact ` and ` / ` or ` entries by
  token and offset; do not treat this as permission to localize parser,
  formatter, or diagnostic text.
- `AtTheGatesCommon.ns_UI.ns_Tooltips.ProfessionTooltip.BuildTooltip` provides
  profession status labels such as `Cannot ` and ` Right Now`.
  It also contains method-scoped profession-tooltip help fragments such as
  portrait, description, structures, upgrades, training cost, and training-time
  explanatory text. Patch these through `hardcoded-common-il-rewrite.json`
  when exact catalog evidence exists.
- Large knowledge-screen profession detail panels can use game EXE static
  checks rather than Common tooltip code for status lines. `Check_CanEverResearch`
  assembles `Cannot ` + `[Study|STUDY]` + `.`, and
  `Check_DoesntAlreadyHaveTech` assembles `Already ` + `[Learned|LEARN]` + `.`.
  Patch these only through `hardcoded-game-il-rewrite.json` with exact
  `MethodToken + ILOffset + Original` evidence; do not retranslate the
  `[Study|STUDY]` or `[Learned|LEARN]` concept display tags when they are
  already localized.
- `AtTheGatesCommon.ns_UI.Concepts` `LEARN` display strings are safe only when
  patched as display tags (`[Learn|LEARN]`, `[Learning|LEARN]`,
  `[Learned|LEARN]`) while leaving the `LEARN` identifier unchanged.
- `AtTheGatesUI.ns_InGame.ns_Popups.ProfessionButton.BuildIconsPanel`
  supplies the knowledge-screen icon prefix `Can Identify `. Patch it through
  `hardcoded-ui-il-rewrite.json`; it pairs with localized Common concept
  display strings for `[Unidentified Deposit|UNIDENTIFIED]` and
  `[Unidentified Deposits|UNIDENTIFIED]`.
- `AtTheGatesCommon.ns_UI.Concepts` display strings for knowledge and upgrade
  tooltips currently include scoped IL rewrites for `[Power|POWER]`,
  `[Attack Power|ATTACK]`, `[Deposit|DEPOSIT]`, `[Plant|PLANT]`,
  `[Mineral|MINERAL]`, `[Animal|ANIMAL]`, `[Produce|PRODUCE]`,
  `[Produces|PRODUCE]`, and `[Producing|PRODUCE]`. Leave the concept IDs after
  the pipe unchanged.
- 2026-07-01 and 2026-07-02 trial batches also accepted additional
  `AtTheGatesCommon.ns_UI.Concepts` display tags and help bodies for stored
  food turns, terrain, structures, professions, movement, defense,
  disciplines, training, terrain/weather, units, structures, deposits,
  profession categories, ennobling, clan traits, mood, movement, vision,
  borders/control, supply, health, combat experience, diplomacy, resources,
  stockpiles, starvation, tech/training/upgrade explanations, combat offense
  and defense fragments, morale/retreat fragments, clan limit, construction,
  foraging, encamping, fortifying, deposits, and declaring a kingdom.
  These are still smoke-proven only; targeted hover/UI coverage is required
  before marking the corresponding visible help screens fully verified.
- `AtTheGatesUI.ns_InGame.WorldScreen.CreateButtons` supplies the main-loop
  top-left system menu tooltip `[HOTKEY:Esc] Open up the System Menu...`; patch
  it through `hardcoded-ui-il-rewrite.json`.
- `ElfTools.Inputs.Hotkey.BuildTooltip` supplies the second-level tooltip that
  appears when hovering `[HOTKEY:*]` tokens inside another tooltip. Patch the
  two fragments `This action can be performed by pressing` and
  `on your keyboard.` through `hardcoded-elftools-il-rewrite.json`; verified
  text should read like `按下 [F11] 即可执行此操作。`.
- `ElfTools.Gui.CollapsibleContainer.Init`,
  `ElfTools.Gui.Dropdown..ctor`, and
  `ElfTools.Gui.TwoButtonDialog.Initialize` contain generic UI helper
  tooltips/prompts. The 2026-07-03 ElfTools discovery exported 811 `ldstr`
  records; only 8 display entries from these helper classes were trialed and
  accepted by smoke. The remaining 394 review rows were marked
  `SkippedByPolicy` as engine/helper diagnostics, parser tokens, resource IDs,
  hotkey labels, or internal exception text.
- `AtTheGatesUI.ns_InGame.ns_Popups.Screen_Diplomacy.CreateControls_Fixed`
  supplies diplomacy-screen labels and tooltip prose such as relationship
  level, influence, reputation, leverage, alliance, war, emissary, and gift
  actions. Patch these through `hardcoded-ui-il-rewrite.json` by exact
  `MethodToken + ILOffset + Original`.
- `AtTheGatesUI.ns_InGame.ns_Popups.ClanListEntry.BuildPanel_TitleRowContents`
  supplies clan-list header labels and their first-level header tooltips. The
  currently tracked header points are clan name, portrait, profession,
  discipline/level, families, supply, damage, upgrades, mood, command, and
  distance. Patch these through `hardcoded-ui-il-rewrite.json` by exact
  `MethodToken + ILOffset + Original`.

Selected map-object and structure descriptions:

- The selected settlement information panel uses
  `Content\Config\OnMap\Structures.xml` (`STRUCTURE_SETTLEMENT`) and is patched
  through `translations\config-node-onmap-strings.json`.

Battle preview and combat result text:

- `AtTheGatesCommon.ns_Utilities.BattleProjection.BuildSummary` and
  `BattleProjection.ToString` provide battle result summary sentences and
  attacker/defender labels. Patch scoped display fragments through
  `hardcoded-common-il-rewrite.json`; do not treat nearby pathfinding,
  random-seed, or debug diagnostic strings as user-facing combat text.

Verified UI DLL offset patches:

- Offset `488569`, original ` can be `, translation `可`
- Offset `488587`, original ` in.`, translation `。`
- Offset `490295`, original `Leave`, translation `离开`

These offsets exist because complete-boundary replacement did not affect the
visible clan-card action sentence.

Do not add a UI IL rewrite for `AtTheGatesUI.ns_InGame.ClanCard.AddActionButton`
`0x06000125` / `ILOffset=1774` / original `Leave ` while offset `490295`
remains active. The 2026-06-30 trial batch rejected this entry at build time
because the IL rewrite changed the bytes that the verified offset fallback
expects to find. Migrate or remove the offset fallback first if this string is
handled again.

Legacy in-place UI IL pilot entry, superseded by `hardcoded-ui-il-rewrite.json`:

- `Settlement is Idle` -> `定居点空闲`

Live DLL regression checks:

- `tools\Test-HoverLocalizationRegressions.ps1` checks live `ldstr` catalog
  values for managed DLLs, not raw metadata bytes, because dnlib rewrites can
  leave unreferenced old user strings in DLL metadata.

## Trial Fast-Fail Status

Use `docs/agent/trial-localization-state.json` as the machine-readable state
for exploratory batches, accepted/rejected counts, rejected single entries,
catalog precision failures, latest smoke evidence, and next-batch guidance.
Keep this section limited to stable source-safety rules.

- A trial pass proves build, install, startup, and the trial runner's explicit
  `-IncludeNewGame` smoke safety. It does not prove wording, layout, hover
  coverage, fixed-save loading, or all UI paths.
- Do not use lack of UI screenshots, targeted visual evidence, or targeted
  regression evidence as a reason to mark discovered display text
  `SkippedByPolicy`. Mark those rows `TrialCandidate` and probe them in small
  fast-fail batches.
- Keep `SkippedByPolicy` for technical/internal text, semantic-free grammar
  glue, date/season logic, external online flows, raw IDs, paths, pure
  formatter tags such as `[HILL]` / `[HILL:S]`, parser match tokens such as
  `AtTheGatesCommon.ns_Text.Text.ConvertTags`, and static config candidates
  explicitly classified as unsafe.
- Trial batch input is rejected when it targets
  `AtTheGatesCommon.ns_Text.Text.ConvertTags`, contains bracket-only
  parser-like tokens, or contains `U+FFFD` replacement characters. Existing
  manually reviewed exceptions in rewrite maps must stay explicit and should
  not be expanded by Spark or other mechanical trial passes.
- Trial batch input is also rejected for
  `AtTheGatesCommon.ns_GlobalSystems.UserSetting_*` descriptions/comments and
  `AtTheGatesGame.DebugConsoleNS.DebugConsole` command/help text. The former
  can pollute `Settings.xml`; the latter is internal tooling text, not normal
  player-facing UI.
- Rewrite maps must contain only baseline entries or entries accepted by the
  trial runner and recorded in `trial-localization-state.json`. Do not keep
  rejected, invalid-smoke, or manually copied batch leftovers in normal maps.
- Batch files under `translations\trial-*.json` are historical inputs and
  evidence. Keep them until their accepted/rejected state is reflected in both
  `docs/agent/trial-localization-state.json` and
  `docs/review/known-texts.csv`.
- The remaining DLL count still contains false positives such as debug console
  strings, control IDs, date/month helpers, long concept help bodies,
  technical labels, punctuation fragments, paths, and raw key references.
  Filter these before generating exploratory batches.

## Sensitive Text Classes

Treat these as logic-sensitive unless an isolated build/install/startup
regression proves the change is safe:

- Faction names and faction labels from `Factions.original.xml`
- Date banner season/month/year text
- `Clan <Name>` notification prefixes
- Broad Common concept terms such as `Turn` and similar core glossary entries
- Common concept identifiers such as `LEARN`, even when their display tags are
  patched

Generated names, technical markers, and other acceptable English remnants are
tracked in `translation-style.md`.
