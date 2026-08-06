# Clan Training Connector Audit

## 2026-08-05 precise discipline-popup correction

The later user capture is not the previously repaired
`Popup_ChooseClanToTrain` title. It is the separate
`Popup_ChooseDisciplineToLevelUp` popup, so the former scoped ` in ` rewrite
at `0x06000504` cannot reach it. The exact source inventory is now:

- `CreateControls_Fixed` (`0x0600051f`, `IL_000F`): title connector ` in ` ->
  `：`, producing `训练：纪律`.
- `BuildTooltip_Cost` (`0x06000522`, `IL_0098` and `IL_04C8`): each tooltip
  connector ` in ` -> `，在`.
- Its paired suffixes (`IL_00E0` and `IL_04FD`) become `纪律中（将从` and
  `纪律中（从`, so the dynamic discipline is followed by a Chinese grammatical
  suffix rather than the source parenthesis clause.
- The exact rich warning literal at `IL_0144` becomes
  `[COLOR:BAD-RED][FONT:CLEAN-BOLD]- 警告 -[/FONT][/COLOR] 训练完成后，`; the
  adjacent source-only space at `IL_015E` is removed.
- The warning consequence at `IL_017E` now retains the opaque `XP` key but
  changes its display link to `[经验|XP]`.

All bindings reuse `il-rewrite-ui`; tags, the dynamic clan/discipline values,
and the `XP` concept key are preserved. This is method-and-offset-specific
coverage, not a global `in`, `WARNING`, or `Experience` replacement. The
patched UI assembly was inspected after build and contains each of the seven
new/changed values at the stated IL offsets.

`AtG.Patch.Tests` now rewrites the original UI DLL with all ten relevant
training connector operands (the two earlier connectors plus the eight
discipline-popup operands) and verifies each final `ldstr`. The runtime and
patch test suites, tag/rich-text/concept-link/alias/font/build-report/IL-risk
gates, and the refreshed Composite/KnownText/TODO checks all passed. The
source catalog refreshed to 19,512 occurrences; the Composite authority now
contains 12,046 entries, 15 rules, and 382 runtime-map entries.

The manifest refresh installed matching `AtTheGatesUI.dll` and
`AtG.RuntimeText.dll` artifacts. Default main-menu smoke passed (8.27 seconds
to a window, eight stable checks over 4.17 seconds; no new-game attempt,
crash log, crash dialog, settings error, or Windows error). The smoke capture
again contained Chrome rather than the game, so it is not visual evidence.
No save, clan screen, discipline selector, or target hover was opened under
the requested smoke-only scope.

## 2026-08-05 smoke-only repair

The reported UI fragments are separate, display-only operands in two distinct
UI methods. They must not use a global `in` or `as` replacement:

- `Popup_ChooseClanToTrain.CreateControls_OnRebuild`
  (`0x06000504`, IL offset 133, string token `0x7000a210`) builds the
  discipline-selection title with ` in `. It now maps to `：`, producing the
  compact composed form `训练氏族：纪律`.
- `ClanCard.BuildTooltips` (`0x06000122`, IL offset 2295, string token
  `0x70008b08`) builds the active training status with `as `. It now maps to
  `成为`, preserving the dynamic profession label as `正在训练成为探险者`.

The first source composition is
`managed:source/AtTheGatesUI.original.dll:06000504:IL_008A`; the second is
`managed:source/AtTheGatesUI.original.dll:06000122:IL_08FC`. Their editable
rewrite bindings use the existing `il-rewrite-ui` rule at
`managed-map:hardcoded-ui-il-rewrite.json:0x06000504:IL_0085` and
`managed-map:hardcoded-ui-il-rewrite.json:0x06000122:IL_08F7`.

`AtG.Patch.Tests` rewrote the original UI assembly using only those two specs,
then verified the exact translated operands at both offsets. The test passed;
the only diagnostic was the non-fatal `NU1900` NuGet vulnerability-feed
warning. This task remains smoke-only: refresh composition evidence, build,
install, and run the default main-menu smoke without opening the clan UI.

`composite-catalog` refreshed the authority to 12,045 entries and 15 rules.
`Test-CompositeTextCatalog.ps1` then passed with 9,031 resolved KnownText
locators; both scoped managed-map bindings resolve under `il-rewrite-ui`.

`Build-Patch.ps1` completed successfully. The UI managed rewrite regenerated
from the changed exact map (1,490 scoped operations); the report retained
`DynamicCjk`, 149 runtime redirects, and the established runtime-map counts.

The manifest-backed installation refreshed successfully. The default main-menu
smoke passed: the window was ready in 15.04 seconds, stayed stable for eight
checks over 4.15 seconds, and showed no crash log, crash dialog, settings
error, or Windows error. The captured main menu was visually checked and a
post-install SHA-256 comparison confirmed that `AtTheGatesUI.dll` matches the
newly built artifact.

Per the smoke-only request, no clan screen, discipline selector, training
status tooltip, save, or other black-box interface was opened. The two target
displays are covered by their exact managed-rewrite test and installed build,
but not by a target-UI replay.
