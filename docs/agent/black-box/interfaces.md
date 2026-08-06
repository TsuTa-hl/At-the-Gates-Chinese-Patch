# Interface Test Coverage

Use the scenario registry for coordinates, setup state, and machine IDs. This
file defines what to inspect and when a surface may be considered covered.

## Coordinate Verification Gate

- A user screenshot establishes a known defect and the intended control; it
  does **not** establish a runnable `X`/`Y` pair. Scenario coordinates use the
  2560 x 1440 harness reference space and must be proven with a current,
  cursor-marked full-client capture on the same save and interface.
- Calibrate setup clicks as well as hover points. A setup click is valid only
  when the requested destination marker is visible (for example, the diplomacy
  screen), not merely because the frame fingerprint changed.
- Calibrate a hover by showing the named control and its own tooltip. A nearby
  tile detail, card body, notification, or title is not a substitute. Capture
  dimensions, save name, reference coordinate, marker result, and stable
  target identity in the current handoff before adding a permanent point.
- If this proof is absent, record `UncalibratedCoordinate` and stop. Such a
  result is neither a localization pass nor a localization failure, and it
  must not be used to tune coordinates by repeated screenshot guessing.
- For ERJ-UUX and any future fixed-save replay, keep calibration in two
  separate phases: first prove setup destinations (clan screen, diplomacy
  screen, selected leader), then prove each hover target and its tooltip. A
  stable absolute mouse trace alone is insufficient. Store no point until the
  cursor-marked frame contains the named target and the destination-state
  marker; the 2026-07-30 ERJ-UUX points therefore remain retired.

The 2026-08-01 ERJ-UUX repair session added exact runtime fallbacks for the
observed Wasteful effect order, the title `in.` suffix, and the flattened
supply sentence; deterministic runtime tests passed, the refreshed patch was
installed, and main-menu smoke passed. The later diplomacy replay used the
exact ERJ-UUX file and proved the same-save path with absolute points
F3=(2025,25), Peucini=(1280,718), and Relationship Level=(1795,644).

## Diplomacy

- The selector button, its hover tooltip, the selected small-tribe detail
  panel, and the Relationship Level tooltip are separate surfaces.
- ERJ-UUX's runtime trace now draws Chinese Peucini and diplomacy tooltip text;
  the relationship tooltip has no differing religious beliefs fragment.
- The name is split by the game into The and a bare tribe-name draw node in
  the tooltip. Runtime mappings therefore retain full The Name entries for
  buttons and add split name/article fallbacks for tooltips.
- The disposable run passed all nine capture points without a crash. Its
  points remain out of the registry until the cursor-marked calibration is
  manually promoted.
- The 2026-08-06 uninstall-completeness verification restored the original
  Factions.xml (The Carpi) and removed the runtime localization DLL/TSV by
  exact file checks before the unpatched main-menu smoke. It did not open the
  diplomacy panel, so this is rollback evidence rather than a new Diplomacy UI
  replay or coordinate calibration.

## Main Menu, Load, and Reload

- Main-menu smoke verifies a complete window and no new crash/log event.
- `Screen_ChooseFaction.Update` derives a faction key from the first four
  characters of the button text. The ten playable faction `<name>` and
  `city/name` config values therefore remain original logic strings; their
  visible Chinese labels come from the runtime display map. A new-game click
  sequence is not a pass until the tribe-selection destination is visibly
  proven on the current client geometry.
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

- The 2026-08-02 RXL-CQW fixed-save replay passed the visible profession cards
  at absolute reference points Reaper (1145,850), Gatherer (1410,850), and
  Trapper (1815,1104). Two absolute panel scrolls at (1280,720) with
  `WheelDelta=-960` then exposed and passed Digger (1280,350), Surveyor
  (1820,1060), and Explorer (1280,1260). The runtime traces contain no
  standalone ` in ` countdown connector, `Attack`, `Cannot`, `Trait`, or
  `Innate`; the same fixed-save map replay also covered the resource and
  selected-bandit surfaces. These points are executable after fixed-save
  authorization and are not random-world discovery.

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
- The 2026-08-01 `CLD-DML` probe isolated a different clan-card countdown
  surface: `BuildBasicDescription` emits a standalone ` in ` node before the
  remaining-turn value. It is now covered by the scoped `0x0600171f` / IL
  offset 693 rewrite to `，还需`. A current replay may run only against the
  designated fixed save and approved coordinates after user authorization; it
  must not broaden into random discovery.

