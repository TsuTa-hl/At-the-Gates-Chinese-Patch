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

## Fonts and Icons

- Fonts must be merged fonts that preserve original SpriteFont glyphs and icon
  glyphs, then append Chinese glyphs.
- Install only generated fonts with
  `patch\Content\Images\Interface\Components\Fonts\.atg-merged-fonts`.
- Old Chinese-only fonts caused resource icons, buttons, and trait icons to
  become letters or squares.
- Generating the full Chinese glyph set into all 38 SpriteFonts caused a
  32-bit XNA `System.OutOfMemoryException` during new-game map generation,
  while loading textures for generated units/boats.
- A later save-load OOM was observed in
  `AtTheGatesGame.ns_Map.ATGTile.RefreshVisibilityCost()` while loading map
  data. Treat it as the same 32-bit memory-pressure class unless new evidence
  points elsewhere.
- `tools\Build-Patch.ps1` must only override the runtime-referenced font
  subset currently used by the patch. Large UI fonts use a smaller UI-display
  glyph subset instead of the full Chinese corpus. The font marker is
  `merged-fonts-v3-large-ui-subset`.
- Run `tools\Test-FontPatchBudget.ps1` after font or translation charset
changes. Current budget: 17 patched SpriteFonts and total patched font bytes
under 120 MB. Latest verified build: 121,292,744 bytes, below the 120 MiB
binary budget of 125,829,120 bytes.
- Latest Quicksave load regression after the v3 font subset kept the game
  alive and did not update `Crash.AtGLog`; keep fixed-save load testing in
  black-box cycles that touch fonts or large text corpora.

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

## Logic-Sensitive Text

Treat these as unsafe for broad replacement:

- Faction names
- Date banner terms
- `Clan <Name>` notification prefixes
- Common concept terms

Patch them only in small isolated changes with build, install, startup, and
targeted UI regression. Revert immediately if startup or UI navigation fails.
