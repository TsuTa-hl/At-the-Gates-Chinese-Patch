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

## Win11 Toolchain Audit (2026-07-28)

- Windows reports build `26200` / display version `25H2` (the registry still
  labels the product `Windows 10 Enterprise`; use the build rather than that
  legacy product string when identifying the host).
- Windows PowerShell 5.1 and the bundled `.tools\dotnet\dotnet.exe` (SDK
  8.0.423, win-x64) are the supported working combination. A system `dotnet`
  command is not on `PATH`, so scripts must continue to use the bundled path.
- All 83 project PowerShell scripts parse successfully; all project JSON/XML
  catalogs parse successfully; every C# project and deterministic test suite
  builds/runs on this host. Restore/build may emit `NU1900` when the NuGet
  vulnerability endpoint is unreachable; this is a network-audit warning, not
  a compile failure.
- The single-instance smoke-test guard now starts its child through explicit
  `.NET ProcessStartInfo`. This avoids a Windows PowerShell 5.1 failure when a
  host environment exposes both case variants of `PATH` (`PATH` and `Path`).
- The audit did not launch the game or validate a live visual surface. Main-menu
  smoke and in-game automation therefore remain separate, explicitly opt-in
  checks.
