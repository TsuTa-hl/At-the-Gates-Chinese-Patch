# Runtime, Font, and Reload Risks

Read when changing DynamicCjk, fallback fonts, text calibration, SpriteFont
references, asset memory behavior, or loading a save from the running game.

## DynamicCjk

- `DynamicCjk` keeps the original SpriteFonts for Latin text, numbers, and
  private-use icon glyphs. CJK goes through `AtG.RuntimeText.dll` and the two
  bundled OFL Noto Sans SC files under `patch\\Content\\Fonts`.
- A DynamicCjk output needs `patch\\AtG.RuntimeText.dll`, both bundled font
  files, and zero generated merged-font XNBs. `.atg-merged-fonts` belongs only
  to the rollback renderer.
- The shared CJK atlas is capped at eight 1024x1024 RGBA pages (32 MiB). A
  missing/unallocatable glyph must create a diagnostic and fallback marker, not
  reach `SpriteFont.GetIndexForCharacter`.
- Keep CJK measurement, line height, glyph cache key, baseline, and draw path
  on the same calibrated descriptor. Calibration currently uses 1.15 scale
  with a small upward per-size baseline adjustment. Do not apply it to the
  original Latin/icon path.
- After renderer/font/translation changes run `Test-FontPatchBudget.ps1`,
  `Test-RuntimeBuildReport.ps1`, and `Test-FontReferences.ps1`.

## MergedFonts Rollback

- `MergedFonts` is rollback-only for one compatibility cycle. It must install
  only marked merged fonts, preserve original icon glyphs, and use the 15
  Segoe UI subset build.
- Never restore the obsolete 38-font full-corpus build: it exhausted 32-bit
  XNA memory. The subset still needs all IL rewrite, `TEXT.Description.*`, and
  config-node `Nodes.Value` glyphs.

## In-Game Reload Memory Lifecycle

- Loading a save from a running main loop previously raised
  `System.OutOfMemoryException` around map object, terrain, and sprite loading.
  Treat these as memory-pressure symptoms rather than proof of a single leak.
- `Build-GameLoadMemoryPatch.ps1` must preserve the Large Address Aware EXE and
  dispose the old world SpriteBatch, clear known static world roots, and force
  collection at the verified load boundary.
- `ElfTools.Graphics.IdSpriteBatch.Dispose(bool)` may dispose its own index
  buffer, but must not dispose shared `_defaultEffect`.
- Use `Copy-AtGFileIfChanged` in `tools\\AtGFileOps.ps1` for final patched
  outputs because verification can briefly leave them memory-mapped.
- The fixed regression save must load from the main menu and then reload five
  times through the in-game pause menu without updating `Crash.AtGLog` or
  growing private bytes monotonically.

## Runtime Glyph Performance Verification

- The first 2026-07-24 implementation unit session compiled the runtime and
  passed the managed frame-hook tests. It stopped on two test-fixture defects:
  the priority-queue assertion ignored promotion ordering, and Windows
  PowerShell misdecoded non-ASCII literals in the warmset exporter fixture.
  Neither failure reached the game runtime; assess/fix returned to the fixtures
  before another test session.
- The follow-up session passed all RuntimeText tests, including shared
  per-frame budgets, request promotion/deduplication, stable provisional
  metrics, prefix-width wrapping, BGRA alpha conversion, warmset parsing, and
  aggregate performance JSON. The deterministic warmset exporter fixture also
  passed with four font/glyph pairs.
- The first TestHarness verification attempt did not reach compilation because
  the ambient PowerShell `PATH` did not contain `dotnet`. Use the repository
  SDK at `.tools\\dotnet\\dotnet.exe` for harness builds and tests; this was an
  execution-environment failure, not a harness assertion or runtime failure.
- The repository-SDK retry passed all 32 TestHarness tests. This includes
  deterministic `Budgeted`/`LegacySync`, trace, aggregate performance, and
  warmset environment propagation while keeping text tracing opt-in.
- The telemetry-extension session passed all 39 RuntimeText tests and the
  standalone performance-summary fixture. Performance JSON now exposes
  aggregate atlas hit rate and maximum single-upload time, while the summary
  gate checks active-frame P95, upload peak, fallback/hot activity, queue
  limits, atlas pages, mode consistency, and optional LegacySync comparison.
- The LockBits/cache follow-up passed all 40 RuntimeText tests. It verifies
  bottom-up pointer stride conversion in addition to byte-buffer equivalence,
  and verifies that a localization rule update replaces the whole bounded
  result-cache generation instead of allowing stale entries to repopulate it.
- The first full `Build-Patch.ps1` session reached and verified the 145
  redirects plus one frame hook, then failed in the UI-DLL post-processing
  stage because Windows reported `AtTheGatesUI.dll` had a user-mapped section
  open during an in-place `WriteAllBytes`. No game smoke was started from this
  incomplete build; assess/fix must identify the mapping owner or remove the
  in-place write before retrying.
- After changing the byte patcher to stage through a temporary file, the next
  full build failed earlier when the IL-string patcher tried to overwrite the
  same mapped UI DLL. This confirms a persistent destination mapping rather
  than an unclosed byte-array read in the post-processor; no smoke was run.
- Staging both IL-string and byte-level UI outputs through temporary files and
  installing them with `Copy-AtGFileIfChanged` resolved the mapped-destination
  failure. The following full DynamicCjk build completed in 12.1 seconds and
  reported 145 redirects plus one frame hook; the retry helper remains part of
  the build path for transient Windows mappings.
- The post-build static session passed the DynamicCjk font budget
  (33,443,942 bytes, two OFL fonts, zero merged XNBs), runtime build report,
  all managed font references, and warmset schema. The warmset was still the
  intentional header-only sampling seed at this point (zero pairs).
- The optimization-tooling regression passed after the mapped-file fix,
  including IL-string patching through the new staged output path, managed IL
  rewrite validation, mismatch rejection, and image evidence helpers.
- A subsequent Patch.Tests invocation did not enter compilation because
  `dotnet run` attempted to contact the unavailable NuGet service index
  (`NU1301`). The required packages and restored assets already exist locally,
  so the assessed retry is the same Release test with `--no-restore`.
- The `--no-restore` retry was also blocked before compilation because the
  existing assets file retains the failed NuGet source state. Assess/fix will
  use the already-built Release test assembly if current, or restore with
  failed sources ignored; this is still not a test assertion failure.
