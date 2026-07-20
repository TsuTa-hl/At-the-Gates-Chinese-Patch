# Crash Risks and Required Workarounds

Use this guide before touching XML output, fonts, ClanCard assets, Common DLL
terms, faction names, dates, or game launch behavior.

## Startup and XML

- `English.xml` with an XML declaration crashes during startup:

  ```text
  FOUND: <xml> ... EXPECTED: Start of a new block
  ```

- `tools\Build-ChineseXml.ps1` must keep `OmitXmlDeclaration = true`.
- The first line of `patch\Content\Text\English.xml` must be `<english>`.
- A silent startup exit can bypass the game's `HE'S DEAD, JIM` dialog and leave
  `Crash.AtGLog` unchanged. A Windows Application log event with
  `At The Gates.exe`, `clr.dll`, and exception code `c00000fd` was observed on
  2026-06-30 before later smoke runs passed. Treat Windows Error Reporting and
  `.NET Runtime` events as authoritative evidence for this class of failure.
- The 2026-06-30 review-continuation trial build also hit one new-game smoke
  WER `c00000fd` exit during map generation (`NewGameReady=False`,
  `CrashLogUpdated=False`), then passed the next two new-game smoke runs. Treat
  this as intermittent unless a batch fails repeatedly or the same seed/path
  becomes reproducible.
- The 2026-07-02 `trial-common-concepts-help-17` batch also hit one
  `c00000fd` WER before bisection and final accepted-only smoke both passed.
  Treat isolated WERs of this class as retryable evidence, not immediate
  rejection of all texts in the batch.
- On 2026-07-01, `trial-common-game-description-1` isolated one
  `StackOverflowException`/WER smoke failure for `Each additional Family
  provides a`, but the same entry passed in
  `trial-common-game-description-retry-1`. Treat single new-game WER failures
  in trial localization as retryable evidence before marking the text unsafe.
- On 2026-07-02, translating
  `AtTheGatesCommon.ns_GlobalSystems.UserSetting_WindowedMode` description and
  warning strings caused the game to write non-ASCII comments into
  `Settings\Settings.xml`. Later launches showed `Error Loading User Settings`
  and the program log reported `Settings.xml` invalid characters at line 27.
  Restore the setting comment to ASCII and keep all `UserSetting_*`
  descriptions out of trial localization unless a separate XML-safe settings
  serialization fix exists.
- On 2026-07-05, a Spark recheck left additional `UserSetting_*` trial entries
  in the normal Common rewrite map. The installed build polluted
  `Settings\Settings.xml` comment lines 108, 150, 170, 201, and 482; smoke tests
  showed `Error Loading User Settings` until those comments were restored to
  ASCII. `tools\Test-GameLaunch.ps1` now reports `SettingsErrorSeen`; any true
  value is a smoke failure and must be handled before evaluating unrelated text
  candidates.

## Launch Working Directory

Starting `At The Gates.exe` without setting the working directory can trigger an
`AtTheGatesCommon.ns_GlobalSystems.Log` initializer crash. Use the launch
command in `docs/agent/operations.md`.

## ClanCard Asset Aliases

Translated discipline names can be used by the game as ClanCard asset path
components, for example:

```text
Images\Interface\ScreenSpecific\ClanCard\冶金\PortraitBackground_2
```

Keep the ClanCard Chinese alias directory copy logic in `tools\Build-Patch.ps1`.
Do not remove these generated patch directories:

- `patch\Content\Images\Interface\ScreenSpecific\ClanCard\农耕`
- `patch\Content\Images\Interface\ScreenSpecific\ClanCard\冶金`
- `patch\Content\Images\Interface\ScreenSpecific\ClanCard\工艺`
- `patch\Content\Images\Interface\ScreenSpecific\ClanCard\探索`
- `patch\Content\Images\Interface\ScreenSpecific\ClanCard\畜牧`
- `patch\Content\Images\Interface\ScreenSpecific\ClanCard\荣誉`

Removing these aliases can crash the clan screen with a missing
`PortraitBackground_*.xnb` file.

When adding PowerShell checks for these generated Chinese paths, avoid raw
non-ASCII path literals in scripts that may run under Windows PowerShell's ANSI
fallback decoding. Build the Chinese path component from Unicode code points or
derive it from the generated directory list, then verify the resulting report
field against `Test-Path`.

## Fonts and Icons

- The default renderer mode is now `DynamicCjk`. It keeps the game's original
  SpriteFonts for Latin text, numbers, and private-use icon glyphs, and routes
  CJK glyphs through `AtG.RuntimeText.dll` and two bundled OFL Noto Sans SC
  font files under `patch\Content\Fonts`.
- A `DynamicCjk` build must contain `patch\AtG.RuntimeText.dll`, the two
  bundled font files, and zero generated merged-font XNB files. It does not use
  `.atg-merged-fonts`; that marker belongs only to the rollback renderer.
- The shared runtime CJK atlas is limited to eight 1024x1024 RGBA pages, or
  32 MiB. When a glyph cannot be allocated or rendered, RuntimeText records a
  diagnostic/fallback event instead of sending that CJK character to
  `SpriteFont.GetIndexForCharacter` and crashing on a missing XNB glyph.
- The 2026-07-14 verified `DynamicCjk` build bundles 33,443,913 bytes of font
  files, redirects 145 runtime calls, and generates no Chinese SpriteFont XNB
  files. Run `tools\Test-FontPatchBudget.ps1` and
  `tools\Test-RuntimeBuildReport.ps1` after renderer, font, or translation
  changes.
- The 2026-07-16 visual calibration rasterizes CJK at 1.15 times the logical
  SpriteFont size and applies a small per-size upward baseline offset. Keep
  measurement, line height, glyph cache keys, and drawing on the same calibrated
  descriptor; changing only drawing or only measurement can reintroduce
  clipping, incorrect centering, or text that sits too low.
- The scale and baseline adjustment apply only to dynamic CJK glyphs. Do not
  apply them to the original SpriteFont path: Latin text, numbers, hotkeys, and
  private-use icon glyphs depend on the original metrics.
- `MergedFonts` remains a rollback-only mode for one compatibility cycle. In
  that mode only, install fonts carrying `.atg-merged-fonts`; preserve original
  icon glyphs and use the 15 Segoe UI subset build. Never restore the older
  38-font full-corpus build, which caused 32-bit XNA memory exhaustion.
- The rollback subsets must still cover all IL rewrite text,
  `TEXT.Description.*`, and config-node `Nodes.Value` strings. Earlier subset
  omissions crashed on glyphs such as `肃` and `哈`; this is one reason
  `DynamicCjk` is now the default.
- Run `tools\Test-FontReferences.ps1` after changing font references or either
  renderer path. Latin/icon rendering must continue to use the original game
  SpriteFonts so resource and trait icons do not become letters or squares.

## Religion Configuration

- Religion `name` and `adjective` fields are safe display text when patched by
  stable religion ID. Keep `RELIGION_*` IDs unchanged and leave `description`
  placeholders unchanged unless a separate source and UI regression prove the
  field is display-safe.
- The 2026-07-18 Religion-screen patch loaded the current fixed save and opened
  the screen without a crash or new `Crash.AtGLog` entry. DynamicCjk handled the
  Chinese glyphs; no merged-font fallback was needed.

## In-Game Reload Memory Lifecycle

- The 32-bit game previously threw `System.OutOfMemoryException` while loading
  a save from an already running main loop. Observed stacks included
  `MapObjectContainer.NEW`, `ATGTile.LoadTerrainLevelData`, and
  `SpriteSheet.LoadSprite`; these are memory-pressure symptoms rather than
  proof that the failing allocation itself owns the leak.
- `tools\Build-GameLoadMemoryPatch.ps1` must keep the generated game EXE Large
  Address Aware. Before reconstructing a loaded world, the lifecycle patch
  disposes the previous world SpriteBatch, clears known static world roots,
  and performs a forced collection at the verified load boundary.
- `ElfTools.Graphics.IdSpriteBatch.Dispose(bool)` may dispose its owned index
  buffer, but must not dispose the shared `_defaultEffect`. Disposing that
  shared effect breaks later SpriteBatch instances and is guarded by
  `tools\Test-GameLoadMemoryPatch.ps1` and the .NET patch tests.
- Final patched Game/ElfTools outputs can remain memory-mapped briefly after
  verification. Use `Copy-AtGFileIfChanged` from `tools\AtGFileOps.ps1`; do
  not replace its bounded retry with a raw `Copy-Item`.
- Latest regression evidence: on 2026-07-14 the fixed save
  `v1.4.1   World [BVT-LCL]   游戏开始.AtGSave` loaded from the main menu and
  then reloaded five times through the in-game pause menu in one process.
  `Crash.AtGLog` did not change, handle count returned to 703, and private
  bytes stabilized near 1.39 GiB after the first reload instead of increasing
  monotonically. Evidence is under
  `.tmp\runs\20260714-load-reload-memory-lifecycle-v4`.

## Common DLL and Concept Terms

- Do not enable `translations\hardcoded-common-offsets.json` by default.
- Do not enable `Build-Patch.ps1 -PatchCommonConceptTerms` by default.
- Direct Common concept replacements have caused startup crashes.
- A direct `Turn` replacement at offset `933116` matched the source text but
  still caused a startup crash.
- `Cannot Learn Right Now` is assembled from Common display fragments and the
  `LEARN` concept display tag. The current safe path is scoped dnlib rewrite in
  `translations\hardcoded-common-il-rewrite.json`, leaving the `LEARN`
  identifier unchanged and patching only display strings. Do not replace broad
  Common concept identifiers or raw metadata offsets to fix this phrase.

## UI IL String Patches

- `tools\Build-IlRewritePatch.ps1` is the preferred UI DLL path. It uses
  dnlib to rewrite `ldstr` operands in `AtTheGatesUI.dll` by
  `MethodToken + ILOffset + Original`, so UI translations do not need padding.
- The rewriter must run as `AtG.IlRewrite.dll` through
  `.tools\dotnet\dotnet.exe`. Do not run `AtG.IlRewrite.exe`; direct apphost
  execution can fail when no system-level .NET runtime is installed and may
  show a Windows application-error dialog.
- `tools\AtG.IlRewrite\AtG.IlRewrite.csproj` must keep
  `<UseAppHost>false</UseAppHost>`. `tools\Test-OptimizationTooling.ps1`
  verifies that no `AtG.IlRewrite.exe` remains after the tool build.
- `tools\Build-IlStringPatch.ps1` is the older in-place `#US` heap fallback.
  Its translation must fit in the original heap entry. If it does not, the
  patch must fail rather than overwrite adjacent metadata.
