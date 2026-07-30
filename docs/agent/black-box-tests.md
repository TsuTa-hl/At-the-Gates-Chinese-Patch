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
- Fixed terrain/resource cases and contextual trait cases may be promoted to a
  targeted run when the user has already confirmed the defect. Such a run may
  launch the designated fixed save and replay only the recorded points. It must
  not create random worlds or broaden the interface scope. Any workflow that
  needs repeated random-world creation requires explicit user confirmation;
  after confirmation, the user—not Codex—must manually confirm the procedure
  before it is tuned or extended.

## Latest Test Session

The scenario registry requires explicit user confirmation before any repeated
random-world procedure. After confirmation, run that exact procedure unchanged
until the user manually confirms it behaves correctly; Codex must not
autonomously evaluate, tune, broaden, or improve it. Terrain/trait exploratory
auto-coverage remains disabled; only recorded fixed-save replays for
user-confirmed known defects are allowed.

The current VMP-MLE procedure is the standard `fixed-save` load of the exact
existing save with the installed patch. Do not isolate, rename, or otherwise
alter saves to run a recorded fixed-save case.

The final 2026-07-30 VMP-MLE session rebuilt and freshly installed the patch,
then passed main-menu smoke before replaying only user-recorded targets. City
and village rumours are Chinese; the tile detail preserves Supply, Terrain,
and Defense recursive links through `RichTextLabel`/`TextFormatter`; and the
Relindis Happy tooltip renders `当高兴时……` plus `+1 心情，因为已册封` with no
residual `When`, `from being`, or `Ennobled`. No random-world creation, broad
terrain sweep, save mutation, or unrecorded target was used. The interface
topic owns the compact coverage record.

## Interface Coverage

Read `docs/agent/black-box/interfaces.md` only for the selected surface. It
contains the current completion criteria for main-menu/load, knowledge, clan
screen, clan list, main loop, terrain, help, and religion.

## Visual Gate

No raw key, unresolved tag, mojibake, safely localizable English, artificial
Chinese spacing, clipping, or lost recursive hover is acceptable on the tested
surface. Generated names, IDs, versions, URLs, and documented logic-sensitive
residuals remain exceptions only when the applicable topic file says so.
