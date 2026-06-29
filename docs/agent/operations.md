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

The smoke test waits until the game window appears, then allows a short stable
render delay before screenshot capture. `-WaitSeconds` is the maximum startup
wait, not an unconditional sleep.

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
