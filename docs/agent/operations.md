# Operations Invariants

This file owns the small set of operational rules that every automation path
must obey. Read a child topic only when its work is actually needed.

## Non-Negotiable Rules

- Windows PowerShell 5.1 Desktop remains the supported public and development
  scripting baseline. Do not require PowerShell 7 syntax or modules.
- Read and write UTF-8 deliberately. Windows PowerShell 5.1 may otherwise use
  an ANSI fallback for non-ASCII files.
- An apostrophe inside a single-quoted PowerShell string must be escaped by
  doubling it, or the value must be passed as an argument rather than spliced
  into a command string.
- Resolve the game directory from `-GamePath`, then `ATG_GAME_PATH` or
  `AT_THE_GATES_PATH`, then Steam discovery. Never hard-code an install path.
- Launch the game with its working directory set to the resolved game folder.
- All coordinates are relative to the game window, not the virtual desktop.
  JSON scenario coordinates use the stated reference client size; the harness
  scales them after locating the window.
- Do not open external webpages, challenge login, or forum links during game
  tests.

## Conditional Topics

- Build, install, uninstall, smoke, and artifact checks:
  `docs/agent/operations/build-and-install.md`
- Game process control, screenshots, input, fixed-save loading, and crash
  dialog handling: `docs/agent/operations/game-automation.md`
- Resource, network, and runtime diagnostics:
  `docs/agent/operations/diagnostics.md`
