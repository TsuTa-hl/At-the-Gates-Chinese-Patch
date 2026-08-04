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
  JSON scenario coordinates are in the harness's 2560 x 1440 reference space;
  `CoordinateTransform` scales them only after it has read the live client
  size. A screenshot is evidence of a control, not a coordinate record. The
  two may numerically coincide only after a current cursor-marked capture has
  demonstrated the live mapping.
- A `RequireChange` result proves only that pixels changed. It does not prove
  that a click opened the intended interface or that a hover reached the
  intended control. Record an interface/state marker before treating either
  kind of action as calibrated.
- Do not open external webpages, challenge login, or forum links during game
  tests.

## Conditional Topics

- Build, install, uninstall, smoke, and artifact checks:
  `docs/agent/operations/build-and-install.md`
- Game process control, screenshots, input, fixed-save loading, and crash
  dialog handling: `docs/agent/operations/game-automation.md`
- Resource, network, and runtime diagnostics:
  `docs/agent/operations/diagnostics.md`

## Win11 Toolchain Audit (2026-07-29)

- Windows reports build `26200` / display version `25H2` (the registry still
  labels the product `Windows 10 Enterprise`; use the build rather than that
  legacy product string when identifying the host).
- Windows PowerShell 5.1 and the bundled `.tools\dotnet\dotnet.exe` (SDK
  8.0.423, win-x64) are the supported working combination. A system `dotnet`
  command is not on `PATH`, so scripts must continue to use the bundled path.
- All 87 current project PowerShell scripts parse successfully; 14 XML files
  parse successfully with explicit UTF-8 decoding. The filtered project set
  contains 183 JSON files; 182 are strict UTF-8 and one legacy, unused
  `translations/recheck-skipped-candidates.json` is GB2312 and should be
  normalized before it is promoted to an input. Every one of the 11 C# projects
  builds and all four deterministic test suites pass. Restore/build may emit
  `NU1900` when the NuGet vulnerability endpoint is unreachable; this is a
  network-audit warning, not a compile failure.
- The single-instance smoke-test guard now starts its child through explicit
  `.NET ProcessStartInfo`. This avoids a Windows PowerShell 5.1 failure when a
  host environment exposes both case variants of `PATH` (`PATH` and `Path`).
- Manifest refresh, install, and main-menu smoke also pass on this host: the
  refreshed window started in 8.27 seconds and remained stable for 4.15 seconds
  across eight checks, with no crash, settings, or Windows-error events. Static
  gates, install-refresh, window-finder, file-operation, cache, IL-rewrite,
  glyph, and trial-localization checks also pass. Running the trial batch-safety
  and recovery checks concurrently is unsupported because they share
  `.tmp\trial-localization\active-run.json`; they pass when run serially. This
  validates startup only; in-game automation and live visual capture remain
  separate, explicitly opt-in checks. PowerShell 5.1 audits must specify
  `-Encoding UTF8`; its default decoding can falsely report valid Chinese JSON
  as malformed.

Reverification on 2026-07-29 after the Win11 update reproduced the toolchain
results: solution build and four deterministic suites passed, the patch rebuilt
with the cached managed/runtime stages, and manifest-backed installation
refresh succeeded. The installed build reached the main menu in 8.78 seconds,
stayed stable for 4.15 seconds (8 checks), and exited cleanly with no crash,
settings, or Windows-error events. Fifteen external static/helper gates also
returned exit code 0. This is a repeat of the startup/tool audit; it does not
promote the separate in-game terrain/deposit coverage to complete.
