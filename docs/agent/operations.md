# Operations Invariants

These rules apply to every build, install, smoke, verification, and release action.

- When work crosses assess/fix, build, install, smoke, UI testing, or a retry,
  carry one timing chain through the workflow handoffs.
- Unified verification stores selected checks, outcomes, and phase timings in
  task-local `.tmp` evidence; cleanup preserves the text handoff. Do not turn
  routine test results into knowledge documents.
- A documentation-only task uses the no-game static verification branch; it
  does not capture source, install a patch, or start a smoke test.
- Windows PowerShell 5.1 Desktop remains the supported public and development
  shell; the repository-local `.tools\dotnet\dotnet.exe` is the .NET toolchain.
  Use explicit UTF-8 for non-ASCII text. Escape an apostrophe inside a single-quoted PowerShell string by doubling it.
- Resolve the game directory from `-GamePath`, then `ATG_GAME_PATH` /
  `AT_THE_GATES_PATH`, then Steam discovery. Never hard-code an install path.
- A player installation is valid when it contains `At The Gates.exe` and
  `Content\Text\English.xml`. Do not add version, Steam-build, or file-hash
  admission checks to the installer.
- Development source capture, build, smoke, and release use a restored current
  Steam original build. `source/` is disposable local input, never release
  content.
- Launch the game with its working directory set to the resolved game folder.
  All coordinates are relative to the game window, not the virtual desktop.
- Default verification is main-menu smoke only. Black-box scenarios and random
  world generation require separate explicit authorization.
- A transactional install backs up the actual pre-install file. An uninstall
  must restore it byte-for-byte; only patch-exclusive files may be deleted.
- Release output is a player package only: `README.md`, install/uninstall
  scripts, and `patch/`. Keep development materials out of that branch.

## Topic Routing

- Build, transaction install/uninstall, unified verification: [build-and-install.md](operations/build-and-install.md)
- Game process control, screenshots, and input: [game-automation.md](operations/game-automation.md)
- In-game debug console, commands, and black-box safety: [debug-console.md](operations/debug-console.md)
- Resource, network, and runtime diagnostics: [diagnostics.md](operations/diagnostics.md)
- Architecture and data flow: [architecture.md](architecture.md)
- Current verification state: [current-status.md](current-status.md)
- Common recovery paths: [troubleshooting.md](troubleshooting.md)