- The current Release Patch.Tests assembly was newer than all changed patch
  test and frame-injector sources, and its direct offline execution passed all
  19 tests, including the exact single static frame-hook injection test.
- Composite catalog (11,402 entries/10 rules), warmset exporter, performance
  summarizer, and the 13-scenario black-box schema all passed. A global
  `git diff --check` was not usable as a task gate because the pre-existing
  dirty workspace contains extensive trailing-whitespace findings in generated
   temporary review views and generated TSV output; do not rewrite those unrelated
   user changes, and use a scoped implementation-file whitespace check instead.
- The completed patch was refreshed into
  `E:\\Steam\\steamapps\\common\\Jon Shafer's At the Gates` through the
  manifest-backed installer, reusing the original 2026-06-29 backup. The game
  had no running process during refresh.
- The default installed-build smoke passed: the XNA window appeared in 19.72
  seconds, remained stable for 4.16 seconds, did not update `Crash.AtGLog`, and
  produced no settings dialog or Windows application-error event. Visual
  inspection of `.tmp\\game-smoke.png` confirmed complete Chinese main-menu
  labels with no question-mark fallback, clipping, or damaged icons.
- The performance-scenario automation follow-up passed all 32 harness tests
  and the 13-scenario schema. Knowledge now opens with F1 and closes with
  Escape, Clan Screen opens through its verified top-left button, and the new
  `main-menu-fixed-save` owner mode promotes a named save without preloading it
  so the load-flow scenario can exercise the menu itself.
- The first warmset sampling attempt stopped before launching the game because
  the scenario-declared `Quicksave.AtGSave` was not present in the installed
  game's `Saved Games` directory. No trace or UI result was produced; assess
  the available fixed saves and update only the stale scenario binding before
  retrying.
- Read-only save inventory confirmed that the documented OAA-JUH game-start
  save still exists while `Quicksave.AtGSave` does not. The two stale selected
  scenario bindings now reuse
  `v1.4.1   World [OAA-JUH]   游戏开始.AtGSave`, matching the existing religion
  scenario; the updated 13-scenario schema passed before retry.
- The load-flow trace retry correctly passed the five main-menu/load points and
  entered the OAA-JUH world, but six later hover/click points failed only
  because the legacy scenario required a pixel change on visually static
  targets. The same session's process samples grew from about 370 MiB private
  bytes to 1.23 GiB while text trace was enabled. Before reusing this trace,
  assess both the point `AllowUnchanged` flags and whether the JSONL probe is
  rereading/retaining the rapidly growing trace; no crash-log failure occurred.
- Screenshot review corrected that initial diagnosis: five failed toolbar
  points were still capturing the game's loading artwork, while only the final
  tile point had reached the world. The 241 KiB trace probe reads only bytes
  appended after its bookmark and does not retain or reread the full JSONL, so
  it does not explain the observed private-byte growth. The harness now lets a
  point bookmark `Program.AtGLog` before its action and wait for a declared
  ready marker afterward; the load-save point waits up to 45 seconds for
  `World Screen - Children Initialized`.
- The load-ready harness change passed the 13-scenario/131-point schema and all
  33 TestHarness tests with the repository-local SDK. The added test verifies
  that the point bookmark precedes its click and that the exact marker and
  45-second timeout reach the program-log probe.
- The first load-ready retry did not launch the game because the CLI was given
  the singular `--scenario` spelling instead of its required `--scenarios`
  option. This was an invocation error with no runtime evidence; retry with the
  documented plural option.
- The next invocation also stopped before launch: `--scenarios` is the JSON
  document path, while `--scenario` is the optional ID filter, and an owned run
  additionally requires `--game-path`. Retry with all three explicit values;
  no game or rendering evidence was produced by this argument error.
- The correctly invoked load-flow retry waited for the new world-ready marker
  and then exercised the map, passing 8 of 11 points. The remaining load click,
  Religion hover, and tile click all produced the intended visible result but
  were marked failed because their crops kept animating after a verified pixel
  change. Screenshot review found a complete Chinese Religion tooltip and a
  complete Chinese shallow-water tile tooltip with no fallback glyphs or icon
  damage. Process private bytes rose at world load to about 1.24 GiB, then
  remained flat or declined across the sampled UI points instead of growing
  per interface. Assess/fix should retain the no-change failure but accept a
  changed result that cannot become pixel-stable due to ambient animation.
- The animation-aware point fix passed the 13-scenario/131-point schema and all
  34 TestHarness tests. A point still fails when its target crop never changes,
  but a verified change may now pass when ambient animation prevents two
  identical fingerprints; explicitly idempotent points retain their prior
  behavior.
- The final load-flow trace retry passed all 11 points after a cold launch.
  World-ready appeared about 12 seconds after the save click; the strategic,
  nested-hotkey, note, Religion, victory, and tile targets then rendered in the
  loaded world. The trace reported zero missing glyphs in its final records.
  Private bytes peaked near 1.23 GiB at world initialization and ended near
  1.22 GiB, again showing no per-interface growth during this scenario.
- The Knowledge Screen trace session passed all 37 hover points. One animated
  first-hover crop reached its wait limit only after a verified change and
  therefore remained a pass. Private bytes stayed effectively flat at about
  1.29 GiB from screen open through teardown; no per-hover growth was observed.
- The Clan List header trace session passed all 11 hover points. Private bytes
  declined from about 1.29 GiB to 1.27 GiB over the session, and no repeated
  header hover produced sustained memory growth.
- The Clan Screen buttons trace session passed all seven points. The close
  target changed successfully despite an animated crop reaching its stability
  limit. Private bytes remained near 1.29 GiB and finished slightly below the
  post-open sample.
- The Religion Screen trace session passed all three open, label, and close
  points. Both transitions changed successfully despite ongoing animation, and
  private bytes remained flat near 1.24 GiB.
- The first five-trace warmset export produced 16 descriptor records and 1,201
  unique font/glyph pairs; two independent exports had the same SHA-256.
  However, the schema gate rejected their record order because the exporter
  uses PowerShell's default property sorting while the runtime gate requires an
  ordinal serialized-key order. No rebuilt package used this rejected table;
  assess/fix must make the exporter and validator share one explicit sort key.
- After replacing culture-sensitive `Sort-Object` ordering with an explicit
  ordinal comparison, the exporter fixture passed and the five real traces
  produced a valid v1 table with 16 descriptor records and 1,201 unique
  font/glyph pairs. Two actual exports were byte-identical with SHA-256
  `8F679F908E8FA598809F90DDAAAEB303A5DB981D45C3BD5161121634395206FD`.
