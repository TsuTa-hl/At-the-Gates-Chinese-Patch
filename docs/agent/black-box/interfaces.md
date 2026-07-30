# Interface Test Coverage

Use the scenario registry for coordinates, setup state, and machine IDs. This
file defines what to inspect and when a surface may be considered covered.

## Main Menu, Load, and Reload

- Main-menu smoke verifies a complete window and no new crash/log event.
- Fixed-save scenarios load from the main-menu load panel, not from the pause
  menu, unless the in-game reload path is the case under test.
- The load panel must localize its buttons/tooltips and may retain World IDs,
  versions, and generated save labels.
- The in-game reload lifecycle case reloads the same fixed save repeatedly in
  one process. It is FullRegression only when renderer, load lifecycle,
  Game/ElfTools rewrite, or save behavior changes.

## Knowledge Screen

- Open the knowledge screen and test visible nodes, status lines, upgrade
  icons, footer, show-all, and close controls selected by the scenario.
- Verify raw profession/discipline keys, `Cannot`/`Already` fragment mixing,
  unlocalized requirements, and broken rich-text links are absent.
- Nested concept hovers must retain a highlighted display term and a valid
  second-level tooltip when one exists.

## Clan Screen and Traits

- Open the clan screen from the main loop and test action buttons, card details,
  and all visible trait icons.
- Random six-point trait discovery is deferred. The former Codex sweep is
  disabled; use `clan-trait-verification.json` to record any deliberately
  inspected trait ID and save.
- Scope includes 92 personality and 14 non-personality traits. A trait is
  passed only when its own name and effect/description are visibly confirmed.
- Do not count a portrait, card body, notification, or clan detail card as a
  trait result. Record the actual trait ID and save before repair when random
  discovery exposes a defect.
- The `avr-wpr-clan-family-countdown-20260727` fixed-save case covers the
  family-growth countdown on the first card. Its 2026-07-27 final trace draws
  `(+1，还需 12 回合)` without a residual English `in`.

- The 2026-07-30 VMP-MLE fixed-save retest covers the user-reported Happy mood
  icon on Relindis's card. The final tooltip renders `当高兴时……` and
  `+1 心情，因为已册封`; its text trace has no residual `When`, `from being`,
  or `Ennobled`. This is a single recorded fixed-save hover, not trait
  discovery coverage.

## Clan List

- Test the first-row header hovers for the scoped text and icon columns.
- Test only the Level secondary tooltip by default; deeper nested paths require
  an explicit request.
- Concept links such as Clan, Discipline, Level, and Upgrades must show
  localized display text while retaining their valid concept keys.

## Main Loop and Terrain

- Test affected HUD, system, action, resource, notification, and selected-unit
  controls. Do not sweep unrelated passed controls by default.
- For a selected settlement/unit, inspect Pack Up, movement, skip, and any
  currently visible action that the change can affect.
- Terrain tests click/hover each distinct visible object needed by the active
  scenario and inspect the lower-right description and left-side detail panel.
- The former `TileHoverSweep` scenarios are archived exploratory records. No
  generated 91-cell runtime sweep is selected or maintained. If the user has
  confirmed a specific terrain/resource defect, use its fixed-point scenario
  and the existing boundary manifest as a checklist; do not treat old sweep
  evidence as a new coverage session.
- Fixed-save terrain/resource hover scenarios and the contextual trait mood
  case may be run by Codex for that confirmed defect only. Their scope is the
  recorded points and save; they must not be expanded into random-world
  discovery. Repeated new-world creation requires explicit user confirmation,
  followed by manual user confirmation that the procedure behaves correctly.
- The 2026-07-30 `VMP-MLE` fixed-save replay is a completed targeted case for
  Deserted City, Deserted Village, and the village basic tile detail. It used
  only the three recorded hover coordinates after a fresh patch installation.
  City and village rumours are Chinese. The tile detail's Supply, Terrain, and
  Defense links are parsed through `RichTextLabel`/`TextFormatter`, not shown
  as literal `[display|KEY]` text; the recorded Supply glyph coordinate opens
  the Chinese recursive Supply card. This is a fixed-save result, not terrain
  discovery coverage.
