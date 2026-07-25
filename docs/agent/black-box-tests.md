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

- `clan-screen-random-traits`: dynamic coverage remains partial. Test every
  visible trait, including non-personality traits, and record only the trait
  actually confirmed by its own tooltip.

## Interface Coverage

Read `docs/agent/black-box/interfaces.md` only for the selected surface. It
contains the current completion criteria for main-menu/load, knowledge, clan
screen, clan list, main loop, terrain, help, and religion.

## Visual Gate

No raw key, unresolved tag, mojibake, safely localizable English, artificial
Chinese spacing, clipping, or lost recursive hover is acceptable on the tested
surface. Generated names, IDs, versions, URLs, and documented logic-sensitive
residuals remain exceptions only when the applicable topic file says so.