- The warmset-enabled full DynamicCjk rebuild completed in 8.8 seconds. Its
  runtime rewrite still reports exactly 145 redirects and one frame-boundary
  hook; all managed rewrite inputs were cache-valid and the build completed
  without an error.
- The warmset-enabled post-build static suite passed: DynamicCjk font budget
  (33,450,715 bytes, two OFL fonts, zero merged XNBs), runtime build report,
  font references, the 1,201-pair warmset gate, optimization tooling, the
  11,402-entry/10-rule composite catalog, and the 13-scenario/131-point schema.
  The report records a 2 ms shared upload budget, 16 uploads per frame, eight
  1024-square atlas pages total, and a six-page warmset soft limit.
- The warmset-enabled patch was refreshed into the installed game through the
  manifest-backed uninstall/install path, reusing the original
  `20260629-204950` backup. The refresh completed without a running-game file
  conflict.
- The first warmset-enabled default smoke was process-stable (window ready in
  8.78 seconds, stable for 4.12 seconds, no crash log/dialog/settings or Windows
  error), but visual inspection found `制作组` rendered as `制作?` on the main
  menu. Because the screenshot was captured well after startup stabilization,
  this fails the no-fallback visual gate; assess the descriptor-specific
  warmset and six-page prewarm path before any formal performance comparison.
- A combined diagnostic trace/perf run passed all 11 load-flow points but
  reproduced the persistent main-menu fallback. `制作组` improved from three
  missing glyphs to one, then stayed at one after pending and ready depths both
  reached zero. The first active frame requested 1,178 pairs and filled the
  256-item ready queue; two budget stops per frame coincided with exactly two
  permanently stranded glyphs. This confirms a ready-queue return race, not a
  missing warmset record, font failure, atlas limit, or ongoing memory growth.
- The race fix now peeks before checking the frame budget and dequeues only
  when an upload may proceed; a device-side defer that cannot rejoin a full
  ready queue is returned to pending for safe rerasterization. RuntimeText test
  compilation succeeded with zero warnings, but the first execution command
  used the nonexistent `net8.0-windows` output path; retry the freshly built
  `net8.0` assembly.
- The corrected RuntimeText test invocation passed all 41 tests, including the
  new non-destructive priority-queue peek regression alongside the shared
  budget, queue limits, device reset, LockBits, cache, wrapping, warmset, and
  telemetry coverage.
- The ready-queue race fix rebuilt successfully with zero RuntimeText compiler
  warnings. The full patch completed in 10.0 seconds and retained exactly 145
  redirects plus one frame-boundary hook.
- Its focused post-build gates passed the runtime report, 1,201-pair warmset,
  and DynamicCjk font budget before installation.
- The ready-queue race fix was refreshed into the installed game through the
  manifest-backed installer, again reusing the original backup.
- The race-fix smoke passed: window ready in 8.78 seconds, stable for 4.12
  seconds, no crash/dialog/settings/Windows error. Visual inspection of
  `.tmp\\game-smoke-warmset-racefix.png` confirms `制作组` and every other main
  menu label render completely, with no question-mark fallback, clipping, or
  icon damage.
- The first multi-pass harness build failed at one serializer call because a
  conditional expression mixed `SessionResult` with an anonymous multi-pass
  envelope and selected the wrong generic overload. No game session ran; cast
  the selected payload to `object` before serialization and retry.
- The multi-pass retry compiled with zero warnings and passed all 36
  TestHarness tests. Coverage now verifies one game start/setup/cleanup across
  two plan passes and deterministic UTC slicing into
  `runtime-performance.pass-1.jsonl` and `pass-2.jsonl`.
- The first formal Budgeted Religion Screen run passed all three UI points in
  both same-process passes. Its cold slice passed the performance gates with
  262 frames, zero fallback, 0.301 ms main-thread P95, and a 0.002 ms maximum
  single upload operation. The hot slice failed the no-new-work gate because
  it attributed 24 background rasterizations (with zero uploads and zero
  fallback) to the replay interval. Determine whether warmset work crossed the
  pass boundary or whether the slice analyzer is interpreting cumulative
  counters before accepting or retrying this sample.
- The hot-replay failure was a real redundant-work defect: every
  `MeasureString` glyph-metric cache hit resubmitted its glyph after the prior
  atlas request had completed. The scheduler now requests work only when the
  metric cache creates its first stable reservation. All 42 RuntimeText tests
  pass, including a regression that the first lookup is cold and subsequent
  lookups reuse the reservation without reporting new work.
- The metric-request fix rebuilt successfully in 10.0 seconds with zero
  RuntimeText warnings and retained exactly 145 redirects plus one frame hook.
  The post-build runtime report, 1,201-pair warmset, 33,450,715-byte Dynamic
  CJK font budget, font references, optimization tooling, composite catalog,
  and 13-scenario/131-point black-box schema gates all passed.
- The rebuilt patch was refreshed through the manifest-backed installer,
  reusing the original `20260629-204950` backup. Its default main-menu smoke
  reached a stable window in 9.22 seconds, remained stable for 4.09 seconds,
  and produced no crash, settings, dialog, or Windows error. Current visual
  evidence in `.tmp\\game-smoke-metric-dedup.png` shows complete Chinese menu
  labels including `制作组`, with no fallback question mark, clipping, or icon
  damage.
- The first post-fix Religion Screen performance retry stopped during
  `FixedSave` setup before either scenario pass began: the harness did not
  reach the main-loop marker within its timeout. The program log contains only
  a normal, complete main-menu initialization and no load-flow, crash, or
  settings error. Treat this as a setup/infrastructure failure rather than a
  performance sample; retry with the scenario's explicit designated save.
- The explicit-save Religion Screen retry passed all three UI points in both
  passes. Budgeted cold replay measured 0.299 ms main-thread P95 with zero
  fallback; hot replay measured 0.311 ms P95 with zero fallback, zero
  rasterizations, and zero uploads. Both slices used one atlas page and passed
  all configured performance thresholds, confirming the metric-request
  deduplication fix.
- A second independent Budgeted Religion Screen cold start passed both
  three-point passes. Cold P95 was 0.263 ms and hot P95 was 0.326 ms; both had
  zero fallback, and the hot replay again performed zero rasterizations and
  zero uploads.
