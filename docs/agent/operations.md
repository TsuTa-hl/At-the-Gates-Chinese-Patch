# Operations

Operational reference for paths, process control, build, install, launch,
screenshot, click, hover, and manual black-box testing.

## Paths and Process Control

- Do not hard-code the game install directory in scripts.
- Resolution order for scripts: explicit `-GamePath`, then `ATG_GAME_PATH` /
  `AT_THE_GATES_PATH`, then Steam auto-detection through `tools\AtGPaths.ps1`.
- Current verified local game path:
  `E:\Steam\steamapps\common\Jon Shafer's At the Gates`. Treat this as local
  test evidence only, not a script constant.
- Current verified local save directory:
  `E:\Steam\steamapps\common\Jon Shafer's At the Gates\Saved Games`. Treat this
  as local test evidence only.
- Close the game before installing the patch because DLLs may be locked:

  ```powershell
  Stop-Process -Name 'At The Gates' -Force -ErrorAction SilentlyContinue
  ```

- Launch the game with its working directory set:

  ```powershell
  . .\tools\AtGPaths.ps1
  $game = Resolve-AtGGamePath $null
  Start-Process -FilePath (Join-Path $game 'At The Gates.exe') -WorkingDirectory $game
  ```

- Launching without the working directory can trigger an
  `AtTheGatesCommon.ns_GlobalSystems.Log` initializer crash.
- Do not use computer-use `launch_app`; it does not guarantee the working
  directory.

## Build and Install

Repo-local .NET toolchain:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Install-DotNetToolchain.ps1
```

The IL rewrite path uses `.tools\dotnet\dotnet.exe` and
`.tools\nuget-cache`. `tools\AtG.IlRewrite` must be run through the repo-local
dotnet host as `AtG.IlRewrite.dll`; do not run or depend on an
`AtG.IlRewrite.exe` apphost. The project disables apphost generation because
directly running the exe can fail when no system-level .NET runtime is
installed.

Standard build:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Build-Patch.ps1
```

Standard install:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Install-ChinesePatch.ps1
```

The standard install command automatically uninstalls an existing
manifest-backed Chinese patch before copying the new patch. If no
`.atg-chinese-patch.json` exists in the game directory, it proceeds as a first
install.

Standard uninstall:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Uninstall-ChinesePatch.ps1
```

Use the uninstall command directly for rollback or manual cleanup. It requires
an existing `.atg-chinese-patch.json` manifest.

Launch smoke test:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-GameLaunch.ps1
```

`Test-GameLaunch.ps1` owns the game process for one smoke run and starts the
game only once. It uses a named single-instance lock
`Local\AtGChinesePatch.TestGameLaunch`; if another smoke test is already
running, a second smoke invocation must fail immediately rather than launch a
second game process.

The smoke test waits until the game window appears, then allows a short stable
render delay before screenshot capture. It then starts a new game through the
default tribe and normal difficulty path, waits for the main loop, captures a
second screenshot, and closes the game. `-WaitSeconds` is the maximum startup
wait, not an unconditional sleep. Use `-SkipNewGame` only when the caller
explicitly needs the old main-menu-only smoke.
The new-game wait is also condition-based: it exits early when
`Logs\Program.AtGLog` reports `Controller - Giving Control to Human`. Do not
treat `Game World - New Game Complete` as sufficient; that marker can appear
before the visible main loop is stable. After the main-loop marker, the smoke
test keeps the game alive briefly through `-PostNewGameReadyDelayMs` before
capturing and closing. Record `NewGameReadyMarker` and `NewGameSmokeSeconds`
when comparing smoke-test cost.
The result also records `ProcessExitedBeforeCleanup`, `ProcessExitCode`,
`WindowsErrorSeen`, `WindowsErrorEvents`, and `FailureReason`; use these fields
to diagnose silent exits that do not show `HE'S DEAD, JIM` and do not update
`Crash.AtGLog`.

