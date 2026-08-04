# Black-Box Test Policy

This is the strategy and state index. Coordinates and executable point details
live only in `black-box-scenarios.json`; interface coverage lives in
`black-box/interfaces.md`.

## Full and Incremental Coverage

- Incremental tests are the default. Select only interfaces affected by the
  latest source, renderer, save/load, or rule change.
- Full regression is opt-in for release work, broad renderer/runtime changes,
  or an explicit user request. Passed interfaces are not repeated merely to
  rediscover text.
- A failed or newly reported scenario becomes Active Focus. A passed scenario
  moves into the matching interface section without duplicating its points.

## Baselines

- The install smoke reaches the main menu only; it never replaces game UI
  coverage.
- In-game UI tests load a designated save from the main menu. Random discovery
  must save the exposed state before a repair and reload it for the retest.
- An in-game reload regression is a separate FullRegression case. It is not a
  substitute for main-menu fixed-save loading.
- Every hover waits at most three seconds. Passing points store crop/text
  evidence; full-window screenshots are for state transitions and failures.

## Deferred Focus

- The terrain 91-cell sweep and six-point random trait discovery are retired
  automation. Their scenario records remain `Deferred` so prior save names,
  boundaries, and evidence handoffs are not lost; they are not selected by the
  incremental runner and no replacement runtime sweep is maintained.
- Fixed terrain/resource cases and contextual trait cases may be executed when
  the user has confirmed the defect and authorized the run. A run must use the
  designated save and approved absolute coordinates; it must not broaden into
  random-world discovery. Any workflow that needs repeated random-world
  creation still requires explicit user confirmation and an unchanged,
  user-approved procedure.

## Latest Test Session

The 2026-08-03 UBL-TVF turn-002 replay used only the designated fixed save
after the latest build, uninstall, and install. Main-menu smoke was stable
with no crash dialog, settings error, Windows error, or process-lifecycle
failure. The clan-list run passed all 11 header points, including the distance
column; the trace rendered the unit as `格` and contained no `tiles`, `Moving`,
`Each`, `Cancel`, `Forage`, or `is mangled` residual. The Hunter run passed the
fixed Dig In point and visibly rendered the Chinese `每回合...固守` tooltip.
The Digger selector and close-after-assignment paths passed, and the map
operation panel visibly rendered `采集`, `固守`, `扎营`, `移动`, and `跳过`.
The static SelectionPanel audit also covered direct action labels Abandon,
Besiege, Enable, Disable, Heal, Repair, and Unpack; existing exact mappings
for Split Army, Pillage, Force, Remove Disguise, Manage Clans, and Add
Apprentice Slot were retained. Those branches were not reachable in this
save, so their evidence is static/build-only. The Digger map unit itself is
not present. A follow-up fixed-save coordinate calibration around the visible
southern bandit camp (14 additional absolute hover points across three
temporary scenarios) still produced map/terrain cards or no card, not the
battle-prediction panel; the `is mangled` card therefore remains a static-only
limitation for this save. Adaptable and Demanding were not present on
the visible clan cards; their scoped static fixes likewise remain unpromoted.
The four trait candidate points passed without forbidden residuals but landed
on other visible traits. No random world was created, and no camera or
selection drift was recorded. Evidence is retained under
`ubl-tvf-turn002-targeted-replay` and the 2026-08-03 run directories.

The 2026-08-03 UBL-TVF continuation was static-only. The first attempted
`become obsessed with the idea of` repair did not cover the standalone display
segment that reaches the clan-trait hover. The current runtime map therefore
contains an exact plain-text mapping plus plain- and rich-text trailing-fragment
forms, all under `runtime-display-fragment` / `runtime-display-richtext-fragment`.
The runtime parser also treats bare `[SCORE]`-style tokens as raw tags rather
than concept links. Only the observed six-token allowlist is now translated
before rich-text parsing (`SCORE`, `TREASURE`, `HORSES`, `WEAPONS`, `CARAVAN`,
and `COAL`); unknown raw tags remain untouched. The same static pass covers
Relationship Level reasons and diplomacy keywords, contextual Bandit/Pillage
labels, and the UBL-TVF `will`/`This`/`No`/`next`/`As`, movement,
status/combat-XP, caravan, coal-deposit, and training-`as` residuals. Runtime,
patch, build-report, tag, generated-output, and installed-file hash checks
passed. The patch was then explicitly uninstalled and reinstalled; no game was
launched. Visual verification remains pending with the user and must not be
promoted as a passed UI scenario.

The 2026-08-04 residual-localization refresh was also static-only at the
user's request. It makes final-display fragment matching tolerant of UI
whitespace and format characters, which covers the observed `become obsessed
with the idea of` variant. It also adds final-output repairs for localized
`remaining`, the abandoned-village rumor, Bandit/Bandit Leader variants,
caravan headings, and relationship-distance reasons through 12 tiles. The
legacy bare display macros such as `[SCORE]` are allowed only as plain Chinese
display replacements in the scoped runtime rich-fragment map; actual concept
links, hotkeys, and formatting remain strictly validated. The coal descriptions
now retain their `DEPOSIT` concept link. Build, tag and concept-link checks,
the patch and runtime test suites, the composite catalog (12,027 entries), and
post-install file-hash comparisons passed. The installer removed the existing
patch and installed the refreshed build. No game process was launched; all UI
visual verification remains pending with the user.

The 2026-08-04 Clan List distance-unit singular refresh was static-only at the
user's request. The reported `1 tile` uses a distinct adjacent `ldstr` from
the already-localized plural `tiles` suffix in
`ClanListEntry.BuildPanel_Contents`. Both exact anchors now map to `格`, and a
patch test rewrites the original UI DLL with only that two-item family to
verify both resulting operands. JSON validation, the patch test suite,
rich-text and concept-link checks, and the full patch build passed. The
installer removed the existing patch and installed the refreshed build; the
installed `AtTheGatesUI.dll` SHA-256 matched the built patch output. No game
process was launched. Manual verification remains pending: inspect a Clan List
row at distance 1 and a plural-distance row.

## Interface Coverage

Read `docs/agent/black-box/interfaces.md` only for the selected surface. It
contains the current completion criteria for main-menu/load, knowledge, clan
screen, clan list, main loop, terrain, help, and religion.

## Visual Gate

No raw key, unresolved tag, mojibake, safely localizable English, artificial
Chinese spacing, clipping, or lost recursive hover is acceptable on the tested
surface. Generated names, IDs, versions, URLs, and documented logic-sensitive
residuals remain exceptions only when the applicable topic file says so.