- The third independent Budgeted Religion Screen run also passed both UI
  passes. Aggregating the three valid cold starts yields 837 cold frames at
  0.297 ms main-thread P95 and 817 hot frames at 0.326 ms P95. Both aggregates
  have zero fallback; hot replay has zero rasterizations/uploads, the atlas
  stays at one page, and pending/ready depths stay at zero during the measured
  interface intervals.
- All three LegacySync Religion Screen runs passed their UI points, but the
  strict no-fallback analyzer correctly rejected the cold aggregate: each
  legacy cold display deferred 48 draws at its SpriteBatch boundary (144
  total). The three synchronous cold peaks were 12.038, 11.417, and 11.550 ms;
  the aggregate P95 was 0.281 ms. Preserve this as baseline behavior and do not
  weaken the Budgeted zero-fallback gate.
- The accepted LegacySync Religion baseline therefore records its existing
  cold fallback rather than requiring zero; its hot replay has zero fallback,
  0.307 ms P95, and a 1.891 ms maximum. Comparing cold peaks, Budgeted is
  1.347 ms versus LegacySync's 12.038 ms (an 88.8% reduction), so the required
  50% improvement gate passes.
- Three Budgeted Clan Screen Button UI runs completed, and their cold
  aggregate passed at 0.833 ms P95 with zero fallback. The hot aggregate failed
  strict acceptance because run 1 encountered one un-warmed glyph twice,
  causing one rasterization and one upload; runs 2 and 3 had zero hot work.
  This intermittent 2-fallback/1-glyph result must be traced and added to the
  deterministic warmset (or otherwise explained) before replacing the sample.
- A separate trace-enabled diagnostic reproduced one hot rasterization/upload
  without visual fallback and found exactly one observed pair absent from the
  warmset: `SegoeUI_13|13|False` plus `另` (U+53E6), from
  `将氏族切换到另一项`. Merge this real Clan Screen trace into the deterministic
  warmset, rebuild, and discard the pre-update formal samples.
- Merging that diagnostic trace produced a valid v1 warmset with 16 descriptor
  records and 1,202 font/glyph pairs. Two independent exports are byte-identical
  with SHA-256
  `7785CBB3AC77E898B5562C7C11A32A6FB9CE52834C5F5AA14896869A887C949B`,
  and the warmset schema/determinism gate passes.
- The 1,202-pair warmset rebuild completed in 7.1 seconds and retained 145
  redirects plus one frame hook. The runtime report, updated warmset, and
  33,450,719-byte Dynamic CJK font-budget gates passed before installation.
- The 1,202-pair build was refreshed through the manifest-backed installer.
  Its default smoke reached a stable main menu in 9.22 seconds, remained stable
  for 4.10 seconds, and showed no crash, settings, dialog, Windows, fallback,
  clipping, or icon issue in `.tmp\\game-smoke-warmset-1202.png`.
- Replacing the discarded Clan Screen samples with three independent starts on
  the 1,202-pair build passed all 42 UI point executions. The 1,625-frame cold
  aggregate has 0.701 ms main-thread P95, zero fallback, and a 1.529 ms maximum
  single upload; the 1,424-frame hot aggregate has 0.686 ms P95, zero fallback,
  and zero rasterizations/uploads. One atlas page was sufficient and queue
  maxima remained 22 pending/11 ready.
- Three LegacySync Clan Screen runs passed all UI points but demonstrate why
  legacy fallback cannot be a general acceptance gate: cold passes recorded
  1,682 deferred draws and one hot replay recorded 82 (the other two recorded
  zero). Cold main-thread P95 was 0.773 ms with a 24.655 ms peak; hot P95 was
  0.702 ms with an 18.503 ms peak. Use this mode only as the compatibility and
  synchronous-peak baseline; Budgeted remains strictly zero-fallback.
- The accepted Clan Screen comparison uses those observed legacy semantics:
  Budgeted's 4.949 ms cold maximum is 79.9% below LegacySync's 24.655 ms
  maximum, while its 0.701 ms P95 and zero-fallback/hot-zero-work gates all
  pass.
- Three Budgeted Clan List Header runs passed all 66 UI point executions. The
  2,593-frame cold aggregate measured 0.368 ms P95 and the 2,582-frame hot
  aggregate measured 0.408 ms P95; both had zero fallback, and hot replay had
  zero rasterization/upload. The measured intervals stayed at one atlas page
  with zero pending/ready queue depth.
- Three LegacySync Clan List Header runs passed their UI points but recorded
  592 cold and 14 hot deferred fallback draws. Legacy cold P95 was 0.366 ms
  with a 15.368 ms peak; Budgeted cold P95 was 0.368 ms with a 0.962 ms peak
  and zero fallback, a 93.7% peak reduction. The 50% comparison gate passes.
- Three Budgeted Knowledge Screen UI runs passed all 222 point executions with
  zero fallback and zero hot rasterization/upload, but failed the hot
  main-thread target: the aggregate P95 was 1.336 ms (individual hot P95 values
  1.311, 1.284, and 1.412 ms). At roughly 540 cached glyph lookups per frame,
  the hot atlas path was still allocating a formatted descriptor/glyph string
  for every lookup.
- The hot lookup path now caches `FontDescriptor.CacheKey`, uses a
  non-allocating struct key for metric-cache reads, indexes atlas glyphs by
  descriptor then character so cache hits allocate no formatted key, and
  bypasses trigonometry for zero-rotation text. All 43 RuntimeText tests pass,
  including stable descriptor-key allocation and the prior rendering,
  scheduler, reset, cache, wrapping, and telemetry coverage.
- The allocation-free hot lookup rebuild completed in 9.6 seconds with zero
  RuntimeText warnings, exactly 145 redirects, and one frame hook. Its runtime
  report, 1,202-pair warmset, and 33,450,719-byte Dynamic CJK font-budget gates
  passed before installation.
- The allocation-free lookup build was refreshed through the manifest-backed
  installer. Its main-menu smoke reached a stable window in 9.28 seconds,
  stayed stable for 4.13 seconds, and showed no crash, settings, dialog,
  Windows, fallback, clipping, or icon regression in
  `.tmp\\game-smoke-hot-lookup.png`.
- The first post-optimization Knowledge Screen probe passed all 74 UI point
  executions. Cold P95 is 0.740 ms and hot P95 is 0.720 ms, down about 46%
  from the rejected 1.336 ms hot aggregate. Both passes have zero fallback;
  hot replay has zero rasterizations/uploads. This no-trace independent cold
  start is eligible as the first formal sample for the rebuilt version.
