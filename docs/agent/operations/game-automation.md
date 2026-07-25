# Game Automation and Crash Handling

Read this file when launching, clicking, hovering, capturing, loading a save,
or inspecting a game crash.

## Process and Window

Close the game before installing. Launch through the resolved executable with
its working directory set:

```powershell
$game = Resolve-AtGGamePath $null
Start-Process -FilePath (Join-Path $game 'At The Gates.exe') -WorkingDirectory $game
```

A merely visible window is not proof that the game is ready. For an in-game
scenario, wait for the selected state marker or stable target interface.

Computer-use may be attempted first. If XNA capture fails, immediately use the
Win32 scripts below; their coordinates are window-relative:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Capture-AtGWindow.ps1 -OutputPath .\.tmp\run.png -MarkCursor
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Click-AtGWindow.ps1 -X 1280 -Y 714
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Move-AtGWindow.ps1 -X 1280 -Y 714
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Capture-Desktop.ps1 -OutputPath .\.tmp\desktop.png
```

For repeatable UI work, prefer `AtG.TestHarness` and the JSON scenario library.
Use one game process and one main-menu fixed-save load per related test session.
Do not derive hover coordinates from cropped evidence images.

## Hover and Capture Discipline

- Wait 700-1500 ms after a hover; poll at most to the 3-second limit.
- Save a full-window image only for a state transition, failure, or crash.
  Passing points should retain a crop and structured text result.
- Load a designated save from the main menu before fixed-save scenarios. Do not
  substitute an in-game pause-menu load unless that behavior is itself under
  test.
- If random terrain, clans, notifications, or commands expose a defect, save
  the state and reload that same save after the repair.

## Crash Procedure

1. Capture the crash dialog and note the pre-click `Crash.AtGLog` timestamp.
2. Click its confirmation button so the game can flush the log.
3. Wait for exit or log timestamp change, then read the newest log block.
4. Record trigger action, log summary, process state, and screenshot summary.
   The log is authoritative; the image documents the visible state.
