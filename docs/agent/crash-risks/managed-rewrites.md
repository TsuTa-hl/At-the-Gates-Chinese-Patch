# Managed Rewrite and Logic Risks

Read when changing any managed DLL/EXE rewrite, rich-text concept behavior, or
logic-sensitive display term.

## Common and Concept Terms

- Leave `translations\\hardcoded-common-offsets.json` and
  `Build-Patch.ps1 -PatchCommonConceptTerms` disabled by default.
- Broad Common concept replacements, including a direct `Turn` replacement,
  have caused startup failures even when their byte match was exact.
- For phrases such as `Cannot Learn Right Now`, keep the concept identifier
  unchanged and use a scoped dnlib display rewrite in
  `hardcoded-common-il-rewrite.json`; do not rewrite raw concept IDs or broad
  metadata offsets.

## UI DLL

- `Build-IlRewritePatch.ps1` is the preferred UI path: dnlib rewrites `ldstr`
  by `MethodToken + ILOffset + Original`, avoiding padding.
- Run the rewriter as `AtG.IlRewrite.dll` through `.tools\\dotnet\\dotnet.exe`.
  Do not invoke `AtG.IlRewrite.exe`; systems without a global .NET runtime can
  show an application-error dialog. `UseAppHost` stays false.
- The old `Build-IlStringPatch.ps1` `#US` fallback may only write a translation
  that fits the original heap entry.
- `Text.HumanReadableMod` (`0x06000207`) has one approved structural display
  operation, `HumanReadableModDynamicPercent`, at the dynamic `x` suffix
  (`IL_0164`). The source argument is already an integer percentage; the
  operation removes only the decimal-multiplier formatting and preserves the
  original value before appending `%`. Keep this operation scoped to that
  method and anchor; do not generalize it to arbitrary numeric strings.
- Keep byte/offset fallbacks until each migrated string has build, install,
  smoke, and target-UI coverage. Do not rewrite `ClanCard.AddActionButton`
  `Leave ` while its verified offset fallback still expects that original text.

## Game and ElfTools

- Game EXE rewrites are restricted to display-only `ldstr` fragments, currently
  static resource-requirement text in action-button tooltips. Every new entry
  needs fixed-save load and target UI coverage as well as smoke.
- ElfTools rewrites are restricted to display helpers such as hotkey tooltips,
  collapsible containers, dropdowns, and two-button dialogs. Do not broadly
  rewrite input handling, parser glue, diagnostics, resource IDs, or engine
  helpers.

## Logic-Sensitive Text

Treat faction names, date-banner terms, `Clan <Name>` notification prefixes,
and Common concept terms as unsafe for bulk replacement. Patch only in small
isolated changes with build, install, startup, and target-UI regression; roll
back immediately if navigation or startup fails.

The RXL-CQW knowledge countdown is a method-scoped Common rewrite at
`GAME.BuildDescription_Abilities` (`0x06001724`, IL_042C / offset 1068), not a
global `in` replacement. It renders the standalone connector as `，还需` while
preserving the remaining-turn value and profession links. The companion
`Innate` and ` Trait` fragments are scoped to the property-details/runtime
display paths. Current fixed-save evidence covers the visible and twice-scrolled
profession cards, including Explorer's former `Attack` fragment.

The 2026-08-01 crash after selecting a new-game tribe was traced to
`Screen_ChooseFaction.Update`: it calls `button.Text.Substring(4)` and
prepends `FACTION_`. Therefore the ten playable faction `<name>` and `city/name`
config values must remain their original logic strings; their visible Chinese
forms belong to the runtime display map. Neutral duplicate-name entries may be
translated only through their indexed source list, not by changing playable
faction identifiers.

## 2026-08-06: Complete uninstall recovery for faction and runtime artifacts

The reported post-uninstall diplomacy crash included the residual Chinese
卡尔皮人. The catalog locates The Carpi both in the neutral duplicate-name
list of Factions.xml and in the display-safe runtime map. The generated patch
therefore changes both a logic-adjacent XML file and runtime-only artifacts.
The former uninstall implementation trusted only manifest.Files, with no
backup-inventory recovery, patch-only fallback, or post-restore hash check. A
stale or incomplete manifest could consequently leave a translated
Factions.xml, AtG.RuntimeText.dll, or AtG.RuntimeText.tsv behind.

Schema-2 installation now backs up and hashes every file in the generated
patch tree, writes a Prepared manifest before the first copy, verifies each
installed hash, and only then marks it Installed. Uninstall merges the
manifest with every file in the original-backup tree and known runtime-only
artifacts, verifies each restored hash or removal, and removes its manifest
only after that succeeds. Test-PatchUninstallCompleteness.ps1 dynamically
enumerates the entire current patch tree, so later patch outputs are covered
without a hand-maintained file list.

The fake-game test passed for all 58 current patch files and for a simulated
legacy manifest omitting AtTheGatesCommon.dll, AtG.RuntimeText.dll, and
the runtime TSV. A live direct-uninstall verification restored 49 original
backup files and removed 43 patch-only files; Factions.xml contained
The Carpi, while the runtime DLL and TSV were absent. The unpatched
main-menu smoke reached a stable window in 7.74 seconds and held it for
4.16 seconds without a crash, settings error, or Windows error. A second live
schema-2 uninstall/reinstall round trip repeated the 49 restored and 43 removed
artifacts before rebuilding the complete 58-file manifest. Its final patched
main-menu smoke reached 7.70 seconds plus 4.12 seconds with the same clean
result. Neither smoke entered a save or the diplomacy panel.

The 2026-08-02 CLR `InvalidProgramException` at the profession screen was
caused by the first `HumanReadableModDynamicPercent` rewrite removing the
original `ldarg.1` that preceded the retained `%` string-concat suffix. The
resulting `String.Concat(string,string)` had only one stack argument. The
operation now restores that receiver explicitly and fails the build if the
suffix is not still preceded by `ldarg.1`; the managed-rewrite cache version was
bumped before rebuilding. Final patched and installed `AtTheGatesCommon.dll`
have identical SHA-256 hashes, and static IL shows the valid sequence
`ldarg.1; ldstr %; call String.Concat(string,string)`. Main-menu smoke passed
without a new crash log or Windows error. The designated fixed-save profession
replay was attempted but stopped before any click because the input driver
returned `SetCursorPos failed`; this is an automation limitation, not a game
crash, so visual profession-screen verification remains pending.