- Two further independent post-optimization Knowledge Screen starts also
  passed. The three-start aggregate covers 4,704 cold frames at 0.727 ms P95
  and 4,736 hot frames at 0.775 ms P95. Both have zero fallback; hot replay has
  zero rasterizations/uploads, and measured atlas/queue state remains one page
  with zero pending and ready work.
- Three LegacySync Knowledge Screen runs passed all UI points. Their cold
  aggregate recorded 2,757 deferred fallback draws, 0.733 ms P95, and a
  406.690 ms screen-opening peak; hot replay had zero fallback, 0.754 ms P95,
  and a 369.330 ms peak. Budgeted's 149.525 ms cold opening peak is 63.2%
  lower, while its steady-state P95 and zero-fallback gates pass.
- All three Budgeted main-menu-to-save-to-main-loop runs passed their 11 UI
  points, but the first raw aggregation was rejected because a one-pass harness
  run did not create a session-sliced performance file. It included startup
  warmup before the scenario: 160 fallback draws, 3,541 warm uploads, and a
  5.372 ms upload peak. The session summaries begin after that warmup; extend
  the harness so `--perf --passes 1` also writes `runtime-performance.pass-1`
  before judging this scenario.
- The harness now splits every owned performance run, including one-pass cold
  scenarios, at the recorded `SessionResult` time interval. All 37 TestHarness
  tests pass, including the new single-pass timestamp slicing regression.
- The corrected one-pass Budgeted slices still fail the formal cold gate: 108
  fallback draws and a 6.135 ms maximum upload. Two runs first submitted about
  1,181 warm requests in their scenario frame, proving warmset registration at
  font load is too late for the first main-menu display. Start warmset work
  from the early GameCore draw hook so rasterization and bounded uploads run
  during the loading frames before the menu appears; retain the 2 ms/16-glyph
  limits and retry the three cold starts.
- `RuntimeGlyphWarmset.Prime` now creates one descriptor per warmset font at
  RuntimeGlyphScheduler initialization, before later FontRegistry registration
  can repeat it. This relies only on the private CJK font and keeps warm work
  on the existing background worker. All 43 RuntimeText tests pass after the
  early-prime change.
- The first early-prime package attempt compiled RuntimeText with zero warnings
  and retained the 145 redirects/one frame hook, but stopped in the config-node
  stage with `The requested operation cannot be performed on a file with a
  user-mapped section open.` No game process was present; do not overwrite or
  kill unrelated user shells. Recheck the lock and retry the normal build after
  the transient mapping releases.
- The normal early-prime rebuild retry completed in 8.0 seconds with zero
  RuntimeText warnings, 145 redirects, and one frame hook. The runtime report,
  1,202-pair warmset, and 33,450,719-byte Dynamic CJK font-budget gates pass.
- The early-prime package was refreshed through the manifest-backed installer.
  Its default smoke reached a stable main menu in 9.25 seconds, remained stable
  for 4.10 seconds, and visual inspection found complete Chinese menu text with
  no fallback, clipping, icon, crash, settings, dialog, or Windows error.
- The first early-prime load-flow probe passed all 11 UI points and reduced
  the session cold fallback to eight draws, with no upload-budget violation,
  but still fails the strict zero-fallback gate. Capture a trace-enabled probe
  to identify the remaining first-menu glyphs and put them ahead of the wider
  warmset without relaxing the 16-upload frame limit.
- The trace shows that the Draw-entry prime is inherently too late: the first
  main-menu frame submitted all 1,202 warm pairs and drew 28 missing CJK
  glyphs, followed by 20 more on the next frame. The remaining eight
  scenario-sliced fallbacks are those menu strings (`新游戏`, `读取存档`, `选项`,
  `制作组`, `退出`) before bounded uploads can catch up. Move the idempotent
  warmset start to `GameCore::.ctor` (token `0x0600000F`), keep exactly one
  `GameCore::Draw` frame-boundary hook (token `0x06000022`), and gate both
  hook counts before retrying the three cold starts.
- The constructor-prime package compiled with zero RuntimeText warnings and
  passed all static gates: 145 redirects, one Draw frame hook, one startup
  warmset hook, warmset v1 with 1,202 pairs, six-page warm cap, 2 ms/16-upload
  budget, and the 33,450,719-byte font budget. The refreshed installation's
  default smoke reached a stable main menu in 9.24 seconds and stayed stable
  for 4.12 seconds; visual inspection found Chinese menu labels with no crash,
  dialog, settings/Windows error, fallback, clipping, or icon regression.
- The first constructor-prime Budgeted load/save/main-loop cold start passed
  all 11 visual points and the strict performance gate: 1,054 scenario frames,
  0.265 ms main-thread P95, 0.182 ms maximum single upload, two late glyph
  requests/uploads, and zero fallback. Continue with two independent cold
  starts before accepting the scene; its hot replay gate will be evaluated
  from the same-process second pass separately.
- A generic two-pass harness attempt is not valid for this combined flow: its
  second pass starts after the first pass has left the game in the main loop,
  while the scenario's first points require the main menu. The load-save row
  never opens and the fixed-save ready marker times out, producing 78 fallback
  draws in an invalid interval. Do not treat this as a renderer regression or
  use its performance data. Keep the three independent process cold starts for
  the full flow; if a same-process hot replay is required, reset to the main
  menu between passes or execute an explicit main-loop-only replay.
- A fixed-save same-process main-loop replay confirms the intended hot path:
  its second pass has 549 frames at 0.186 ms P95 with zero requests,
  rasterization, uploads, or fallback. The first replay pass exposed two
  untraced `SegoeUI_13` glyphs while opening the victory-progress tooltip.
  A trace-enabled diagnosis identifies `查看你的胜利进度。`; regenerate the
  deterministic v1 warmset from all five selected scenario traces plus this
  capture before retrying. The regenerated table contains 1,203 pairs and
  passes the exporter and format tests.
- The first post-regeneration formal cold start still fails, but its telemetry
  isolates scheduling order rather than a missing warmset pair: at frame one
  all 1,203 requests were queued, the worker had filled the 256-glyph ready
  cap, and the first menu needed 28 glyphs before the `SegoeUI_15_Bold` row
  reached the front. This produced 74 fallback draws and a 5.359 ms first-page
  upload. Reclassify only the trace-observed main-menu glyphs as warm priority
  zero (queue priority one, below live misses); put the rest of the load flow
  behind them and retain the bounded 256/4 MiB prepared cache.