Trial localization batch runner:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Invoke-AtGTrialLocalizationBatch.ps1 -BatchJson .\translations\trial-ui-notification-labels.json
```

The runner appends a candidate batch to normal IL rewrite maps, builds,
installs, runs the new-game smoke, and bisects a failing batch down to single
entries. It writes evidence under `.tmp\trial-localization\<timestamp>`.
One trial batch command may therefore run several sequential smoke tests when
the batch fails and needs bisection; this is expected. It must not run smoke
tests concurrently, and every smoke run must pass through `Test-GameLaunch.ps1`
so the single-instance lock applies.
If any trial stage fails during bisection, the runner must run a final
accepted-only smoke check before reporting accepted entries. This catches
infrastructure failures such as transient build locks or click/input failures
that can make a batch appear unsafe. The final check result must be written
back to `results.json`; if it fails, the run is marked with `invalid.json` and
any rejected evidence is preserved as `rejected.invalid-smoke.json` rather than
exported as unsafe text.
`Build-IlRewritePatch.ps1` retries transient Windows mapped-file write failures
from dnlib output, including `user-mapped section` and the localized Windows
message for user-mapped regions. If a whole trial batch fails once at build
time but smaller reruns and the final accepted-only smoke pass, treat it as
infrastructure noise, not unsafe text evidence.
`Build-Patch.ps1` also retries transient failures while removing the generated
font patch directory before regenerating fonts. If the retry succeeds and later
static/font tests pass, treat a single access-denied cleanup failure as
infrastructure noise rather than a localization rejection.
While a trial batch is running, the tool writes
`.tmp\trial-localization\active-run.json` with baseline map backups. If the
process is interrupted before it can write `accepted.json` / `rejected.json`,
the next trial-batch invocation must restore those baseline maps before
planning or testing a new batch.
After a run, record accepted/rejected counts and any isolated failures in
`docs\agent\trial-localization-state.json` during the knowledge-update step.
If a trial run reports `Error Loading User Settings`, inspect
`Settings\Settings.xml` in the game directory before retrying. A 2026-07-02
UserSetting trial wrote Chinese comments into that file and polluted every
subsequent smoke run until line 27 was restored to ASCII. Do not treat repeated
failures with that window title as evidence against unrelated trial entries.

Text tag validation:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-TextTags.ps1
```

Generated text alias validation:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-GeneratedTextAliases.ps1
```

Font patch budget validation:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-FontPatchBudget.ps1
```

Hover localization static regression:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-HoverLocalizationRegressions.ps1
```

Optimization tooling regression:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-OptimizationTooling.ps1
```

IL rewrite mapped-file retry regression:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-IlRewriteMappedFileRetry.ps1
```

Generated font cleanup retry regression:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-FontPatchRemovalRetry.ps1
```

IL rewrite map risk check:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-IlRewriteMapRisk.ps1
```

DLL `ldstr` catalog export:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Export-DllLdstrCatalog.ps1 -DllPath .\source\AtTheGatesUI.original.dll -OutputJson .\.tmp\ui-ldstr-catalog.json -OutputCsv .\.tmp\ui-ldstr-catalog.csv
```

## Screenshot and Input Automation

- Try computer-use first when explicitly requested. If XNA window capture
  fails, use the Win32 helper scripts immediately.
- The Win32 helpers use `Get-AtGWindow.ps1`. It tries `EnumWindows` first, then
  falls back to the `At The Gates` process `MainWindowHandle` when XNA/window
  enumeration does not expose the game window reliably. Keep this fallback
  because smoke tests can otherwise screenshot the main menu but fail before
  clicking `New Game`.
- Known computer-use XNA capture failure:

  ```text
  SetIsBorderRequired failed: 不支持此接口 (0x80004002)
  ```

Window screenshot:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Capture-AtGWindow.ps1 -OutputPath .\.tmp\<name>.png -MarkCursor
```

Window-relative click:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Click-AtGWindow.ps1 -X <window-x> -Y <window-y>
```

Window-relative hover:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Move-AtGWindow.ps1 -X <window-x> -Y <window-y>
```

Hover waits should be short. Default to 700-1500 ms after moving the cursor.
Retry up to 3 seconds only when the tooltip does not appear. Do not use longer
fixed waits for routine sweeps.

Crop a screenshot region:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Crop-AtGImage.ps1 -SourcePath .\.tmp\shot.png -OutputPath .\.tmp\tooltip.png -X <x> -Y <y> -Width <w> -Height <h>
```

