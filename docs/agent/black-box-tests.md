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

## Active Focus

- `*-tile-hover-sweep-20260728`: the dynamic map protocol uses each save's persisted absolute center and two adjacent tile anchors to generate exactly 91 axial-radius-five positions. It requires runtime text tracing, expands map cards from their detected per-card controls, cycles same-tile items with bounded identity deduplication, records the lower-right quick reference separately, and treats empty tiles as `NoTooltip`. AVR-WPR, XDR-HCF, and one saved new-game discovery are separate states; repair verification must reload the same save rather than reroll it.
- `clan-trait-random-discovery`: every load runs the six fixed global absolute
  points `(1182,639)`, `(1182,655)`, `(1331,639)`, `(1331,655)`,
  `(1483,639)`, and `(1483,655)` in 2560x1440 reference-client space. The
  harness converts each once to a Windows screen coordinate, verifies the
  cursor position, and requires a translated trait title at every point; a
  card detail, mood detail, empty hover, or changed crop fails the round.
  Record every actual trait, including non-personality traits.
- `clan-trait-miserable-mood-detail`: the fixed `SYI-ITT` retest passed on
  2026-07-27 after the exact mood-display repairs. It is retained as an
  incremental regression because the tooltip is contextual to a trait and is
  not reached by ordinary card-summary coverage.

## Latest Test Session (2026-07-28)

- Static harness validation passed: both harness projects built with zero
  warnings/errors, all deterministic tests passed, the boundary generator
  produced 23 terrains/78 deposit variants/42 resources, and the scenario
  schema accepted 22 scenarios and 142 points.
- Package gates passed for text tags (1,422 entries), generated aliases, the
  DynamicCjk font budget (33,451,005 bytes), runtime build-report counts, and
  composite rules (11,471 entries, 15 rules); documentation routing also
  passed after removing disposable historical screenshot paths. Installation
  refreshed the manifest-backed patch successfully.
- Default main-menu smoke reached a stable AtG window for 4.22 seconds with
  no crash log, settings error, or Windows error event. The host desktop did
  not expose the AtG surface to screen capture (the captured image belonged
  to another foreground application), so this is a startup pass, not visual
  tile coverage.
- The three `TileHoverSweep` scenarios remain `Discovery`: their persisted
  anchor/basis values are calibration placeholders and no 91-tile UI sweep is
  claimed until each designated save is calibrated. Do not promote them to
  `Completed` from static evidence alone.
- Win11 audit smoke (2026-07-28) resolved and started the AtG window, reached a
  stable main menu for 4.19 seconds, and reported no crash, settings, or
  Windows-error events; it exited cleanly with code 0. The Win32 screenshot
  helper received an invalid capture handle, so this remains a startup/tool
  pass rather than visual UI evidence.
- Static terrain-boundary coverage (2026-07-28) passed: 23 terrain names, 78
  deposit-variant names, 42 resource names, 22 defined terrain descriptions,
  42 resource descriptions, and seven runtime resource/rumor tooltip template
  families all contain approved Chinese mappings. This does not promote the
  three dynamic 91-tile scenarios; their per-save observations remain pending.

## Interface Coverage

Read `docs/agent/black-box/interfaces.md` only for the selected surface. It
contains the current completion criteria for main-menu/load, knowledge, clan
screen, clan list, main loop, terrain, help, and religion.

## Visual Gate

No raw key, unresolved tag, mojibake, safely localizable English, artificial
Chinese spacing, clipping, or lost recursive hover is acceptable on the tested
surface. Generated names, IDs, versions, URLs, and documented logic-sensitive
residuals remain exceptions only when the applicable topic file says so.