- The warmset exporter now promotes only 29 trace-observed `SegoeUI_15_Bold`
  main-menu glyphs to warm priority zero; all other load-flow glyphs are
  priority one and the other selected scenes are priority two. The result is
  deterministic v1 with the same 1,203 unique pairs across 17 descriptor /
  priority records. The exporter regression test verifies the priority-zero
  group and the warmset format gate passes; rebuild and retry from a fresh
  process before accepting this ordering fix.
- The first unit-test attempt for the new `LoadContent` instance-entry hook
  failed at compile time because its test fixture was still declared `static`
  while defining an instance `LoadContent` method. The production injector and
  rewrite dry run were not executed in that failed test session. The fixture
  has been corrected to a sealed class; rerun the unit suites before packaging.
- The corrected unit suites pass: all 43 RuntimeText tests and all Patch tests,
  including a structural assertion that the startup hook injects `ldarg.0`
  immediately before `PrepareStartupGraphics(object)`. The Patch test restore
  emitted only `NU1900` advisory-metadata warnings because NuGet was
  unreachable; compilation and assertions completed successfully.
- The startup-preupload package build completed with zero compiler warnings and
  errors. Static gates confirm 145 redirects, one Draw frame hook, one
  constructor warmset hook, one `LoadContent` graphics hook, deterministic
  warmset v1 with 1,203 pairs, six-page warm cap, 2 ms/16-upload frame limits,
  and a 33,450,898-byte Dynamic CJK font budget. Install this package and make
  a real cold-start smoke/performance observation before accepting it.
- The refreshed startup-preupload installation passed the default main-menu
  smoke: the game window was ready in 9.24 seconds and stable for 4.12 seconds,
  with no crash log, dialog, settings/Windows error, or exit. Visual inspection
  shows complete Chinese menu labels without fallback glyphs, clipping, or icon
  damage. Proceed to the isolated cold load/save/main-loop performance run.
- Budgeted cold start `run-11` passed all 11 load/save/main-loop visual points
  and the strict performance gate. Across 1,041 rendered frames it recorded
  zero fallback, requests, rasterizations, uploads, budget stops, page
  creations, or device resets; all 106,663 lookups were cache hits. Main-thread
  font P95 was 0.258 ms (maximum 3.551 ms), with one atlas page and no queue
  residue. Perform two independent cold starts before accepting reproducibility.
- Independent Budgeted cold start `run-12` again passed all 11 visual points,
  but the strict analyzer rejected it because one single upload measured
  5.226 ms, over the 4 ms cap. This means a small amount of warm work can still
  miss the load-stage preparation window and reach a Draw frame. Inspect that
  frame and its request path before retrying; do not accept the earlier passing
  run as reproducible yet.
- The rejected frame sequence shows the cause: startup uploaded only the 29
  priority-zero menu glyphs, then the first Draw frame still had 917 warm
  requests pending and drained 16 per frame; frame 12 had the 5.226 ms upload.
  `PrepareStartupGraphics` now drains all warm priorities (1 through 3) while
  `LoadContent` owns the main thread, with a 6-second bounded startup window.
  It leaves live priority zero untouched and preserves the regular per-frame
  2 ms/16-upload limits. The RuntimeText and Patch test suites pass after this
  change; Patch restore again reported only the non-fatal NuGet `NU1900` SSL
  advisory-metadata warning. Rebuild/install before the next cold run.
- The all-priority startup-preupload rebuild completed with zero compiler
  warnings or errors. The runtime report and all static gates still pass:
  145 redirects; one each of the frame, constructor-warmset, and graphics
  hooks; 1,203 warm pairs; six-page warm cap; and the 33,450,898-byte Dynamic
  CJK font budget. Refresh the installation before retrying cold startup.
- The refreshed all-priority build also passes the default main-menu smoke:
  window ready in 8.69 seconds, stable for 4.10 seconds, no crash/error dialog
  or early exit, and current visual inspection shows intact Chinese menu text,
  icons, and layout. Run the next independent Budgeted cold start.
- The first formal cold start after the all-priority fix (`run-13`) passes all
  11 visual points and the strict analyzer: 1,036 frames, zero fallback,
  requests, rasterization, uploads, budget stops, page creations, or resets;
  106,085/106,085 lookup hits; main-thread P95 0.299 ms (maximum 2.689 ms).
  Run two more fresh processes for reproducibility.
- The second formal cold start after the fix (`run-14`) also passes all 11
  visual points and the strict analyzer: 1,073 frames; 110,199/110,199 lookup
  hits; zero fallback, render-frame glyph work, queue residue, budget stop,
  page creation, or reset; and main-thread P95 0.280 ms. The unbounded
  11.890 ms timing sample is outside glyph upload work (all upload counters
  are zero), so it does not violate the stated font thresholds. Run one final
  fresh process, then aggregate the three passing samples.
- The third formal cold start (`run-15`) passes all 11 points and, combined
  with runs 13 and 14, passes the strict aggregate: 3,171 frames, main-thread
  P95 0.285 ms, 325,294/325,294 lookup hits, and zero Draw-frame request,
  rasterization, upload, fallback, budget stop, page creation, or device reset.
  The same-process main-loop hot replay also passes all six points twice; pass
  two has 246 frames, 0.077 ms main-thread P95, 6,888/6,888 hits, and zero
  glyph work/fallback. Capture three LegacySync cold baselines next for the
  specified comparison.
- LegacySync baseline `run-1` completes all 11 visual points. Its 1,054 frames
  have a 0.283 ms P95 but a 25.733 ms maximum main-thread font sample, 591
  misses, and 414 fallbacks (108,198 lookups, 99.454% hits). This confirms a
  materially worse cold-path spike than the Budgeted aggregate, but require two
  more independent LegacySync starts before making the percentage comparison.
- LegacySync `run-2` again completes all 11 points with the same 414 fallback
  count: 992 frames, 593 misses, 99.419% hit rate, 0.325 ms P95, and a 27.278
  ms maximum. The repeated over-4-ms peak supports the comparison but one
  independent baseline remains before reporting it.
- LegacySync `run-3` completes all 11 points. Its aggregate with runs 1 and 2
  is 2,932 frames, 0.292 ms P95, 27.278 ms maximum, 1,817 misses, and 1,270
  fallbacks. Against the three Budgeted cold starts (3,171 frames, 0.285 ms
  P95, 11.890 ms maximum, zero misses/fallbacks), the maximum is reduced by
  56.4%, exceeding the required 50% when the synchronous baseline exceeds
  4 ms. The Budgeted default remains installed; finalize the performance
  conclusion and preserve these results as the current test evidence.
