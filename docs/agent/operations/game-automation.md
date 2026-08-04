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
On the current 125% Windows display scale, harness X/Y values remain absolute
client logical coordinates while saved capture PNGs use scaled pixels. Convert
only from the client-coordinate record, never by copying a coordinate from a
screenshot; a 2026-07-30 VMP-MLE mood retest confirmed this distinction.
Terrain and trait exploratory auto-coverage is intentionally disabled. Use the
archived scenario records and fixed points for an explicitly requested,
user-confirmed targeted review of a known defect; Codex may launch that fixed
save and replay its listed points. Do not launch a generated tile sweep or
random six-point trait pass. Any workflow that would repeatedly create random
worlds requires the user's confirmation first, and the procedure must remain
unchanged until the user manually confirms it behaves correctly.
The Win32 driver re-activates the owned window before every absolute move,
click, fingerprint, and frame capture, then verifies the cursor with
`GetCursorPos`; it never falls back to relative mouse motion.

On this workspace, launch the test harness through the bundled runtime:
`& .\.tools\dotnet\dotnet.exe .\tools\AtG.TestHarness\bin\Release\net8.0-windows\AtG.TestHarness.dll ...`.
The standalone `AtG.TestHarness.exe` needs a global .NET 8 installation and
cannot start here; the bundled runtime avoids that environmental failure.
Its fixed-save selector temporarily promotes the selected save in the external
Steam `Saved Games` directory. In the sandbox this requires the scoped elevated
test command; an access-denied selector failure occurs before the game starts.
`AtG.TestHarness` filters by suite before applying `--scenario`; for a manually
selected scenario whose suite has not been checked, pass `--suite All` to avoid
an otherwise successful zero-point session.

Resolve a user-supplied world keyword in the resolved game's `Saved Games`
directory before invoking the harness, then pass the exact filename through
`--save-name` (or the scenario's `SaveName`). `SaveSelectionLease` only promotes
that exact file by timestamp; it does not search the user profile, infer a world
ID, or isolate other saves. A load-list failure is current evidence only when a
new post-action `Crash.AtGLog` event (or a matching process exit) is recorded
against a pre-action timestamp/bookmark; never infer it from an old log tail.
If a current crash is verified, record it and stop the UI session; do not create
a new world or silently broaden the save-selection procedure.

### Coordinate Calibration Gate

Scenario `X`/`Y` values are expressed in the harness's fixed 2560 x 1440
reference space and are transformed against the live game client at runtime.
The capture is a physical screen image, so its pixels are not automatically a
scenario coordinate. The display scale, client size, borderless/windowed
state, and capture origin must therefore be treated as runtime facts rather
than remembered constants.

Before a new targeted point is allowed to assert localization text, perform a
calibration pass on the same fixed save and interface:

1. Record the intended *control identity* from the user image (for example,
   the fish-school icon, the family-count badge, or the F3 diplomacy button),
   not merely a nearby panel or tooltip rectangle.
2. Move to the candidate reference coordinate and capture the full client with
   the harness cursor marker. Verify that the marker lies on that control and
   that its expected stable state/tooltip is visible. For a click, also verify
   the named destination interface; a changed fingerprint alone is not enough.
3. Record the reference size, observed client/capture size, target identity,
   save name, and marker result alongside the candidate. Promote the point to
   `black-box-scenarios.json` only after this proof.
4. If the marker misses, the tooltip is a neighbour's tooltip, or setup reaches
   another interface, stop that point as `UncalibratedCoordinate`. Do not run
   `ExpectedAll`/`ExpectedNo`, do not infer a translation regression, and do
   not adjust the coordinate repeatedly from the screenshot alone.

Recalibrate whenever display scale, client size, window mode, capture method,
or setup path changes. The 2026-07-30 ERJ-UUX attempt is the governing
negative example: all six entered coordinates were absolute and stable, but
the fish point opened Shallow Water, the clan points did not open their three
requested tooltips, and the purported diplomacy setup did not reach diplomacy.
Those six failures are invalid coordinate evidence, not translation results.

Terrain and trait exploratory auto-coverage remains retired. A fixed-save
replay for a user-confirmed defect may be launched when the user authorizes
that designated run; it must use approved absolute coordinates and may not
silently broaden into a discovery sweep. Do not launch a generated tile sweep
or random six-point trait pass. Any workflow that would repeatedly create
random worlds remains separately gated by the user's confirmation and manual
confirmation that the procedure behaves correctly.
The Win32 driver re-activates the owned window before every absolute move,
click, fingerprint, and frame capture, then verifies the cursor with
`GetCursorPos`; it never falls back to relative mouse motion.

On this workspace, launch the test harness through the bundled runtime:
`& .\.tools\dotnet\dotnet.exe .\tools\AtG.TestHarness\bin\Release\net8.0-windows\AtG.TestHarness.dll ...`.
The standalone `AtG.TestHarness.exe` needs a global .NET 8 installation and
cannot start here; the bundled runtime avoids that environmental failure.
Its fixed-save selector temporarily promotes the selected save in the external
Steam `Saved Games` directory. In the sandbox this requires the scoped elevated
test command; an access-denied selector failure occurs before the game starts.
`AtG.TestHarness` filters by suite before applying `--scenario`; for a manually
selected scenario whose suite has not been checked, pass `--suite All` to avoid
an otherwise successful zero-point session.

Resolve a user-supplied world keyword in the resolved game's `Saved Games`
directory before invoking the harness, then pass the exact filename through
`--save-name` (or the scenario's `SaveName`). `SaveSelectionLease` only promotes
that exact file by timestamp; it does not search the user profile, infer a world
ID, or isolate other saves. A load-list failure is current evidence only when a
new post-action `Crash.AtGLog` event (or a matching process exit) is recorded
against a pre-action timestamp/bookmark; never infer it from an old log tail.
If a current crash is verified, record it and stop the UI session; do not create
a new world or silently broaden the save-selection procedure.

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