- Use UI DLL patches first. Do not use this as a reason to broadly patch
  Common concept terms.
- Keep byte and offset fallback paths available until each migrated UI string
  has build, install, smoke, and targeted UI coverage.
- Some UI strings are still coupled to verified offset fallbacks. In particular,
  do not IL-rewrite `ClanCard.AddActionButton` original `Leave ` at
  `0x06000125` / `ILOffset=1774` while UI offset `490295` still expects
  original `Leave`; the 2026-06-30 fast-fail batch rejected that entry during
  build.

## Game EXE IL String Patches

- `tools\Build-Patch.ps1` may patch `source\AtTheGatesGame.original.exe`
  through `translations\hardcoded-game-il-rewrite.json` and install the result
  as `patch\At The Gates.exe`.
- Keep EXE patches narrowly scoped to display-only `ldstr` fragments with
  `MethodToken + ILOffset + Original` evidence. The current safe class is
  `AtTheGatesGame.ns_GameCode.ns_StaticChecks.*.PerformCheck` resource
  requirement text shown in action-button tooltips.
- Do not broadly patch gameplay EXE strings. Every new EXE patch requires
  build, install, smoke, fixed-save load, and the targeted UI regression that
  exposes the string.

## ElfTools IL String Patches

- `tools\Build-Patch.ps1` may patch `source\ElfTools.original.dll` through
  `translations\hardcoded-elftools-il-rewrite.json` and install the result as
  `patch\ElfTools.dll`.
- Keep ElfTools patches narrowly scoped to display-only helper text with
  `MethodToken + ILOffset + Original` evidence. Current smoke-accepted
  classes are `ElfTools.Inputs.Hotkey.BuildTooltip`,
  `ElfTools.Gui.CollapsibleContainer.Init`, `ElfTools.Gui.Dropdown..ctor`, and
  `ElfTools.Gui.TwoButtonDialog.Initialize`.
- Do not broadly patch input handling, parser glue, diagnostics, resource IDs,
  exception text, or other ElfTools engine helpers without an isolated build,
  install, smoke, and targeted UI regression.

## Logic-Sensitive Text

Treat these as unsafe for broad replacement:

- Faction names
- Date banner terms
- `Clan <Name>` notification prefixes
- Common concept terms

Patch them only in small isolated changes with build, install, startup, and
targeted UI regression. Revert immediately if startup or UI navigation fails.