- Clan-trait random-discovery `run-1` created and saved a new world
  (`v1.4.1   World [CMY-APT]   游戏开始.AtGSave`) and completed all six configured
  screen points. Three lower-card positions exposed actual traits: `有创造力`
  (`TRAIT_Creative`), `坚韧` (`TRAIT_Tough`), and `小气` (`TRAIT_Petty`); the
  latter two had Chinese bodies, while the three upper-card positions were
  card-detail views rather than trait labels. Runtime text trace and screenshot
  evidence show `TRAIT_Creative` has one real residual English display fragment,
  `, or`, in its dynamically composed discipline list (`冶金, 工艺, or 探索`).
  Query the generated source catalog and composite entry before changing this
  composition, then rebuild and retest the saved world; do not mark the trait
  as fully clean from this discovery run alone.
- The first final-display regression for that residual added only `, or` to
  the runtime fragment map and correctly localized the Oxford-list suffix, but
  its focused RuntimeText test failed: `冶金, 工艺, or探索` became
  `冶金, 工艺、或探索`. The preceding list separator is emitted independently,
  so a second narrow final-display fragment is required before retrying. No
  package, installation, or game smoke was attempted after this failed unit
  session.
- The corrected narrow Common rewrite passed all 43 RuntimeText tests and all
  Patch tests (the latter emitted only the non-fatal `NU1900` advisory-data
  network warning). Packaging and static gates passed: 892 Common rewrites,
  145 runtime redirects, one each of the Draw/constructor/LoadContent hooks,
  warmset v1 with 1,203 pairs, Dynamic CJK font budget 33,450,898 bytes, and
  direct IL inspection confirms `BuildCommaSeparatedListOfNames` offsets
  235/254/275/289/315 now emit `、/和/或/、/、`. The manifest-backed install
  refresh also completed successfully.
- The first post-install retest was not valid evidence despite six harness
  point statuses being `Passed`: its `main-menu-fixed-save` run retained the
  main menu, and the card screenshot plus trace contain no clan trait text.
  Treat this as a fixed-save setup failure, not a localization pass; use the
  explicit `fixed-save` setup mode and inspect the resulting full-window state
  before accepting the card evidence.
- The explicit fixed-save retest loaded the saved clan screen and visibly
  opened the `有创造力` card, but its runtime trace still drew `,` and `, or`
  between `冶金`, `工艺`, and `探索`. This is a real target regression failure:
  the generated patch had been inspected with the three separator operands,
  yet the game did not use those values on the observed draw path. Preserve the
  save and trace, then compare the installed DLL and package pipeline before
  making another translation change; do not accept the harness point statuses
  as visual localization evidence.
- The final-display retry adds only exact `PlainText` entries for `,` and
  `, or` (not broad fragments). RuntimeText tests pass; rebuild and static
  gates pass with five plain-text entries, 15 fragments, 145 redirects, the
  v1/1,203-pair warmset, and the Dynamic CJK font budget unchanged. After the
  manifest-backed refresh, fixed-save retest `retest-creative-3` loaded the
  actual clan screen and completed all six points. Its trace now draws
  `冶金` + `、` + `工艺` + `、或` + `探索`, with zero target `, or`/`or` draw
  nodes. Current screenshots visibly confirm `有创造力`, `坚韧`, and `小气`
  titles and Chinese effect text; `TRAIT_Tough` may be recorded as verified.
- Clan-trait random-discovery `run-2` completed all six points from a newly
  saved game. The three lower-card targets visibly exposed `冷漠`
  (`TRAIT_Apathetic`), `急躁` (`TRAIT_Impatient`), and `有魅力`
  (`TRAIT_Charismatic`). The first two were previously unverified and have
  fully Chinese visible names/effects; `TRAIT_Charismatic` was already
  verified. Record the two new verifications with this saved run before the
  next random discovery; upper-card positions remain non-trait card detail
  views and are not counted.
- Clan-trait random-discovery `run-3` completed all six points from a newly
  saved game. It exposed `敏锐` (`TRAIT_Perceptive`), `合群`
  (`TRAIT_Gregarious`), and `易反胃` (`TRAIT_Squeamish`). `合群` and `易反胃`
  have fully Chinese visible names/effects; `敏锐` is not acceptable yet
  because its visible effect reads `+1 视野 Range`. Query the catalog for this
  residual and repair the exact display boundary, then retest the saved game
  before marking `TRAIT_Perceptive` verified. Do not reroll away this evidence.
- The `Range` fix adds the exact `PropertyBlueprint.BuildDetailsString`
  operand `" Range"` at `0x06000118:IL_0523` and an exact final-display
  `Range -> 范围` fallback. RuntimeText tests, package build, static gates, and
  direct IL inspection pass (893 Common rewrites; six plain-text display-map
  entries). The manifest refresh followed by `retest-perceptive-1` loaded the
  saved third world and completed all six points; its trace has zero `Range`
  draws and instead draws `范围` in the `敏锐` effect. `TRAIT_Perceptive`,
  `TRAIT_Gregarious`, and `TRAIT_Squeamish` can now be recorded as verified.
- Clan-trait random-discovery `run-4` completed all six points from a newly
  saved game (`v1.4.1   World [VC-JCY]   游戏开始.AtGSave`). The three actual
  lower-card trait tooltips expose `学得快` (`TRAIT_Fast_Learner`, already
  verified), `林地人` (`TRAIT_Woodsmen`), and `热情`
  (`TRAIT_Passionate`). The Woodsmen name and terrain-movement body are fully
  Chinese and may be recorded as verified. Passionate is not yet clean: the
  traced RichText node `获得于all` occurs between `经验` and `纪律`; catalog
  evidence narrows it to `PropertyBlueprint.BuildDetailsString`
  (`0x06000118`, exact `all` operand at IL 2881), not a global display word.
  Repair this composed tooltip with the existing scoped Common rewrite, then
  rebuild, install, and retest this saved world before marking Passionate.
- The first scoped repair build stopped before packaging: the catalog's review
  value `all` had normalized away a significant trailing space, so the exact
  rewriter rejected `0x06000118:IL_0B41` with an original mismatch. Direct
  metadata inspection confirms the required operand is `all ` (character
  codes 97,108,108,32). Keep the same token/offset and correct only that exact
  operand before retrying; no installation or game smoke occurred in this
  failed build session.