- The 2026-07-30 VMP-MLE fixed-save retest covers the user-reported Happy mood
  icon on Relindis's card. The final tooltip renders `当高兴时……` and
  `+1 心情，因为已册封`; its text trace has no residual `When`, `from being`,
  or `Ennobled`. This is a single recorded fixed-save hover, not trait
  discovery coverage.

- The 2026-08-02 UBL-TVF turn-002 replay did not expose Adaptable or Demanding
  on the visible cards. Their scoped `No` and `become obsessed with the idea
  of` fixes are installed, but this save supplies no target tooltip for visual
  promotion; do not count the absent cards as a pass.

## Clan List

- Test the first-row header hovers for the scoped text and icon columns.
- Test only the Level secondary tooltip by default; deeper nested paths require
  an explicit request.
- Concept links such as Clan, Discipline, Level, and Upgrades must show
  localized display text while retaining their valid concept keys.

- The 2026-08-03 UBL-TVF turn-002 fixed-save run passed all 11 first-row header
  hovers, including the distance column. The distance label renders `格`, and
  the trace contains no `tiles`, `Moving`, or other command-family English
  residuals.

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
  case may be executed after the user confirms the defect and authorizes the
  designated run. Use only approved absolute coordinates and the same save;
  repeated new-world creation remains separately gated by explicit user
  confirmation and manual confirmation that the procedure behaves correctly.
- The 2026-07-30 `VMP-MLE` fixed-save replay remains historical evidence for
  Deserted City and the village basic tile detail, but its Deserted Village
  rumor conclusion is superseded by the 2026-08-05 user capture. That capture
  showed the unpatched `GOODY_HUT_VILLAGE` config description beginning with
  `All that remains`; the prior runtime-fragment repair did not own this
  surface. The replacement is an ID-scoped `GoodyHuts.xml` patch, built and
  installed with a passing default main-menu smoke. No fixed-save or target
  hover was run under the smoke-only scope, so the repaired village tooltip is
  pending visual verification. The tile detail's Supply, Terrain, and Defense
  links are parsed through `RichTextLabel`/`TextFormatter`, not shown as
  literal `[display|KEY]` text; the recorded Supply glyph coordinate opens the
  Chinese recursive Supply card.
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

- The 2026-08-03 UBL-TVF turn-002 fixed-save run reached the Hunter at the
  approved center point and passed the Chinese `固守`/`每回合` tooltip. The
  Digger selector and close-after-assignment paths passed; the map operation
  panel visibly rendered `采集`, `固守`, `扎营`, `移动`, and `跳过`. The static
  SelectionPanel audit also covers direct Abandon, Besiege, Enable, Disable,
  Heal, Repair, and Unpack labels, while existing exact mappings cover Split
  Army, Pillage, Force, Remove Disguise, Manage Clans, and Add Apprentice Slot.
  These less common branches were not reachable in this save and remain
  static/build-only evidence. No Digger map unit was present, and four fixed
  enemy candidates produced terrain/resource cards rather than a bandit camp;
  the `is mangled` battle-prediction card therefore remains unreachable in this
  save. Adaptable and Demanding were also absent from the visible clan cards;
  their scoped static rewrites remain unpromoted until a save exposes them.

## Help and Religion

- Help tests cover only the requested article/page sequence; `Escape` can
  close an article, then the help panel, then open a pause menu if overused.
- Religion tests use the designated fixed save and inspect the title and each
  listed option. Preserve logic IDs while localizing stable display names.

## Completion Evidence

Record scenario ID, setup/save, target points, visible result, crash-log state,
timing, and any limitation. Keep screenshots only until this text record is in
the cleanup handoff.
