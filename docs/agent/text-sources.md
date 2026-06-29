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
- `source\Content\Config\Primary\ClanTraits.original.xml` ->
  `translations\config-node-strings.json` and
  `translations\config-node-extra-strings.json`
- `source\Content\Config\Primary\Techs.original.xml` ->
  `translations\config-node-extra-strings.json`
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
  - `TEXT.Name.Deposit.*:SINGULAR`
  - `TEXT.Name.Deposit.*:PLURAL`

## Static Discovery

When new English text is found, first run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Export-StaticTextCandidates.ps1
```

Only auto-patch strings classified as `SafeDisplay` with stable `ID`, `XPath`,
or `Index` metadata. Current static-candidate status:

- `ClanTraits.xml` `SafeDisplay` entries are covered.
- Remaining candidates are mostly `Factions.original.xml` `ManualOnly` faction
  names or labels and must not be force-patched by default.

For DLL strings, export a method-level `ldstr` catalog before byte searching:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Export-DllLdstrCatalog.ps1 -DllPath .\source\AtTheGatesUI.original.dll -OutputJson .\.tmp\ui-ldstr-catalog.json -OutputCsv .\.tmp\ui-ldstr-catalog.csv
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Export-DllLdstrCatalog.ps1 -DllPath .\source\AtTheGatesCommon.original.dll -OutputJson .\.tmp\common-ldstr-catalog.json -OutputCsv .\.tmp\common-ldstr-catalog.csv
```

Use the catalog to map screenshot findings to DLL, type, method, token, and
risk class before adding a patch.

## DLL Patch Rules

- Prefer UI DLL rewrite entries in `hardcoded-ui-il-rewrite.json` for safe UI
  buttons, labels, and tooltip fragments. This dnlib path rewrites the `ldstr`
  instruction operand by `MethodToken + ILOffset + Original`, so translations
  do not need equal-length padding and do not need to fit the original `#US`
  heap entry.
- `tools\Build-IlRewritePatch.ps1` builds `tools\AtG.IlRewrite` with the
  repo-local `.tools\dotnet\dotnet.exe`, disables apphost generation, and runs
  `AtG.IlRewrite.dll`. Do not invoke `AtG.IlRewrite.exe`.
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
- `AtTheGatesCommon.ns_UI.ns_Tooltips.ProfessionTooltip.BuildTooltip` provides
  profession status labels such as `Cannot ` and ` Right Now`.
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
- `AtTheGatesUI.ns_InGame.WorldScreen.CreateButtons` supplies the main-loop
  top-left system menu tooltip `[HOTKEY:Esc] Open up the System Menu...`; patch
  it through `hardcoded-ui-il-rewrite.json`.

Verified UI DLL offset patches:

- Offset `488569`, original ` can be `, translation `可`
- Offset `488587`, original ` in.`, translation `。`
- Offset `490295`, original `Leave`, translation `离开`

These offsets exist because complete-boundary replacement did not affect the
visible clan-card action sentence.

Legacy in-place UI IL pilot entry, superseded by `hardcoded-ui-il-rewrite.json`:

- `Settlement is Idle` -> `定居点空闲`

Live DLL regression checks:

- `tools\Test-HoverLocalizationRegressions.ps1` checks live `ldstr` catalog
  values for managed DLLs, not raw metadata bytes, because dnlib rewrites can
  leave unreferenced old user strings in DLL metadata.

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