- The corrected `all ` operand builds successfully (894 Common rewrites) and
  all three static gates pass, followed by a manifest refresh. The first
  `fixed-save` retest is invalid, however: it exits with only 98 measurement
  trace events, zero draw events, no run summary, and no screenshots, leaving
  the game at main-menu measurement. This is a harness/session setup failure,
  not evidence for or against the tooltip change. Inspect the fixed-save
  harness path and rerun a complete saved-world session before accepting it.
- The explicit-save rerun `retest-passionate-3` is valid: all six points
  passed, its trace has 1,416 draw events and no `all`/`获得于all` target node,
  instead drawing `经验` + `：所有` + `纪律`; the lower-card screenshot visibly
  reads `经验：所有纪律翻倍`. `TRAIT_Passionate` is therefore fully Chinese and
  may be recorded as verified. The localized installation remains current;
  continue with an independent new-game discovery rather than treating the
  prior two setup-only retries as discovery attempts.
- The first `run-5` new-game invocation returned before creating its output
  directory, summary, screenshots, or saved-world evidence. It is another
  harness launch/session failure and is not a fifth discovery sample. No code
  changed after the valid Passionate retest; retry the same command only after
  preserving this limitation, and count a run only when it has a complete
  six-point summary plus save evidence.
- The complete retry `run-5` saved `v1.4.1   World [WKZ-LOF]   游戏开始.AtGSave`
  and passed all six points. Its three lower-card traits are previously
  verified `林地人` and `贪食`, plus `忠诚` (`TRAIT_Loyal`); this is one valid
  no-new discovery sample, but Loyalty cannot retain its verification because
  its visible body reads `心情绝不会低于Happy`. The trace isolates the final
  `Happy` node between the localized property fragments. Catalog evidence
  shows that the UI notification copy is already translated and is not this
  path; the source trait uses `MOOD_HAPPY`, so locate the runtime Mood config
  display source and patch that exact config display name before retesting the
  saved world. Do not count this run as a clean no-new sample until Loyalty is
  reverified.
- The `MOOD_HAPPY` config-node repair preserves the original Mood XML's active
  element/value structure (semantic source-parity check passed), changes only
  its stable `name` node to `高兴`, builds successfully, and passes all static
  gates. After installation, fixed-save `retest-loyal-1` passes all six points;
  its trace has zero `Happy` draws and draws `高兴` after `绝不会低于`, while the
  screenshot visibly reads `心情绝不会低于高兴`. `TRAIT_Loyal` can be restored
  to verified. With the repair included, run 5 is the first clean valid
  no-new discovery sample; require one more independent clean no-new new game
  before using the sampling stop condition.
- Clan-trait random-discovery `run-6` saved
  `v1.4.1   World [TEU-OLG]   游戏开始.AtGSave` and passed all six points, but
  it discovered the previously unverified `苦闷` (`TRAIT_Miserable`). Its
  lower-card tooltip is not clean: the visible and traced final nodes contain
  `Upset` in the Mood minimum and `any` in the no-experience condition.
  Catalog evidence identifies `any` as a scoped
  `PropertyBlueprint.BuildDetailsString` operand at `0x06000118:IL_0B21`,
  while the trait's `MOOD_UPSET` requires the same stable Mood-config name
  path used for `MOOD_HAPPY`. Patch only these two exact display values, then
  rebuild and retest this saved world before recording Miserable; run 6 cannot
  count as a no-new sample.
- The `MOOD_UPSET` plus exact `any ` repair builds with 895 Common rewrites
  and passes all static gates. Installed fixed-save `retest-miserable-1`
  passes every point; its trace has zero `Upset` and `any` draw nodes and
  includes `不悦`, while the lower-card screenshot visibly reads `心情永远不高于
  不悦` and `无经验：任意纪律`. `TRAIT_Miserable` can be recorded as verified.
  Because run 6 did yield a new trait, it does not count toward the two
  consecutive clean no-new stopping samples.
- Clan-trait random-discovery `run-7` saved
  `v1.4.1   World [KRQ-HYY]   游戏开始.AtGSave` and passed all six points. The
  actual lower-card hovers show previously verified `高效` and `苦闷`, plus
  newly observed `挑剔` (`TRAIT_Fastidious`). The Fastidious title and all five
  effect lines are visibly Chinese with no English/raw-key residual; it may be
  recorded as verified. This resets the no-new discovery counter.
- Clan-trait random-discovery `run-8` saved
  `v1.4.1   World [NPE-JYK]   游戏开始.AtGSave` and passed all six points. The
  lower-card hovers show verified `足智多谋` and `挑剔`, plus new
  `顽固` (`TRAIT_Obstinate`). Its title and all visible training, experience,
  desire, and feud effects are Chinese without residual English; record it as
  verified. This is another new-trait sample, so do not stop sampling yet.
- Clan-trait random-discovery `run-9` saved
  `v1.4.1   World [CBR-YJC]   游戏开始.AtGSave` and passed all six points. Its
  actual lower-card traits are already verified `顽固`, `苦行`, and `合群`; all
  visible body lines are Chinese, with no new English/raw-key residual. This
  is the first consecutive clean no-new sample after run 8; obtain one more
  independent clean no-new new-game sample before stopping the random
  discovery loop.
- The attempted independent `run-10` invocation produced no scenario-output
  directory, runtime trace, screenshots, or saved world. It is therefore an
  invalid harness-launch result rather than a no-new discovery sample; retry
  the same new-game discovery scenario once and inspect the three lower-card
  hovers before updating the stopping counter.
- Final runtime-text and patch unit suites pass after the rendering and
  localization changes. The static runtime-build, warmset, and font-budget
  gates also pass (1,203 warmset pairs; 33,450,898-byte DynamicCjk payload;
  no merged XNBs). The installed default-main-menu smoke completed normally
  with a stable window, no crash/settings/Windows-error indicators, and a
  visually verified Simplified-Chinese menu screenshot at
  `.tmp/game-smoke-final.png`. No new-game flow or save was created by this
  final smoke.
- The existing-save clan-trait retest for `EZN-YZD` passed all six hover
  points with a current runtime trace free of `Angry`, `Obsessed`, and
  `decreased by`. The loaded world currently exposes `Reserved`, `Petty`,
  `Handy`, `Violent`, and `Attentive`, not the failed `Demanding` or
  `Low_Fertility` traits, so it proves the final-display rules are active but
  cannot change either failed trait to verified. Preserve their failed state
  until a world that actually draws each tooltip is captured.