Build a contact sheet from cropped screenshots:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\New-AtGContactSheet.ps1 -ImagePath .\.tmp\a.png,.\.tmp\b.png -OutputPath .\.tmp\sheet.png
```

Validate structured black-box scenarios:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-BlackBoxScenarioSchema.ps1
```

Dry-run an incremental or full-regression scenario:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Invoke-AtGBlackBoxScenario.ps1 -ScenarioId <id> -DryRun
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Invoke-AtGBlackBoxScenario.ps1 -ScenarioId <id> -Suite FullRegression -DryRun
```

Run a scenario against the currently open game/interface:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Invoke-AtGBlackBoxScenario.ps1 -ScenarioId <id> -Suite Incremental
```

The scenario runner only executes recorded click/hover/capture points. It does
not launch the game, choose a tribe, save, or load. Perform setup through the
workflow first, then run the scenario against the already-open state.

Dual-monitor diagnostic screenshot:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Capture-Desktop.ps1
```

All coordinates are relative to the game window, not the virtual desktop.

## Crash Dialog Handling

The game writes the useful crash details to `Crash.AtGLog` only after the
`HE'S DEAD, JIM` dialog is acknowledged. When a crash dialog is visible:

1. Capture the dialog first:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Capture-AtGWindow.ps1 -OutputPath .\.tmp\<crash-dialog>.png -MarkCursor
   ```

2. Record the current crash-log timestamp before clicking OK:

   ```powershell
   . .\tools\AtGPaths.ps1
   $game = Resolve-AtGGamePath $null
   $log = Join-Path $game 'Crash.AtGLog'
   Get-Item -LiteralPath $log -ErrorAction SilentlyContinue | Select-Object FullName,LastWriteTime,Length
   ```

3. Click the dialog OK button with the Win32 click helper, wait briefly for the
   process to close or the log timestamp to change, then read the latest log
   block:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Click-AtGWindow.ps1 -X <ok-x> -Y <ok-y>
   Start-Sleep -Milliseconds 500
   Get-Content -LiteralPath $log -Encoding UTF8 -Tail 120
   ```

4. Treat the newly written `Crash.AtGLog` block as the authoritative error and
   stack trace. If the timestamp does not update, keep the screenshot, process
   state, and pre-click log metadata as failure evidence.

If the game exits without a crash dialog, check the smoke result's
`WindowsErrorEvents` and Windows Application log for `.NET Runtime`,
`Application Error`, or `Windows Error Reporting` entries. CLR-level failures
such as `c00000fd` stack overflow can bypass the game's crash dialog entirely.

## Verified 2560x1440 Coordinates

- Main menu `新游戏`: `1280,714`
- Tribe selection default first item: `1280,526`
- Difficulty `普通`: `1280,654`
- Top-left clan/support hover: `78,24`
- Top-left `氏族` button: `64,57`

## Manual Test Discipline

- Avoid clicking external webpages, challenge login, and forum links.
- Prefer a fixed test save for in-game UI cycles. The latest verified local
  fixed state is `Quicksave.AtGSave`; load it from the main-menu `读取存档`
  screen before retesting terrain, clan-join notifications, knowledge-screen
  availability, or main-loop hovers that depend on random start state.
- If a new random game is needed to expose a problem, save it before fixing so
  the same state can be reloaded after rebuild/install. Record the save name,
  load path, and any required click/hover coordinates in `black-box-tests.md`.
- If exploring the main game loop, use a fixed operation count or fixed time
  budget, then exit.
- Prefer cropped screenshots and contact sheets for tooltip/text checks. Use
  full-window screenshots for layout and capture-integrity checks.
- New test evidence should go under `.tmp\runs\<timestamp>-<scenario>`. Use
  `tools\Clear-AtGEvidence.ps1 -WhatIf` to report cleanup candidates:

  ```powershell
  powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Clear-AtGEvidence.ps1 -WhatIf
  ```

  Do not delete historical evidence unless the user explicitly approves a
  cleanup.
- Record rough wall-clock time for assess/fix, build, install, smoke, UI test,
  and failure-loop rework. Use the build timing table from `Build-Patch.ps1`
  when comparing bottlenecks.
- Always stop the game before final reporting if it was launched for testing.