- Run `tools\Test-TerrainTooltipBoundaryCoverage.ps1` before a manual review
  or terrain/resource translation change.
  It verifies all 143 source name entries against the patched XML, all 22
  defined terrain descriptions and 42 resource descriptions, and the seven
  runtime resource/rumor tooltip templates. The three volcano descriptions
  marked `TODO` remain source-defined and are not treated as missing runtime
  observations.
- Random terrain, clans, notifications, and commands must use a saved state for
  repair/retest; never reroll while chasing one defect.
- 2026-07-26 resource-tooltip regression uses the fixed `XDR-HCF` save only:
  verify deer, berry, unknown mineral/plant/animal, forest movement text, and
  Note Mode. The final seven-point run drew no resource-tooltip target English;
  its terrain status drew `消耗全部` with zero missing glyphs. Keep the expanded
  unknown-plant and Note Mode captures as fixed-wait companions, because the
  ordinary hover points can stabilize before their long tooltip is visible.
- The `avr-wpr-resource-tooltips-20260727` fixed `AVR-WPR` case separately
  covers Deserted Farm, the normal deer herd, and the wheat field. Its prior
  passing conclusion was reopened by a user capture because the test omitted
  the final farm literal. The repaired final fixed-save run now asserts the
  whole two-sentence value and draws `其中可能仍有有用的物资，可由` plus the linked
  `探险者` and `调查。`, with no English or trailing `n`. Wheat still requires
  final-rich-text boundary fragments rather than a whole-template rule.
- As of 2026-07-27, the farm point also uses per-point `ExpectedAll` runtime
  text assertions for the title, both Chinese sentences, linked `探险者`, and
  final `调查。`. A no-English check alone cannot pass this point, so a missed
  hover or title-only tooltip now fails instead of producing false coverage.
- Historical 91-cell sweep results remain in text evidence for audit context
  only. They are not rerun automatically and do not replace the static
  23/78/42 source boundary counts.
- The HJM-TMC fixed-save replay on 2026-07-29 also passed all 91/91 tiles. Its
  animal-herd cards previously exposed split final nodes such as `Herds of`,
  `can be`, and `on them.`; the repaired runtime fragment rules now render
  those nodes in Chinese for non-Deer herd variants. No forbidden English,
  camera movement, or selection change was recorded. Boundary evidence is
  merged from 11 passing saves, with 32 observed source identities and 111
  pending identities; this is not yet full 23/78 runtime coverage.
- RKA-ILH was replayed with the same fixed 91-coordinate plan and passed every
  tile, including collapsed/expanded handling and movement guards. It added no
  new terrain/deposit identity, so the boundary remains 32 observed and 111
  pending.
- SJI-VMQ was replayed with the same fixed plan and also passed every tile;
  no additional source identity was visible, leaving 32 observed and 111
  pending in the boundary manifest.
- NQT-LXE completed the same 91-tile replay without movement or untranslated
  text and likewise added no boundary identity; 32 are observed and 111 remain
  pending.
- YJU-SXX completed the fixed replay with the same clean result and no new
  identity; runtime boundary evidence remains 32 observed and 111 pending.
- YQX-XNF and WOC-IPI are historical random-world samples from the retired
  exploratory protocol. They are evidence only, not current executable
  coverage; any new repeated random-world run requires explicit user
  confirmation and manual confirmation of the unchanged procedure.

## Help and Religion

- Help tests cover only the requested article/page sequence; `Escape` can
  close an article, then the help panel, then open a pause menu if overused.
- Religion tests use the designated fixed save and inspect the title and each
  listed option. Preserve logic IDs while localizing stable display names.

## Completion Evidence

Record scenario ID, setup/save, target points, visible result, crash-log state,
timing, and any limitation. Keep screenshots only until this text record is in
the cleanup handoff.
