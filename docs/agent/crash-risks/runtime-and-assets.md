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
- VMP-MLE has no active load-list/font limitation: its existing fixed-save
  procedure loads the exact save and reaches `World Screen - Children
  Initialized` while `Crash.AtGLog` remains unchanged. Treat a future
  `SpriteFont` exception as current only if its log event or process exit is
  newly timestamped after the triggering click.

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
  produced no settings dialog or Windows application-error event. The retained
  text handoff recorded complete Chinese main-menu labels with no question-mark
  fallback, clipping, or damaged icons; disposable image evidence was removed.
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
- On 2026-07-26, an alternate-save Clan Screen trace (`CBR-YJC`) completed all
  six trait hover actions but failed the visual text gate: 370 of 1,455 draw
  nodes contained a spurious `级`, including `Clan级Valborg`, save labels, and
  main-menu text. The suspect source is the exact Common rewrite at
  `PropertyBlueprint.BuildDetailsString` `0x06000118:IL_0A14`, whose original
  single space shares user-string token `0x70001d8e` with 201 source `ldstr`
  sites. Treat a whitespace-only managed rewrite as a shared-metadata risk:
  compare the installed DLL with the regenerated patch before changing a
  localized phrase, then refresh the installation and rerun the same save.
- The 2026-07-25 expanded Composite patch rebuilt successfully with the
  DynamicCjk runtime (1,203 warm glyph pairs; 33,450,898-byte payload; no
  merged XNB files). Its manifest-backed refresh reused backup
  `20260629-204950`. The final LF-generated installation reached a stable
  main-menu window after 8.14 seconds and remained stable for 4.08 seconds;
  it reported no crash-log update, crash dialog, settings error, or Windows
  error. Current visual inspection confirms a legible Simplified-Chinese main
  menu. This is startup-only evidence: no new game, save, or unknown Composite
  entry point was opened by the smoke.
- The 2026-07-26 `级` corruption was not a binary-string encoding issue and
  not a broad rewrite of the compiled Common DLL. Runtime display-map export
  had admitted generic Composite templates such as `{arg:0} {arg:2}` →
  `{arg:0}级{arg:2}`; because templates run against every draw string, this
  converted ordinary separators across unrelated UI. Runtime export now
  requires a literal source anchor of at least four alphanumeric characters,
  and a regression test rejects generic templates. The rebuilt map emits 286
  anchored templates and no unsafe template.
- The same visual pass found the live SeasonBanner date in English. It is a
  runtime value from `SeasonBanner.ApplySeasonAndDate`, not a stable source
  literal, so `DisplayStringLocalizer` now accepts only the exact game date
  grammar (`Early|Late` + Gregorian month + `,` + decimal year + ` AD`) and
  renders it as `公元{year}年{month}{上旬|下旬}`. The six required
  `SegoeUI_36_Bold` glyphs are priority-0 warmset entries; without that
  prewarm the first banner draw produced question marks even though its text
  was localized.
- Final manifest-backed installation and startup smoke passed on 2026-07-26:
  stable main-menu window, no crash/settings/Windows-error indicator. The
  fixed `CBR-YJC` save then passed all six Clan Screen trait hovers. Its trace
  drew `公元400年4月上旬` with zero missing glyphs and no English-adjacent `级`;
  the screenshot is visually legible. Full configured black-box coverage on
  the same save recorded 32 passed and 42 skipped points; every skip is a
  scenario record with missing coordinates, not a product failure. Its 4,554
  draw nodes have zero missing-glyph draws and zero English-adjacent `级`
  corruption. The intentionally English clan proper names and the transient
  constructor seed `January 2018 - Winter` remain trace-only observations;
  the captured gameplay banner is the localized date above.
- The 2026-07-26 CBR-YJC diplomacy baseline reached the current-leader panel.
  Its draw trace, rather than OCR, is the reliable source for the small right
  column: it drew `Minor Leader`, `Friends`, `Enemies`, `Approach`,
  `Influence`, `Leverage`, and the malformed dynamic name `该Peucini`. The
  static labels are exact `Screen_Diplomacy.CreateControls_Fixed` operands;
  `Minor Leader` has no direct catalog literal and is a safe exact final-display
  value. The generic `The ` final-display fragment is the cause of `该Peucini`:
  it came from source-specific Common rewrites but was incorrectly exported for
  every composed display string. The same baseline had zero missing-glyph
  draws; its standalone `?` is the normal unknown-map marker, so it is not
  evidence of an apostrophe glyph failure.
- A later final-package diplomacy invocation is invalid test evidence: it
  produced only a main-menu trace (1,158 draw events), with no scenario setup,
  screenshot, or run summary. The harness session stopped before the fixed save
  was applied, so this is neither a product regression nor a diplomacy result;
  rerun the same fixed-save scenario before closing the test session.
- The subsequent `20260726-diplomacy-final-retry` is the valid final package
  result: the fixed `CBR-YJC` save reached the current-leader panel and its
  draw trace contains zero `Minor Leader`, `Friends`, `Enemies`, `Approach`,
  `Influence`, `Leverage`, or malformed `该Peucini` nodes. It instead records
  `小部族领袖`、`友好`、`敌对`、`态度`、`影响力`、`筹码`, with zero
  missing-glyph and question-mark draws. The displayed `The Peucini` is the
  deliberate fallback for an untranslated proper name, not a partial Chinese
  determiner. The exact `ATGCity.BuildTrainingProjectDescription`
  `0x0600086c:IL_00ac` source fragment `in ` now emits an empty string only in
  that completion sentence because the preceding Chinese fragment already ends
  in `于`; no short preposition is exported as a global runtime rule.
- After rebuilding the durable Composite-to-KnownTexts index, the refreshed
  package was reinstalled with the existing manifest backup and passed a
  startup-only smoke on 2026-07-26: the main-menu window became ready in 8.74
  seconds, remained stable for 4.13 seconds across eight checks, and reported
  no crash log, crash dialog, settings, or Windows-error indicator. This smoke
  does not replace the current-leader diplomacy retest that follows it.
- The post-index `20260726-diplomacy-index-final` fixed-save retest passed its
  capture point in 238 ms (2.90-second owned session). Its 446 `draw` nodes
  contain zero target English labels, 18 draws of `小部族领袖`、`友好`、`敌对`、
  `态度`、`影响力`、`筹码`, zero missing-glyph draws, and zero standalone `?`
  draws. `The Peucini（小部族）` and `的 The Peucini` remain intentional proper
  name retention; no malformed Chinese determiner is present. The captured
  final panel visually confirms the six Chinese labels are legible. The
  regenerated package then passed its build-report, font-budget, font-reference,
  and glyph-warmset gates, plus the Patch and RuntimeText unit suites.
- The 2026-07-26 resource-tooltip repair keeps final-display templates disabled:
  they lack an `EntryPoint` at runtime and previously turned unrelated fragments
  into `Seeing该`/`级`. Five exact rich-text rules now own the XDR resource
  descriptions, preserve every concept key, and localize their visible link
  text directly. The final XDR trace has zero targeted English draws and draws
  `消耗全部` with zero missing glyphs.
- Smart quote/apostrophe/dash/ellipsis glyphs are eligible for DynamicCjk and
  are prewarmed in the affected `SegoeUI_15_Bold` row. The fixed-wait Note Mode
  capture visibly renders `切换“备注模式”，可为自己写下简短备注。` with no fallback
  question mark. The final refreshed installation reached a stable main menu in
  7.72 seconds and passed eight stable-window checks with no crash, dialog,
  settings, or Windows-error indicator.
- The first unit run after the `run-10` clan-trait fragment repair failed only
  because `RuntimeDisplayFragmentsPreserveLinks` still expected the former
  two-fragment wording `卷入斗殴`. The new exact final-display fragment
  `engage in Brawls` deliberately takes precedence and produced
  `参与斗殴`; update that assertion, then rerun the suite before packaging.
- Clan-trait random-discovery `run-10` saved
  `v1.4.1   World [IAR-IBO]   游戏开始.AtGSave` and completed all six hover
  points. The actual lower-card traits are `离群索居` (`TRAIT_Reclusive`),
  `北地人` (`TRAIT_Northmen`), and `好斗` (`TRAIT_Aggressive`). Northmen is
  visually Chinese throughout and can be recorded as verified. Reclusive
  visibly retains `commit Theft` and `engage in Brawls`; Aggressive retains
  `there's another` and `engage in Brawls`. The catalog has no literal match
  for those composed values; their final plain-text path uses
  `runtime-map:PlainTextFragments` / `runtime-display-fragment`. Add only the
  exact three final fragments, then rebuild, install, and reload IAR-IBO before
  accepting Reclusive or Aggressive. This is a new-trait run, not a no-new
  discovery sample.
- The fragment repair's rebuilt package reports five exact runtime strings,
  eight plain-text strings, and three plain-text fragments. Text-tag, generated
  alias, font-budget, font-reference, runtime-build-report, and warmset gates
  all printed successful results. A local aggregation wrapper then falsely
  reported them failed because PowerShell retained a prior native-process exit
  code; this is a wrapper defect, not a gate failure.
- The first IAR-IBO fixed-save retest passed all six harness actions and removed
  `commit Theft`, `engage in Brawls`, and `there's another`; its trace now
  draws `犯下盗窃`、`参与斗殴`、`另有`. Visual inspection still found the exact
  plain segment ` on the same` between the localized Clan and Tile links in
  Aggressive. Catalog evidence has four scoped Common operands, but this final
  draw boundary remains `runtime-map:PlainTextFragments` /
  `runtime-display-fragment`; add the exact leading-space fragment
  ` on the same` -> `位于同一`, rebuild and reload IAR-IBO once more. Do not
  verify Aggressive until that final segment is gone.
- The second IAR-IBO fixed-save retest completed all six points in 9.40 seconds.
  Its trace has zero `commit Theft`, `engage in Brawls`, `there's another`, or
  ` on the same` draw nodes and instead records `犯下盗窃`、`参与斗殴`、`另有`、
  `位于同一`. Current lower-card screenshots visibly confirm fully Chinese
  `离群索居`, `北地人`, and `好斗` tooltips with intact concept links and icons.
  Record Reclusive and Aggressive as verified; the totals are now 52 verified,
  2 failed, and 52 unverified. The refreshed package also passed a default
  main-menu smoke (8.24-second readiness, eight stable checks, no crash,
  settings, or Windows-error indication).
- Clan-trait random-discovery `run-11` saved World `WHS-JWN`. Its three actual
  lower-card traits are already verified: Frail, Gregarious, and Petty; do not
  count it as a clean no-new discovery sample. The Frail tooltip visibly drew
  `Max` in the bullet `Max Health Halved`. Catalog entries 2844/2845 trace that
  source literal to `PropertyBlueprint.BuildDetailsString`, but the final draw
  node is the scoped `\u0080Max` plain-text node. The matching active composite
  boundary is `runtime-map:PlainText` / `runtime-display-plain`; add only
  `\u0080Max` -> `\u0080最高`, preserving the bullet. The RuntimeText and Patch
  unit suites passed after adding the exact-node regression assertion (the Patch
  suite emitted only its existing NU1900 package-advisory connectivity warning).
- The `\u0080Max` repair package built successfully with 145 runtime redirects,
  one frame-boundary hook, nine plain-text entries, and four fragments. Its
  post-build gates passed: runtime build report, deterministic glyph warmset
  (1216 font/glyph pairs), and DynamicCjk font budget (33,451,005 bytes, two
  OFL fonts, no merged XNB files). It is safe to install and retest the saved
  WHS-JWN discovery world; do not create another world before this retest.
- The installed package reached the default Chinese main menu in 8.24 seconds
  and remained stable for eight checks over 4.14 seconds, with no crash,
  settings, or Windows-error indication. WHS-JWN's fixed-save retest passed all
  six harness points in 7.77 seconds. Its lower Frail tooltip visibly renders
  `最高生命减半`; the trace has zero `Max` nodes and draws `\u0080最高` with no
  missing glyphs. Gregarious and Petty remain visually clean. Record this as
  one consecutive clean no-new discovery sample, update scenario evidence to
  the three lower traits and WHS-JWN, then create the next new world.
- Clan-trait discovery `run-12` saved World `VRB-PGL`. Its lower-card Eloquent
  is already known, while Herder and Intimidating are newly observed traits.
  Eloquent and Intimidating are visually Chinese, but keep all three records
  pending until the required same-save retest. Herder visibly retains the final
  rich-text nodes `forced into a` before its Profession link and ` outside of`
  before the following link. SQLite has no matching complete dynamic operand;
  the active final-display fragment boundary is the applicable safe path. Add
  only `forced into a` -> `被迫从事` and ` outside of` -> `，且不在`; neither
  fragment changes a concept key. The RuntimeText regression asserts the full
  localized sentence with Profession and Settlement keys intact. RuntimeText
  and Patch unit suites passed after this repair (Patch again emitted only the
  pre-existing NU1900 advisory connectivity warning).
- The Herder fragment repair built successfully with 145 redirects, one
  frame-boundary hook, nine exact plain-text nodes, and six scoped fragments.
  Runtime-build-report, glyph-warmset (1216 pairs), and DynamicCjk font-budget
  gates all passed. Install this package and retest VRB-PGL from the main-menu
  fixed-save route before verifying Eloquent, Herder, or Intimidating.
- The refreshed installation reached the default Chinese main menu in 8.23
  seconds, remained stable for eight checks over 4.14 seconds, and reported no
  crash, settings, or Windows error. VRB-PGL's fixed-save retest passed all six
  points in 9.38 seconds. It has zero `forced into a` and `outside of` trace
  nodes and instead draws `被迫从事` plus `，且不在`; the three lower-card
  screenshots visibly confirm Eloquent, Herder, and Intimidating as Chinese
  with intact concept links and icons. Mark all three verified. Totals are now
  54 verified, 2 failed historical residuals, and 50 unverified; Herder and
  Intimidating are new coverage, so reset the clean no-new discovery counter.
- Clan-trait discovery `run-13` saved World `KDW-EPG`. Marshmen and Eager are
  newly observed lower-card traits; Violent is already verified. Marshmen's
  first bullet visibly draws `No extra`, despite an old static catalog candidate
  for that literal: the actual final draw is the precise `\u0080No extra` node.
  Map only that node to `\u0080无额外` through `runtime-map:PlainText`, preserving
  the bullet and leaving the legacy IL path untouched. Eager is visually Chinese
  but remains pending until the same-save retest. RuntimeText and Patch suites
  pass after the new exact-node assertion (Patch has only the existing NU1900
  advisory connectivity warning).
- The first KDW-EPG repair build did not complete: `Build-Patch.ps1` was denied
  access while refreshing the generated ClanCard alias
  `patch/Content/Images/Interface/ScreenSpecific/ClanCard/畜牧/CrowdBG.xnb`.
  The subsequent read-only static gates printed passes against prior complete
  artifacts and are not evidence for this edit. Inspect for a stale process or
  transient file lock, then retry the build before any installation or game
  retest.
- No game or test-harness process remained, and the lock cleared without any
  destructive action. The single build retry completed successfully: 145
  redirects, one frame-boundary hook, ten exact plain-text nodes, and six
  scoped fragments. Fresh post-build runtime-report, warmset (1216 pairs), and
  DynamicCjk budget gates passed. Install this successful output and retest
  KDW-EPG; the earlier static-gate pass remains explicitly non-authoritative.
- The successful package reached the default Chinese main menu in 8.23 seconds
  and remained stable for eight checks over 4.14 seconds, with no crash,
  settings, or Windows error. KDW-EPG's fixed-save retest passed all six points
  in 9.37 seconds. The trace has zero `No extra` nodes and draws `无额外`; lower
  screenshots visibly confirm Marshmen, Eager, and Violent with intact icons
  and concept links. Mark Marshmen and Eager verified. Totals are 56 verified,
  2 failed historical residuals, and 48 unverified; both newly verified traits
  reset the clean no-new discovery counter.
- Clan-trait discovery `run-14` saved World `VNV-WKZ`. Its lower-card traits
  are Confident, Afraid of Water, and already-verified Vigorous. Afraid of
  Water visibly retains standalone `seafaring` in the final forced-profession
  sentence; catalog search has no complete dynamic operand for it. Map only the
  exact final plain-text node `seafaring` -> `航海` at
  `runtime-map:PlainText`, leaving the surrounding rich-text nodes intact. Both
  unit suites pass after the exact-node regression assertion (Patch has only
  the existing NU1900 advisory connectivity warning). Build, install, and
  retest VNV-WKZ before verifying Afraid of Water.
- The VNV-WKZ repair package built successfully with 145 redirects, one frame
  hook, eleven exact plain-text nodes, and six scoped fragments. Fresh runtime
  build-report, glyph-warmset (1216 pairs), and DynamicCjk budget gates passed.
  Install this package and use the main-menu fixed-save route to retest VNV-WKZ
  before changing the Afraid of Water verification state.
- VNV-WKZ's first fixed-save retest passed the harness actions and the default
  main-menu smoke was stable (8.23-second readiness, eight checks, no crash or
  settings error), but visual evidence still drew `seafaring`. Its final text
  node contains Chinese text before that word, so the PlainText exact entry did
  not match. Move only `seafaring` to `PlainTextFragments` and assert the mixed
  node with its Profession link; both unit suites pass after that correction
  (with only the existing NU1900 advisory warning in Patch). Rebuild, reinstall,
  and retest the same save before accepting Afraid of Water.
- The fragment-corrected VNV-WKZ package built successfully with 145 redirects,
  one frame hook, ten exact plain-text nodes, and seven scoped fragments. Fresh
  runtime-report, warmset (1216 pairs), and DynamicCjk budget gates passed.
  Install it and retest VNV-WKZ from the main-menu fixed-save route before
  changing Afraid of Water's verification state.
- The installed fragment-corrected package reached the default Chinese main
  menu in 8.23 seconds and stayed stable for eight checks over 4.12 seconds,
  without crash, settings, or Windows error. VNV-WKZ's final fixed-save retest
  passed all six points in 9.12 seconds. Its trace has zero `seafaring` nodes
  and draws `航海`; screenshots visibly confirm Confident, Afraid of Water, and
  Vigorous with intact concept links and icons. Reconfirm Confident and mark
  Afraid of Water verified. Totals are 57 verified, 2 failed historical
  residuals, and 47 unverified; the new trait resets the clean no-new counter.
- AVR-WPR's patched baseline reproduced the Deserted Farm title/body, the
  normal deer-herd body variant, the wheat-field body variant, and the clan
  family countdown's `in`. The resource body variants are final rich text and
  require exact mappings; do not restore a global Composite template. The
  first static rebuild rejected display labels on direct `[WHEAT]` and
  `[WHEAT-FARM-1]` references as invalid concept keys. Keep these direct
  references unchanged in the translation and translate only their surrounding
  literals. The next static rebuild also rejected reordered `HARVEST`, `TILE`,
  and `COLD` keys; preserve their source order in Chinese. The third rejection
  confirmed `[EXPLORER]` is also a direct reference rather than a concept link,
  so it must remain verbatim. No output was installed from any rejected build.
- The first successful AVR-WPR build produced eight exact runtime mappings and
  no global templates, but the Composite catalog gate then found its durable
  runtime-map index stale (25 bindings recorded versus 38 source definitions).
  Regenerate `translations/composite-text-rules.json` from the current source
  maps before treating any static gate or installed artifact as current.
- Composite-catalog regeneration initially rejected the wheat rule because its
  localized second sentence added a third direct `[WHEAT]` tag while the source
  has only two. The second-sentence `Wheat` is a literal: localize it as plain
  `小麦`, preserving the two source direct references and all concept links.
- After regenerating the Composite authority, its CSV gate still found the
  SQLite occurrence catalog predated the expanded 38 runtime-map definitions.
  Rebuild the source occurrence catalog, then rerun the Composite gate; never
  manufacture reverse links in a generated CSV view.
- AVR-WPR first installed retest passed the normal deer-herd exact body, but
  showed that Deserted Farm is emitted as two independent final strings and
  that `Fields of Wheat` is a literal prefix, not `[WHEAT]`. Replace the unused
  combined farm rule with one exact second sentence plus a standalone first
  sentence mapping; make the wheat exact source literal. Keep the same fixed
  save for the next retest.
- The narrowed-rule build initially stopped while replacing the generated
  `patch/Content/Config/Misc/Religions.xml`: Windows reported a user-mapped
  section open. No new output was installed. Confirm that no game or harness
  process remains, then retry once without deleting files.
- The safe build retry succeeded after confirming no residual game or harness
  process. The patched main menu was stable in 8.19 seconds plus eight checks
  over 4.12 seconds with no crash, settings, or Windows error. AVR-WPR then
  passed Deserted Farm and the normal deer herd, but wheat still drew `Fields
  of Wheat` and `Wheat can no longer be`. The trace proves that wheat is split
  at rich-text boundaries (`Fields of Wheat can be`, `Harvested`, ` by a`,
  ` or`, ` to`, and the second-sentence literals), so remove the unused whole
  exact mapping and add only the observed post-boundary fragments before the
  next fixed-save retry.
- AVR-WPR's clan-card retry still drew `(+1 in 12`. Inspection of string token
  `0x7000053e` confirmed its byte-exact operand is ` in `, and the patch
  executable already contains `，还需` at `GetMinTurnsToTrain` IL `018c`; that
  method only builds a different training-description fragment. The actual
  card is a final rich-text node beginning `(+1 in `. Keep the byte-exact IL
  mapping, then add only final-boundary `(+1 in ` -> `(+1，还需 `; do not add a
  global `in` mapping.
- Final AVR-WPR verification passed with the installed patch: the three
  resource-tooltip points completed in 8.13 seconds and the clan family
  countdown completed in 4.06 seconds. The resource trace draws `小麦田可被` and
  `小麦无法再采收，若`; the card trace draws `(+1，还需 12 回合)`. The final main-menu
  smoke reached readiness in 8.17 seconds and remained stable for eight checks
  over 4.12 seconds, with no crash, settings, or Windows error. Runtime output
  remains 7 exact, 16 plain, 14 final-boundary fragments, and zero templates.
- The prior AVR-WPR resource conclusion is reopened by the 2026-07-27 user
  capture: Deserted Farm still renders `It may still contain useful supplies,
  and can be investigated,` before the localized Explorer link. The rejected
  exact rule includes `[EXPLORER]`, but the runtime actually emits the literal
  and link as separate final-display nodes. Do not reuse its Passed result;
  add and test the observed literal-only node on the same fixed save.
- The corrected AVR-WPR fixed-save recheck took 8.237 seconds and failed only
  Deserted Farm (2.535 seconds); deer and wheat remained passed. Its actual
  final draw is `It may still contain useful supplies, and can be
  investigated，由n`. The broad ` by a` fragment locally changes the prefix of
  ` by an`, leaving `n`; replace this path with an ordered, complete
  pre-Explorer literal mapping and retest the same save. Do not treat a title,
  first sentence, or partial trace as full-tooltip coverage.
- A trace-only diagnostic build captured the actual `LocalizeRichText` input:
  `This is a farm that has been recently abandoned.\r\n\r\nIt may still
  contain useful supplies, and can be investigated by an [EXPLORER].`.
  Therefore the old second-sentence exact rule cannot match. Replace it with
  one exact two-sentence rich-text mapping that retains `[EXPLORER]` and places
  `调查` after the link; remove the trace hook before the final build and retest.
- The final package adds that exact two-sentence mapping and removes the trace
  hook. Runtime output is 8 exact, 16 plain, 14 final-boundary fragments, and
  zero templates. The main menu reached readiness in 8.25 seconds and stayed
  stable for eight checks over 4.13 seconds, without crash, settings, or
  Windows error. AVR-WPR then passed all three resource points in 8.217
  seconds: the farm trace draws `这是一座最近被遗弃的农场。`, `其中可能仍有有用的
  物资，可由`, linked `探险者`, and `调查。`, with no English or residual `n`.
- Clan-trait discovery `run-15` saved World `JEV-MCR` and passed all six hover
  points in 9.437 seconds. The actual lower-card tooltips were Envious,
  Sensitive, and already-verified Disgraced. Their captured titles and every
  visible effect line are Chinese; no English or raw keys occur in those three
  tooltip crops. Record Envious and Sensitive as verified, retain Disgraced's
  prior verification, and continue sampling because all-106 coverage is not
  yet met.
- The historical `EZN-YZD` fixed-save recheck passed its six hover actions in
  8.569 seconds, but it did not reproduce either recorded failure: its lower
  card tooltips are Reserved, Violent, and Attentive. All three are Chinese,
  yet that is only confirmation of already-verified traits and cannot clear
  Demanding or Low Fertility. Keep both historical records failed until their
  actual trait tooltips are observed again in a reproducible saved world.
- Clan-trait discovery `run-16` saved World `LJV-CWC` and completed its six
  actions in 8.474 seconds. Fecund is fully Chinese and may be verified. Low
  Fertility visibly retains `decreased by -10%` twice, while Easily Cold
  retains `unable to spend the winter`; mark both as failed evidence on this
  save. Query the exact final-display inputs and their Composite entries before
  modifying the runtime map, then rebuild and retest this same world.
- The first LJV-CWC repair build passed runtime-report and 1216-pair glyph
  warmset gates, but the Composite CSV gate stopped before installation: the
  persistent occurrence catalog predates the two new runtime-map definitions.
  This is an index-refresh requirement, not permission to skip the gate. Keep
  the build uninstalled; rebuild the source occurrence catalog and rerun the
  Composite gate before installation or fixed-save retest.
- The occurrence refresh imported 18,907 source records and the rerun Composite
  gate passed (11,445 entries, 14 rules). An initial installer command used the
  obsolete `tools/` path and terminated before touching the game directory;
  invoke the repository-root installer next, then perform the normal smoke and
  LJV-CWC fixed-save retest.
- The corrected LJV-CWC package installed cleanly. Main-menu smoke reached
  readiness in 8.18 seconds and remained stable for eight checks over 4.11
  seconds with no crash, settings, or Windows error. The 9.456-second
  fixed-save retest draws `降低-10%` for Low Fertility's two resource effects;
  Easily Cold draws `很可能变得相当不满 数月内，如果无法在冬季留在` before its
  existing recursive-hover node. No target English token is drawn. Mark both
  traits verified, retain Fecund's clean discovery verification, and continue
  all-106 sampling.
- The 2026-07-27 AVR-WPR user report correctly exposed a test-oracle gap: a
  forbidden-English assertion alone can pass when the pointer misses the full
  body text. The current installed fixed-save run now includes mandatory
  final-draw assertions for the full Deserted Farm title/body/link sequence.
  It completed all three resource points in 8.207 seconds; the farm rendered
  `这是一座最近被遗弃的农场。`, `其中可能仍有有用的物资，可由`, linked `探险者`, and
  `调查。`, with no English or trailing `n`. No game patch content changed in
  this harness-only correction.
- Clan-trait discovery `run-17` saved World `DGK-OCG` and completed its six
  hover actions. The actual first lower-card trait is Afraid of Animals, whose
  final draw retains ` VS Mounted单位减半` and a separate ` in the` node in its
  desire sentence. Do not alter the `Mounted` config ID: it is a logic token
  in `ClanTraits.original.xml`. The literal `VS` is a display candidate at
  `AtTheGatesCommon.ns_Properties.PropertyBlueprint.BuildDetailsString`
  (`0x06000118`, IL offset 2163), while the desire residue requires capture of
  the complete pre-localization rich text. Dabbler and Wasteful were visually
  clean in the same saved world and are recorded separately; rebuild and
  fixed-save retest only after the two Afraid-of-Animals paths are isolated.
- The final `DGK-OCG` same-save retest passed after adding the entry-specific
  rich-text fragment for the profession/discipline clause, the display-only
  `VS` IL rewrite, and a final-display `Mounted` fragment. Main-menu smoke
  reached readiness in 8.17 seconds and held stable for eight checks over
  4.12 seconds without crash, settings, or Windows errors. The 8.855-second
  hover session visually and in its final-draw trace rendered `战力对骑乘单位减半`
  and `职业，所属为畜牧纪律`, with zero `VS`, `Mounted`, or `in the` residuals.
  The `Mounted` XML config ID was not changed. Continue the all-106 trait
  sampling from a new deterministic world.
- Discovery `run-18` created World `KDG-LYR` and found Vigorous, Woodsmen,
  Lazy, Obstinate, Dutiful, and Brown Thumb. The Brown Thumb final tooltip
  retains `in the` between the linked profession and the `AGRICULTURE`
  discipline. Record that trait as failed before changing the patch; this is a
  second concrete entry point for the bounded profession/discipline rich-text
  localization family. Retest the same save after adding its exact structure.
- The KDG-LYR fixed-save retest passed after adding the exact `AGRICULTURE`
  profession/discipline rich-text fragment. Main-menu smoke was ready in
  8.24 seconds and stable for eight checks over 4.15 seconds with no crash,
  settings, or Windows error. The 7.771-second hover run visibly and in its
  final-draw trace renders `职业，所属为农耕纪律`; `in the` is absent and the
  `AGRICULTURE` concept link remains intact. Brown Thumb is verified.
- The later KDG-LYR minimum-dwell audit exposed a harness-quality gap: the
  old y=610 upper-card coordinates open the clan-card summary rather than a
  trait tooltip. The executor now holds a hover for at least its requested
  duration, but the second trait slot must be coordinate-probed before those
  points can be counted as coverage. The direct y=639 Brown Thumb retest
  remains valid and is not invalidated by this finding.
- The KDG-LYR coordinate probe then established the actual first-card slots:
  y=639 displays `林地人` and y=655 displays `精力旺盛`; y=620 and y=670 still
  open card-detail UI. The common scenario now uses y=655/y=639 for every
  card and needs one corrected six-tooltip recapture before the calibration
  is considered accepted.
- The corrected KDG-LYR six-point recapture passed in 12.727 seconds. All
  six captures were actual trait tooltips: `精力旺盛`, `林地人`, `懒惰`, `顽固`, `尽责`,
  and `拙于园艺`. The visible bodies were Chinese and the final-draw trace had
  no `VS`, `Mounted`, ` in the`, or `, or ` residual. This accepts the new
  y=655/y=639 calibration; it does not claim completion of the all-106 sweep.
- SYI-ITT then proved that the vertical upper-slot location is not reusable
  across every freshly generated card layout: the three y=639 hovers correctly
  opened `离群索居`, `会砍价`, and `怯懦`, but none of the y=655 hovers opened a
  second trait tooltip. Treat KDG-LYR only as a valid same-save regression;
  future random discovery must probe each visible second icon per save rather
  than assuming a universal six-point layout.
- The SYI-ITT bottom-center follow-up found a second, trait-linked regression:
  Eberhardt's mood detail says `Default 心情 is Content (+0)`, includes
  `(苦闷 Trait)`, and begins a condition with `When 不悦`. This is a contextual
  `TRAIT_Miserable` tooltip, not a generic card-summary false positive. It is
  recorded as failed before source inspection and must be fixed/retested on
  this same save.
- The same-save `SYI-ITT` retest now passes in 3.994 seconds. The final draw
  has `Eberhardt为不悦`, `默认`, `为满足`, `（苦闷特质）`, and `当不悦时……`, with no
  `Default`, `Content`, `Trait`, `When`, or English mood connector. The repair
  is deliberately split between the existing `RecalcMood` runtime-display
  template, scoped final-display fragments, the `MOOD_CONTENT` config display,
   and the exact `BuildDescription_Mood` connector at `0x06001731` / IL 285;
   do not replace generic `is` fragments outside those entry points.
- The 2026-07-27 coordinate audit found no relative hover movement or DPI
  fallback: `Win32WindowDriver.Move` scales 2560x1440 client references,
  converts them with `ClientToScreen`, and calls absolute `SetCursorPos`; the
  evidence marker is drawn from the actual cursor position. The fault was a
  test-oracle error: KDG-LYR's six trait slots were treated as universal even
  though SYI-ITT and FII-JKZ proved they are layout-dependent, and a changed
  crop could pass without a trait tooltip. The driver now verifies the actual
  cursor position after every absolute move and no longer emits legacy
  relative `mouse_event` moves during clicks. The random discovery scenario
  is restricted to per-save lower candidates and requires an observed Chinese
  trait title; its former six-slot scenario is Deferred. FII-JKZ's
  `TRAIT_Epicure` hover is recorded failed before localization work because it
  still visibly contains English. A 7.352-second same-save negative retest
  failed that candidate for `outside the`, `Warrior`, `unable`, `spend`,
  `winter`, and `inside`, while the two other candidate trait hovers passed.
- Discovery `run-15` created World `IRM-LMH` and completed the three lower-card
  trait hovers as real localized tooltips: `TRAIT_Competitive` (`好胜`),
  `TRAIT_Gluttonous` (`贪食`), and `TRAIT_Rowdy` (`粗野`). The three secondary
  candidate points produced no trait title and were not counted. The lower
  tooltip bodies retained only localized concept links (`宿怨`, `氏族`, `地块`,
  `犯罪`) and the runtime trace contained no configured English residual.
  Persist these three IDs against the same save and continue discovery with a
  fresh world; do not treat the empty secondary slots as coverage.
- Discovery `run-16` created World `ZLJ-ESX`. The six actual trait tooltips were
  `TRAIT_All_Thumbs` (`笨手笨脚`), `TRAIT_Esteemed` (`受敬重`), `TRAIT_Meek`
  (`温顺`), `TRAIT_Sullen` (`阴沉`), `TRAIT_Green_Thumb` (`园艺能手`), and
  `TRAIT_Low_Fertility` (`低生育`). The All Thumbs tooltip still draws the
  English connector ` in the` between the localized `职业` and `纪律` links;
  record it failed before editing. The other five titles and bodies are
  Chinese. The exact final draw is `职业` + ` in the` + `纪律`, so the missing
  rich-text family is the Crafting discipline variant of the existing
  profession/discipline fragments.
- The ZLJ-ESX same-save retest after adding the CRAFTING fragment passed all six
  hover points in 15.616 seconds. The All Thumbs final tooltip now draws the
  Chinese `职业，所属为工艺纪律` sequence with no `in the` node; the other five
  observed traits remained fully Chinese. Default main-menu smoke after install
  reached the Chinese menu and stayed stable. Mark all six IDs verified against
  the final retest evidence and continue the all-106 sweep from a new world.
- Discovery `run-17` created World `RKG-SPT` and all six fixed trait points passed
  in 15.535 seconds. The observed titles were `北地人` (`TRAIT_Northmen`),
  `涉猎广` (`TRAIT_Dabbler`), `敏感` (`TRAIT_Sensitive`), `热情`
  (`TRAIT_Passionate`), `多产` (`TRAIT_Fecund`), and `服从`
  (`TRAIT_Obedient`). Visual review and the final runtime trace contained no
  configured English residual; persist the six IDs and continue with a new
  world.
- The FII-JKZ same-save retest completed all six points in 15.497 seconds with
  no `in the`, `outside the`, `Warrior`, `unable`, `spend`, `winter`, `inside`,
  or `Resident` nodes. It visibly confirmed `TRAIT_Adventurous` (`爱冒险`),
  `TRAIT_Epicure` (`享乐者`), `TRAIT_Loyal` (`忠诚`), `TRAIT_Calm` (`冷静`),
  `TRAIT_Fecund` (`多产`), and `TRAIT_Paranoid` (`多疑`). This clears the old
  FII Partial evidence; persist all six against `run-fii-final-crafting`.
- The EZN-YZD fixed-save session completed all six points in 15.583 seconds with
  no `Angry` or `Obsessed` nodes, but the current card layout exposed
  `TRAIT_Petty` (`小气`), `TRAIT_Reserved` (`寡言`), `TRAIT_Handy` (`手巧`),
  `TRAIT_Violent` (`暴力`), a duplicate `TRAIT_Handy`, and `TRAIT_Attentive`
  (`专注`). Persist the five unique observations. Do not clear the historical
  `TRAIT_Demanding` Failed state from this save because Demanding was not
  re-observed; continue fresh-world discovery until its tooltip is captured.
- Discovery `run-18` created World `ZBG-OWS` and all six fixed trait points passed
  in 15.514 seconds. The titles were `本地人` (`TRAIT_Local`), `好斗`
  (`TRAIT_Aggressive`), `野性` (`TRAIT_Wild`), `独立` (`TRAIT_Independent`),
  `北地人` (`TRAIT_Northmen`), and `专注` (`TRAIT_Attentive`). Visual review
  and final trace were Chinese with no configured residual; persist the six IDs
  and continue seeking the remaining unverified traits plus 苛求/适应力强.
- Discovery `run-19` created World `JQL-THW` and all six fixed trait points passed
  in 15.514 seconds. Runtime title draws identified `TRAIT_Confident` (`自信`),
  `TRAIT_Intimidating` (`威吓`), `TRAIT_Craven` (`怯懦`), `TRAIT_Vigorous`
  (`精力旺盛`), `TRAIT_Northmen` (`北地人`), and `TRAIT_Wild` (`野性`). Visual
  review and the final trace contained no configured English residual; persist
  the six IDs and continue fresh-world discovery for the remaining 27 traits,
  including the still-unobserved `TRAIT_Demanding` and the historical
  `TRAIT_Adaptable` partial.
- The current-package fixed-save replay of `TYP-EOO` (`run-20-typ-current`)
  passed all six trait points in 15.583 seconds. Runtime title draws were
  `TRAIT_Afraid_of_Water` (`怕水`), `TRAIT_Gluttonous` (`贪食`),
  `TRAIT_Epicure` (`享乐者`), `TRAIT_Woodsmen` (`林地人`), `TRAIT_Greedy`
  (`贪婪`), and `TRAIT_Envious` (`善妒`). The six crops were visually Chinese;
  no configured trait-tooltip residual was present. Persist `TRAIT_Greedy` and
  continue with a fresh world.
- The same-save XF-CB replay after installing all six discipline variants
  (`run-21-retest-disciplines`) rendered `TRAIT_Afraid_of_Fire` (`怕火`) without
  any `in the` draw. The three lower candidates were valid Chinese trait
  tooltips (`怕火`, `涉猎广`, `本地人`); the three secondary slots were empty
  for this save, so the harness returned an overall nonzero result even though
  the repaired trait point passed. Mark `TRAIT_Afraid_of_Fire` verified and
  continue fresh-world discovery.
- Discovery `run-22-current` created World `YHW-VMD`. The three visible lower
  tooltips were `TRAIT_Eloquent` (`善辩`), `TRAIT_Impatient` (`急躁`), and
  `TRAIT_Obstinate` (`顽固`); all were Chinese and the trace had no configured
  trait residual. Secondary slots were empty under this layout, so no new
  verification state was added.
- Discovery `run-23-current` created World `ARH-KDB` and all six points passed in
  15.586 seconds. The observed titles were `TRAIT_Demanding` (`苛求`),
  `TRAIT_Intimidating` (`威吓`), `TRAIT_Reserved` (`寡言`), `TRAIT_Corrupt`
  (`腐败`), `TRAIT_Perceptive` (`敏锐`), and `TRAIT_Lazy` (`懒惰`). Visual crops
  and the final runtime trace were Chinese with no configured trait residual;
  this clears the historical Demanding failure and persists the two newly
  observed IDs.
- Discovery `run-24-current` created World `KYH-MMW`. The three visible lower
  titles were `TRAIT_Smithing_Lineage` (`锻造世家`), `TRAIT_Paranoid` (`多疑`),
  and `TRAIT_Confident` (`自信`). Visual crops and trace were Chinese with no
  configured trait residual; persist `TRAIT_Smithing_Lineage` and continue.
- Discovery `run-25-current` created World `FWR-OFC` and all six points passed in
  15.537 seconds. The observed titles were `TRAIT_Epicure` (`享乐者`),
  `TRAIT_Woodsmen` (`林地人`), `TRAIT_Hoarder` (`囤积者`), `TRAIT_Loyal`
  (`忠诚`), and `TRAIT_Impatient` (`急躁`), with one duplicate Loyal. The
  Hoarder crop was visually Chinese and the trace contained no configured
  residual; persist `TRAIT_Hoarder` and continue.
- Discovery `run-21-current` created World `XF-CB`. The run exposed
  `TRAIT_Afraid_of_Fire` (`怕火`) at the first lower candidate, but its tooltip
  still drew the literal English connector ` in the`; the point failed before
  any edit. The other visible titles were `TRAIT_Dabbler` (`涉猎广`) and
  `TRAIT_Local` (`本地人`), while the remaining candidate slots were empty under
  this layout. Keep the same save for a scoped composite repair and retest; do
  not broaden the rule to unrelated trait templates.
- Discovery `run-26-current` created World `DKK-XXH` and all six fixed points
  passed in 15.584 seconds. The observed titles were `TRAIT_Esteemed`
  (`受敬重`), `TRAIT_Obstinate` (`顽固`), `TRAIT_Adaptable`
  (`适应力强`), `TRAIT_Violent` (`暴力`), `TRAIT_Independent` (`独立`), and
  `TRAIT_Hillmen` (`山地人`). The six crops were visually Chinese, including
  the previously partial Adaptable tooltip, and the final runtime trace had no
  configured `in the` or other trait residual. Persist Adaptable as verified;
  Hillmen was rechecked and remains verified.
- Discovery `run-27-current` created World `APX-LDH`. The three lower points
  passed and showed `TRAIT_Envious` (`善妒`), `TRAIT_Loyal` (`忠诚`), and the
  previously unverified `TRAIT_Strong` (`强壮`); its crop and final trace were
  fully Chinese with no configured residual. The three secondary slots were
  empty in this layout, so the harness returned nonzero and no secondary trait
  was inferred.
- Discovery `run-28-current` created World `WR-STV` and all six fixed points
  passed. The observed titles were `TRAIT_Apathetic` (`冷漠`), `TRAIT_Woodsmen`
  (`林地人`), `TRAIT_Impulsive` (`冲动`), `TRAIT_Lazy` (`懒惰`),
  `TRAIT_Obsessive` (`执念`), and `TRAIT_Gluttonous` (`贪食`). The Obsessive
  crop was visually Chinese and the final runtime trace had no configured
  residual; persist `TRAIT_Obsessive` and continue fresh-world discovery.
- Discovery `run-29-current` created World `QKK-UIF` and all six fixed points
  passed. The observed titles were `TRAIT_Esteemed` (`受敬重`),
  `TRAIT_Envious` (`善妒`), `TRAIT_Adaptable` (`适应力强`),
  `TRAIT_Intimidating` (`威吓`), `TRAIT_Apathetic` (`冷漠`), and
  `TRAIT_Vigorous` (`精力旺盛`). Representative crops and the final trace
  were Chinese with no configured residual; no new verification state was
  inferred.
- Discovery `run-30-current` created World `FFB-OXW` and all six fixed points
  passed. The observed titles were `TRAIT_Epicure` (`享乐者`),
  `TRAIT_Reclusive` (`离群索居`), `TRAIT_Loyal` (`忠诚`),
  `TRAIT_Boisterous` (`喧闹`), `TRAIT_Apathetic` (`冷漠`), and
  `TRAIT_Haggler` (`会砍价`). Representative crops were visually Chinese and
  the final trace had no configured residual; no new verification state was
  inferred.
- Discovery `run-31-current` created World `HVY-VNV` and all six fixed points
  passed. The observed titles were `TRAIT_Low_Fertility` (`低生育`),
  `TRAIT_Calm` (`冷静`), `TRAIT_Reserved` (`寡言`), `TRAIT_Epicure` (`享乐者`),
  `TRAIT_Fastidious` (`挑剔`), and `TRAIT_Competitive` (`好胜`). Representative
  crops were visually Chinese and the final trace had no configured residual;
  no new verification state was inferred.
- Discovery `run-32-current` created World `ZQN-HID` and all six fixed points
  passed. The observed titles were `TRAIT_Reclusive` (`离群索居`),
  `TRAIT_All_Thumbs` (`笨手笨脚`), `TRAIT_Charismatic` (`有魅力`),
  `TRAIT_Northmen` (`北地人`), `TRAIT_Smithing_Lineage` (`锻造世家`), and
  `TRAIT_Apathetic` (`冷漠`). Representative crops were visually Chinese and
  the final trace had no configured residual; no new verification state was
  inferred.
- Discovery `run-33-current` created World `NHN-SVF`. The three lower points
  passed and showed `TRAIT_Paranoid` (`多疑`), `TRAIT_Afraid_of_Fire` (`怕火`),
  and `TRAIT_Resourceful` (`足智多谋`); representative crops and the final
  trace were Chinese with no configured residual. The three secondary slots
  were empty in this layout, so the harness returned nonzero and no new
  verification state was inferred.
- Discovery `run-34-current` created World `RFF-YQG` and all six fixed points
  passed. The observed titles were `TRAIT_Confident` (`自信`),
  `TRAIT_Sullen` (`阴沉`), `TRAIT_Nervous` (`紧张`), `TRAIT_Reserved` (`寡言`),
  `TRAIT_Gregarious` (`合群`), and `TRAIT_Low_Fertility` (`低生育`). All six
  crops were visually Chinese and the final trace had no configured residual;
  no new verification state was inferred.
- Discovery `run-35-current` created World `VWN-OOE`. The visible lower points
  showed `TRAIT_All_Thumbs` (`笨手笨脚`), `TRAIT_Violent` (`暴力`), and
  `TRAIT_Frail` (`虚弱`); representative crop and the final trace were Chinese
  with no configured residual. The secondary slots were empty in this layout,
  so the harness returned nonzero and no new verification state was inferred.
- Discovery `run-36-current` created World `QIU-JEZ` and all six fixed points
  passed. The observed titles were `TRAIT_Obstinate` (`顽固`),
  `TRAIT_Nervous` (`紧张`), `TRAIT_Curious` (`好奇`), `TRAIT_Rowdy` (`粗野`),
  `TRAIT_Gluttonous` (`贪食`), and `TRAIT_Rivermen` (`河民`). Representative
  crops were visually Chinese and the final trace had no configured residual;
  no new verification state was inferred.
- Discovery `run-37-current` created World `UEV-KVV`. The visible lower points
  showed `TRAIT_Craven` (`怯懦`), `TRAIT_Corrupt` (`腐败`), and `TRAIT_Nervous`
  (`紧张`); representative crop and final trace were Chinese with no configured
  residual. The secondary slots were empty in this layout, so the harness
  returned nonzero and no new verification state was inferred.
- Discovery `run-38-current` created World `TOW-XYY`. The visible lower points
  showed `TRAIT_Calm` (`冷静`), `TRAIT_Resourceful` (`足智多谋`), and
  `TRAIT_Attentive` (`专注`); representative crop and final trace were Chinese
  with no configured residual. The secondary slots were empty in this layout,
  so the harness returned nonzero and no new verification state was inferred.
- Discovery `run-39-current` created World `HW-HOJ`. The visible lower points
  showed `TRAIT_Stoic` (`坚忍`), `TRAIT_Violent` (`暴力`), and `TRAIT_Stingy`
  (`小气`); the Stoic crop and final trace were Chinese with no configured
  residual. The secondary slots were empty in this layout, so the harness
  returned nonzero; persist `TRAIT_Stoic` and continue discovery.
- Discovery `run-40-current` created World `ABK-EXC`. The visible lower points
  showed `TRAIT_Stubborn` (`固执`), `TRAIT_Low_Fertility` (`低生育`), and
  `TRAIT_Handy` (`手巧`); representative crop and final trace were Chinese
  with no configured residual. The secondary slots were empty in this layout,
  so the harness returned nonzero and no new verification state was inferred.
- Discovery `run-41-current` did not reach the new-world screen: no save was
  created, the trace stopped at the main-menu footer, and no trait points were
  captured. Treat this as an infrastructure/startup failure rather than trait
  evidence; retry after confirming the game process is clean.
- Review correction for `run-30-current`: the Epicure (`TRAIT_Epicure`, `享乐者`)
  crop was not wide enough to show the full tooltip, and the final draw trace
  contained the residual `被迫从事n`. The source is the overlapping fragment
  mapping `forced into a` -> `被迫从事`, which leaves the `n` from `forced into
  an`; mark Epicure Failed until the new `forced into an` fragment is installed
  and a full-width capture is visually checked.
- Fixed-save `run-43-epicure-full` replayed `FFB-OXW` after the fragment repair.
  All six points passed; the Epicure tooltip was captured in a 1600x650 region
  with its complete border and all body lines visible. The final trace contains
  `如果被迫从事` with no trailing `n`, and no scoped `forced`, `unable`,
  `spend`, `winter`, `inside`, or `Resident` residual. Promote `TRAIT_Epicure`
  back to Verified; keep the widened capture for future discovery runs.
- Final post-install main-menu smoke after the Epicure repair passed: the game
  window became ready in 7.68 seconds, stayed stable for 4.12 seconds, and
  exited cleanup without a crash dialog or updated crash log.
- Post-install default main-menu smoke after the Bow-Legged fragment cleanup
  also passed: the window became ready in 8.19 seconds, stayed stable for
  4.13 seconds, and exited without a crash dialog or crash-log update.
- Discovery `run-44-current` again failed before new-world creation: no save was
  written and the trace stopped during startup/menu rendering. This is startup
  infrastructure evidence only; no trait result was recorded. Retry after the
  clean-process check used for the earlier run-41 failure.
- Runtime localization unit tests initially reproduced the Bow-Legged residual;
  after adding the longest-match `where they're neither within the` and
  `nor the` variants (including space-boundary forms), all runtime text tests
  passed. Rebuild and same-save QKT-QZF retest are required before promotion.
- Fixed-save `run-45-bowlegged-retest` replayed QKT-QZF after installation of
  the rebuilt runtime map. All six points passed with the 1600x650 capture;
  the Bow-Legged (`TRAIT_Bow_Legged`, `罗圈腿`) tooltip has a complete border
  and Chinese body, and the prior `where they're neither` / `nor the` English
  fragments are absent from both screenshot and scoped draw trace. Promote the
  trait back to Verified; retain this full-width capture for future checks.
- Discovery `run-46-current` created a new world successfully and all six
  hovers passed with the widened 1600x650 captures. It rediscovered only
  already-verified traits (`TRAIT_Passionate`, `TRAIT_Demanding` twice,
  `TRAIT_Hoarder`, `TRAIT_All_Thumbs`, and `TRAIT_Meek`); the representative
  tooltip is fully framed and Chinese, with no scoped English residual. No new
  verification state was inferred.
- Discovery `run-47-current` started a new world and the harness completed all
  six point actions, but the full captures show empty secondary hovers at the
  current layout; only three lower tooltips rendered (`TRAIT_Diligent`,
  `TRAIT_Mountaineer`, and `TRAIT_Obedient`). Treat this as a Partial scenario
  result with no new trait verification, and retry after recording the layout
  limitation rather than inferring traits from the empty points.
- Discovery `run-48-current` did not reach a new-world save or any trait
  capture; the trace stopped while the difficulty/new-game menu was rendering
  and the harness process ended without a point result. Record this as a
  startup/infrastructure failure and retry only after the knowledge update.
- Discovery `run-49-current` created a new world and completed all six points
  with full 1600x650 captures. It rediscovered `TRAIT_Dutiful`,
  `TRAIT_Corrupt`, `TRAIT_Afraid_of_Animals`, `TRAIT_Intimidating`,
  `TRAIT_Bow_Legged`, and `TRAIT_Marshmen`; all were already Verified and the
  scoped trace contained no configured English residual. No new state inferred.
- Discovery `run-50-current` created a new world and completed all six points
  with full captures. It rediscovered `TRAIT_Afraid_of_Fire`,
  `TRAIT_Reclusive`, `TRAIT_Bow_Legged`, `TRAIT_Boisterous`,
  `TRAIT_Impatient`, and `TRAIT_Hoarder`; all were already Verified and no
  scoped English residual was present. No new state inferred.
- Discovery `run-51-current` created a new world and completed all six points
  with full captures. It rediscovered `TRAIT_Wild`, `TRAIT_Dutiful`,
  `TRAIT_Easily_Cold`, `TRAIT_Haggler`, and `TRAIT_Apathetic` (one duplicate
  slot); all were already Verified and no scoped English residual was present.
  No new state inferred.
- Discovery `run-52-current` created a new world, but only three lower-point
  tooltips rendered in the full captures (`TRAIT_Boisterous`, `TRAIT_Sullen`,
  and `TRAIT_Fecund`); the secondary points were empty at this layout. Record
  the scenario as Partial with no new verification state and continue retrying.
- Discovery `run-53-current` again stopped during the difficulty/new-game menu;
  no save or trait screenshot was produced and the harness process ended before
  point results. Record this as a startup/infrastructure failure before retry.
- Discovery `run-54-current` created a new world, but only three lower-point
  tooltips rendered (`TRAIT_Strong`, `TRAIT_Paranoid`, and `TRAIT_Sensitive`);
  secondary points were empty in the full captures. Record Partial with no new
  verification state and continue retrying.
- Discovery `run-55-current` created a new world, but only three lower-point
  tooltips rendered (`TRAIT_Stoic`, `TRAIT_Sociable`, and `TRAIT_Stubborn`);
  secondary points were empty in the full captures. Record Partial with no new
  verification state and continue retrying.
- Discovery `run-56-current` created a new world and completed all six points
  with full captures. It rediscovered `TRAIT_Demanding`, `TRAIT_Aggressive`,
  `TRAIT_Impulsive`, `TRAIT_Impatient`, `TRAIT_Handy`, and `TRAIT_Haggler`;
  all were already Verified and no scoped English residual was present. No new
  state inferred.
- Discovery `run-57-current` created a new world and completed all six points
  with full captures. It rediscovered `TRAIT_Curious`, `TRAIT_Frail`,
  `TRAIT_Eager`, `TRAIT_Disfigured`, `TRAIT_Filthy`, and `TRAIT_Lazy`; all were
  already Verified and no scoped English residual was present. No new state
  inferred.
- Discovery `run-58-current` created a new world and completed all six points
  with full captures. It showed the previously unverified `TRAIT_Gentle`
  (`温和`) and `TRAIT_Nomadic` (`游牧`) plus four already-verified traits.
  Both new tooltips were visually inspected in complete 1600x650 captures;
  borders and Chinese bodies are intact and the scoped draw trace has no
  English residual. Promote both traits to Verified.
- Discovery `run-59-current` created a new world and completed all six points
  with full captures. It showed the previously unverified `TRAIT_Rustic`
  (`乡野`) plus five already-verified traits. The Rustic tooltip was visually
  inspected in a complete 1600x650 capture; its two body paragraphs are fully
  Chinese and the scoped trace has no English residual. Promote Rustic to
  Verified.
- Discovery `run-60-current` created a new world and completed all six points
  with full captures. It rediscovered `TRAIT_Passionate`, `TRAIT_Independent`,
  `TRAIT_Peddlers`, `TRAIT_Paranoid`, `TRAIT_Gregarious`, and
  `TRAIT_Disfigured`; all were already Verified and no scoped English residual
  was present. No new state inferred.
- Discovery `run-61-current` created a new world and completed all six points
  with full captures. It rediscovered `TRAIT_Ascetic`, `TRAIT_Nomadic`,
  `TRAIT_Eager`, `TRAIT_Intimidating` twice, and `TRAIT_Easily_Cold`; all were
  already Verified and no scoped English residual was present. No new state
  inferred.
- Discovery `run-62-current` created a new world and completed all six points
  with full captures. It rediscovered `TRAIT_Aggressive`, `TRAIT_Demanding`,
  `TRAIT_Herder`, `TRAIT_Stingy`, `TRAIT_Marshmen`, and `TRAIT_Disgraced`; all
  were already Verified and no scoped English residual was present. No new
  state inferred.
- Discovery `run-63-current` created a new world, but only three lower-point
  tooltips rendered (`TRAIT_Strong`, `TRAIT_Obsessed`, and `TRAIT_Frail`);
  secondary points were empty in the full captures. Record Partial with no new
  verification state and continue retrying.
- Discovery `run-64-current` created a new world and completed all six points
  with full captures. It rediscovered `TRAIT_Afraid_of_Animals`,
  `TRAIT_Stubborn`, `TRAIT_All_Thumbs`, `TRAIT_Disfigured`,
  `TRAIT_Sensitive`, and `TRAIT_Gluttonous`; all were already Verified and no
  scoped English residual was present. No new state inferred.
- Discovery `run-65-current` created a new world and completed all six points
  with full captures. It rediscovered `TRAIT_Nomadic`, `TRAIT_Obstinate`,
  `TRAIT_Lazy`, `TRAIT_Corrupt`, `TRAIT_Brown_Thumb`, and
  `TRAIT_Perceptive`; all were already Verified and no scoped English residual
  was present. No new state inferred.
- Discovery `run-66-current` created a new world, but only three lower-point
  tooltips rendered (`TRAIT_Independent`, `TRAIT_Easily_Cold`, and
  `TRAIT_Haggler`); secondary points were empty in the full captures. Record
  Partial with no new verification state and continue retrying.
- Discovery `run-67-current` created a new world, but only three lower-point
  tooltips rendered (`TRAIT_Respected`, `TRAIT_Apathetic`, and
  `TRAIT_Haggler`); secondary points were empty in the full captures. Record
  Partial with no new verification state and continue retrying.
- Discovery `run-68-current` created a new world and completed all six points
  with full captures. It rediscovered `TRAIT_Craven`, `TRAIT_Greedy`,
  `TRAIT_Independent`, `TRAIT_Nomadic`, `TRAIT_Envious`, and
  `TRAIT_Marshmen`; all were already Verified and no scoped English residual
  was present. No new state inferred.
- Discovery `run-69-current` created a new world and completed all six points
  with full captures. It rediscovered `TRAIT_Ascetic`, `TRAIT_Adventurous`,
  `TRAIT_Miserable`, `TRAIT_Stubborn`, `TRAIT_Rivermen`, and
  `TRAIT_Fast_Learner`; all were already Verified and no scoped English
  residual was present. No new state inferred.
- Discovery `run-70-current` created a new world and completed all six points
  with full captures. It rediscovered `TRAIT_Afraid_of_Animals`,
  `TRAIT_Lazy`, `TRAIT_Dabbler`, `TRAIT_Fecund`, `TRAIT_Rivermen`, and
  `TRAIT_Attentive`; all were already Verified and no scoped English residual
  was present. No new state inferred.
- Discovery `run-71-current` created a new world and the harness returned
  Passed for all six actions, but only the three lower-point captures rendered
  complete trait tooltips; the secondary captures were empty. Record Partial,
  not Passed. The visible lower tooltips were `TRAIT_Peddlers`,
  `TRAIT_Disgraced`, and newly verified `TRAIT_Thorough`; all three full
  1600x650 captures had complete borders/title/body and no scoped English
  residual. This run also confirms that harness action status alone cannot
  establish six-point visual coverage.
- Discovery `run-72-current` created a new world and completed all six points
  with complete 1600x650 captures. It rediscovered `TRAIT_Impulsive`,
  `TRAIT_Obstinate`, `TRAIT_Fastidious`, `TRAIT_Thorough`,
  `TRAIT_Wasteful`, and `TRAIT_Calm`; all were already Verified. The tooltip
  borders, titles, and bodies were complete and no scoped English residual
  was present.
- Discovery `run-73-current` created a new world, but only the three
  lower-point captures rendered complete trait tooltips (`TRAIT_Hoarder`,
  `TRAIT_Thorough`, and `TRAIT_Charismatic`); all three secondary captures
  were empty. Record Partial with no new verification state. The visible
  tooltips were complete in 1600x650 captures and had no scoped English
  residual.
- Discovery `run-74-current` created a new world and completed all six points
  with complete 1600x650 captures. It rediscovered `TRAIT_Northmen`, newly
  verified `TRAIT_Leperous`, `TRAIT_Sensitive`, `TRAIT_Perceptive`,
  `TRAIT_Obedient`, and `TRAIT_Intimidating`; all six tooltip borders, titles,
  and bodies were complete with no scoped English residual.
- Discovery `run-75-current` created a new world, but only the three
  lower-point captures rendered complete tooltips (`TRAIT_Impatient`,
  `TRAIT_Charismatic`, and `TRAIT_Ascetic`); the three secondary captures were
  empty. Record Partial with no new verification state. The visible tooltips
  were complete in 1600x650 captures and had no scoped English residual.
- Discovery `run-76-current` created a new world and completed all six points
  with complete 1600x650 captures. It rediscovered `TRAIT_Gregarious`,
  `TRAIT_Fecund`, `TRAIT_Gentle`, `TRAIT_Adaptable`, `TRAIT_Tense`, and
  `TRAIT_Attentive`; all were already Verified. Tooltip borders, titles, and
  bodies were complete and no scoped English residual was present.
- Discovery `run-77-current` created a new world and completed all six points
  with complete 1600x650 captures. It rediscovered `TRAIT_Sensitive`,
  `TRAIT_Disfigured`, `TRAIT_Tense`, `TRAIT_Epicure`, `TRAIT_Impatient`, and
  `TRAIT_Gregarious`; all were already Verified. Tooltip borders, titles, and
  bodies were complete and no scoped English residual was present.
- Discovery `run-78-current` created a new world and completed all six points
  with complete 1600x650 captures. It rediscovered `TRAIT_Sturdy`,
  `TRAIT_Attentive`, `TRAIT_Gardener`, `TRAIT_All_Thumbs`, `TRAIT_Greedy`,
  and `TRAIT_Suspicious`; all were already Verified. Tooltip borders, titles,
  and bodies were complete and no scoped English residual was present.
- Discovery `run-79-current` created a new world and completed all six points
  with complete 1600x650 captures. It rediscovered `TRAIT_Gentle`,
  `TRAIT_All_Thumbs`, and `TRAIT_Boisterous`; all were already Verified. The
  other three points were empty in the generated cards, but the three visible
  tooltip borders, titles, and bodies were complete with no scoped English
  residual; record Partial for six-point coverage.
- Discovery `run-80-current` created a new world and completed all six points
  with complete 1600x650 captures. It rediscovered `TRAIT_Impatient`,
  `TRAIT_Wild`, `TRAIT_Gentle`, `TRAIT_Gregarious`, `TRAIT_Hoarder`, and
  `TRAIT_Obstinate`; all were already Verified. Tooltip borders, titles, and
  bodies were complete and no scoped English residual was present.
- Discovery `run-81-current` created a new world and completed all six points
  with complete 1600x650 captures. It rediscovered `TRAIT_Impulsive`,
  `TRAIT_Greedy`, `TRAIT_Adventurous`, `TRAIT_Envious`, `TRAIT_All_Thumbs`,
  and `TRAIT_Disfigured`; all were already Verified. Tooltip borders, titles,
  and bodies were complete and no scoped English residual was present.
- Discovery `run-82-current` created a new world and completed all six points
  with complete 1600x650 captures. It rediscovered `TRAIT_Low_Fertility`,
  `TRAIT_Meek`, `TRAIT_Herder`, `TRAIT_Strong`, `TRAIT_Attentive`, and a
  duplicate `TRAIT_Meek`; all were already Verified. Tooltip borders, titles,
  and bodies were complete and no scoped English residual was present.
- Discovery `run-83-current` created a new world and completed all six points
  with complete 1600x650 captures. It rediscovered `TRAIT_Rustic`,
  `TRAIT_Obstinate`, `TRAIT_Wasteful`, `TRAIT_Fastidious`,
  `TRAIT_Smithing_Lineage`, and `TRAIT_Loyal`; all were already Verified.
  Tooltip borders, titles, and bodies were complete and no scoped English
  residual was present.
- Discovery `run-84-current` created a new world and completed all six points
  with complete 1600x650 captures. It rediscovered `TRAIT_Meek`,
  `TRAIT_Corrupt`, and `TRAIT_Bow_Legged`; the remaining three points were
  empty in the generated cards. The visible tooltip borders, titles, and
  bodies were complete with no scoped English residual; record Partial for
  six-point coverage and no new verification state.
- Discovery `run-85-current` did not reach new-world setup: the harness process
  terminated before producing `run-summary.json` or any screenshots; the trace
  contains only main-menu/footer draws. Record an infrastructure/startup
  failure, do not infer trait coverage, and retry after the evidence update.
- Discovery `run-86-current` created a new world and completed all six points
  with complete 1600x650 captures. It showed `TRAIT_Easily_Cold`,
  `TRAIT_Independent`, `TRAIT_Obedient`, `TRAIT_Fastidious`,
  `TRAIT_Obstinate`, and `TRAIT_Creative`; all were already Verified. Visual
  inspection confirmed complete tooltip borders, titles, and bodies, with no
  scoped English residual; the prior incomplete-crop risk was not repeated.
- Discovery `run-87-current` created a new world and completed all six points
  with complete 1600x650 captures. It showed `TRAIT_Epicure`,
  `TRAIT_Woodsmen`, `TRAIT_Sullen`, `TRAIT_All_Thumbs`, `TRAIT_Haggler`, and
  `TRAIT_Paranoid`; all were already Verified. Visual inspection confirmed
  complete tooltip borders, titles, and bodies, and the configured residual
  probes (`从事n`, `forced into an/a`, and the boundary English fragments)
  returned no hits.
- Discovery `run-88-current` created a new world and completed all six points
  with complete 1600x650 captures. It rediscovered `TRAIT_Reserved`,
  `TRAIT_Thorough`, `TRAIT_Petty`, `TRAIT_Nervous`, `TRAIT_Sensitive`, and
  `TRAIT_Eloquent`; all were already Verified. Visual inspection confirmed
  complete tooltip borders, titles, and bodies with no scoped English residual.
- Discovery `run-89-current` created a new world but only three lower points
  produced trait tooltips: `TRAIT_Aggressive`, `TRAIT_Independent`, and
  `TRAIT_Attentive`. Their 1600x650 captures were complete and clean; the
  secondary points were empty or showed a non-trait tutorial bubble. Record
  Partial for six-point coverage and do not infer missing trait coverage.
- Discovery `run-90-current` created a new world and completed all six points
  with complete 1600x650 captures. It showed `TRAIT_Fecund`,
  `TRAIT_Marshmen`, `TRAIT_Loyal`, `TRAIT_Confident`, `TRAIT_Rowdy`, and
  `TRAIT_Afraid_of_Fire`; all were already Verified. Visual inspection
  confirmed complete tooltip borders, titles, and bodies with no scoped
  English residual.
- Discovery `run-91-current` created a new world but only three lower points
  produced trait tooltips: `TRAIT_Independent`, `TRAIT_Wasteful`, and
  `TRAIT_Disgraced`. Their captures were complete and clean; the three
  secondary points were empty or tutorial bubbles. Record Partial for
  six-point coverage and do not infer missing trait coverage.
- Discovery `run-92-current` created a new world and completed all six points
  with complete 1600x650 captures. It showed `TRAIT_Competitive`,
  `TRAIT_Leperous`, `TRAIT_Bow_Legged`, `TRAIT_Independent`, `TRAIT_Lazy`,
  and `TRAIT_Apathetic`; all were already Verified. Visual inspection
  confirmed complete tooltip borders, titles, and bodies with no scoped
  English residual.
- Discovery `run-93-current` created a new world and completed all six points
  with complete 1600x650 captures. It showed `TRAIT_Craven`,
  `TRAIT_Easily_Cold`, `TRAIT_Nervous`, `TRAIT_Northmen`, a duplicate
  `TRAIT_Nervous`, and `TRAIT_Sullen`; all were already Verified. Visual
  inspection confirmed complete tooltip borders, titles, and bodies with no
  scoped English residual.
- Discovery `run-94-current` created a new world but only three lower points
  produced trait tooltips: `TRAIT_Charismatic`, `TRAIT_Ascetic`, and
  `TRAIT_Impatient`. Their captures were complete and clean; the three
  secondary points were empty or tutorial bubbles. Record Partial for
  six-point coverage and do not infer missing trait coverage.
- Discovery `run-95-current` created a new world and completed all six points
  with complete 1600x650 captures. It showed `TRAIT_Craven`, `TRAIT_Haggler`,
  `TRAIT_Fecund`, `TRAIT_Nomadic`, `TRAIT_Wild`, and `TRAIT_Perceptive`; all
  were already Verified. Visual inspection confirmed complete tooltip borders,
  titles, and bodies with no scoped English residual.
- Discovery `run-96-current` created a new world but only three lower points
  produced trait tooltips: `TRAIT_Confident`, `TRAIT_Competitive`, and
  `TRAIT_Leperous`. Their captures were complete and clean; the three
  secondary points were empty. Record Partial for six-point coverage and do
  not infer missing trait coverage.
- Discovery `run-97-current` created a new world and completed all six points
  with complete 1600x650 captures. It showed `TRAIT_Marshmen`,
  `TRAIT_Afraid_of_Animals`, `TRAIT_Northmen`, `TRAIT_Respected`,
  `TRAIT_Gregarious`, and `TRAIT_Dutiful`; all were already Verified. Visual
  inspection confirmed complete tooltip borders, titles, and bodies with no
  scoped English residual.
- Discovery `run-98-current` created a new world but only three points
  produced trait tooltips: `TRAIT_Herder`, `TRAIT_Sensitive`, and
  `TRAIT_Rivermen`. Their captures were complete and clean; the other points
  were empty or tutorial bubbles. Record Partial for six-point coverage and do
  not infer missing trait coverage.
- Discovery `run-99-current` created a new world and completed all six points
  with complete 1600x650 captures. It showed `TRAIT_Vigorous`,
  `TRAIT_Perceptive`, `TRAIT_All_Thumbs`, `TRAIT_Paranoid`,
  `TRAIT_Afraid_of_Water`, and `TRAIT_Adaptable`; all were already Verified.
  Visual inspection confirmed complete tooltip borders, titles, and bodies
  with no scoped English residual.
- Discovery `run-100-current` created a new world but only three points
  produced trait tooltips: `TRAIT_Calm`, `TRAIT_All_Thumbs`, and
  `TRAIT_Obstinate`. Their 1600x650 captures were complete and clean; the
  other three points were empty cards or had no trait tooltip. Record Partial
  and do not infer missing trait coverage.
- Discovery `run-101-current` created a new world and completed all six points
  with complete 1600x650 captures. It showed `TRAIT_Stoic`, `TRAIT_Envious`,
  `TRAIT_Petty`, `TRAIT_Filthy`, `TRAIT_Gluttonous`, and `TRAIT_Impulsive`;
  visual inspection confirmed complete tooltip borders, titles, and bodies
  with no scoped English residual.
- Discovery `run-102-current` created a new world but only three points
  produced trait tooltips: `TRAIT_Calm`, `TRAIT_Impatient`, and `TRAIT_Tough`.
  Their 1600x650 captures were complete and clean; the other three points had
  no trait tooltip. Record Partial and do not infer missing trait coverage.
- Discovery `run-103-current` created a new world and completed all six points
  with complete 1600x650 captures. It showed `TRAIT_Curious`, `TRAIT_Petty`,
  `TRAIT_Curious`, `TRAIT_Peddlers`, `TRAIT_Fast_Learner`, and `TRAIT_Dutiful`;
  visual inspection confirmed complete tooltip borders, titles, and bodies
  with no scoped English residual.
- Discovery `run-104-current` created a new world but only three points
  produced trait tooltips: `TRAIT_Stoic`, `TRAIT_Esteemed`, and
  `TRAIT_Dramatic`. Their 1600x650 captures were complete and clean; the
  other three points had no trait tooltip. `TRAIT_Dramatic` was promoted to
  Verified from the complete lower-point capture. Record Partial for the
  six-point run and do not infer missing trait coverage.
- Discovery `run-105-current` created a new world but only three points
  produced trait tooltips: `TRAIT_Confident`, `TRAIT_Efficient`, and
  `TRAIT_Intimidating`. Their 1600x650 captures were complete and clean; the
  other three points had no trait tooltip. Record Partial and do not infer
  missing trait coverage.
- Discovery `run-106-current` created a new world and completed all six points
  with complete 1600x650 captures. It showed `TRAIT_Local`, `TRAIT_Craven`,
  `TRAIT_Local`, `TRAIT_Reclusive`, `TRAIT_Envious`, and `TRAIT_Obsessive`;
  visual inspection confirmed complete tooltip borders, titles, and bodies
  with no scoped English residual.
- Discovery `run-107-current` created a new world and completed all six points
  with complete 1600x650 captures. It showed `TRAIT_Strong`, `TRAIT_Rowdy`,
  `TRAIT_Imaginative`, `TRAIT_Rowdy`, `TRAIT_Obsessive`, and
  `TRAIT_Gluttonous`; `TRAIT_Imaginative` was promoted to Verified from the
  complete card_3_secondary capture. Visual inspection found no scoped
  English residual.
- Discovery `run-108-current` created a new world and completed all six points
  with complete 1600x650 captures. It showed `TRAIT_Afraid_of_Animals`,
  `TRAIT_Afraid_of_Water`, `TRAIT_Sensitive`, `TRAIT_Fast_Learner`,
  `TRAIT_Ascetic`, and `TRAIT_Local`; visual inspection confirmed complete
  tooltip borders, titles, and bodies with no scoped English residual.
- Discovery `run-109-current` created a new world but only three points
  produced trait tooltips: `TRAIT_Paranoid`, `TRAIT_Filthy`, and
  `TRAIT_Wasteful`. Their 1600x650 captures were complete and clean; the
  other three points had no trait tooltip. Record Partial and do not infer
  missing trait coverage.
- Discovery `run-110-current` created a new world but only three points
  produced trait tooltips: `TRAIT_Herder`, `TRAIT_Obstinate`, and
  `TRAIT_All_Thumbs`. Their 1600x650 captures were complete and clean; the
  other three points had no trait tooltip. Record Partial and do not infer
  missing trait coverage.
- Discovery `run-111-current` created a new world and completed all six points
  with complete 1600x650 captures. It showed `TRAIT_Vigorous`,
  `TRAIT_Gluttonous`, `TRAIT_Northmen`, `TRAIT_Marshmen`,
  `TRAIT_Squeamish`, and `TRAIT_Nervous`; visual inspection confirmed complete
  tooltip borders, titles, and bodies with no scoped English residual.
- Discovery `run-112-current` created a new world and completed all six points
  with complete 1600x650 captures. It showed `TRAIT_Afraid_of_Fire`,
  `TRAIT_Thorough`, `TRAIT_Sullen`, `TRAIT_Low_Fertility`,
  `TRAIT_Reserved`, and `TRAIT_Filthy`; visual inspection confirmed complete
  tooltip borders, titles, and bodies with no scoped English residual.
- Discovery `run-113-current` created a new world and completed all six points
  with complete 1600x650 captures. It showed `TRAIT_Meek`, `TRAIT_Loyal`,
  `TRAIT_Northmen`, `TRAIT_Dabbler`, `TRAIT_Resourceful`, and
  `TRAIT_Sullen`; visual inspection confirmed complete tooltip borders,
  titles, and bodies with no scoped English residual.
- Discovery `run-114-current` created a new world but only three points
  produced trait tooltips: `TRAIT_Confident`, `TRAIT_Hoarder`, and
  `TRAIT_Lazy`. Their 1600x650 captures were complete and clean; the other
  three points had no trait tooltip (one showed a tutorial bubble). Record
  Partial and do not infer missing trait coverage.
- Discovery `run-115-current` created a new world and completed all six points
  with complete 1600x650 captures. It showed `TRAIT_Afraid_of_Animals`,
  `TRAIT_Passionate`, `TRAIT_Intimidating`, `TRAIT_Loyal`,
  `TRAIT_Perceptive`, and `TRAIT_Apathetic`; visual inspection confirmed
  complete tooltip borders, titles, and bodies with no scoped English residual.
- Discovery `run-116-current` created a new world but only three points
  produced trait tooltips: `TRAIT_Obsessive`, `TRAIT_Fast_Learner`, and
  `TRAIT_Low_Fertility`. Their 1600x650 captures were complete and clean; the
  other three points had no trait tooltip. Record Partial and do not infer
  missing trait coverage.
- Discovery `run-117-current` created a new world and completed all six points
  with complete 1600x650 captures. It showed `TRAIT_Ascetic`, `TRAIT_Eloquent`,
  `TRAIT_Charismatic`, `TRAIT_Strong`, `TRAIT_Competitive`, and
  `TRAIT_Smithing_Lineage`; visual inspection confirmed complete tooltip
  borders, titles, and bodies with no scoped English residual.
- Discovery `run-118-current` created a new world but only three points
  produced trait tooltips: `TRAIT_Ascetic`, `TRAIT_Bow_Legged`, and
  `TRAIT_Northmen`. Their 1600x650 captures were complete and clean; the
  other three points had no trait tooltip. Record Partial and do not infer
  missing trait coverage.
- Discovery `run-119-current` created a new world and completed all six points
  with complete 1600x650 captures. It showed `TRAIT_Epicure`,
  `TRAIT_Charismatic`, `TRAIT_Low_Fertility`, `TRAIT_Perceptive`,
  `TRAIT_Gluttonous`, and `TRAIT_Thorough`; visual inspection confirmed
  complete tooltip borders, titles, and bodies with no scoped English residual.
- Final post-build install smoke on 2026-07-28 reached the main menu in 8.22s
  and remained stable for 4.12s (8 checks); no crash log update, crash dialog,
  settings error, or Windows error was observed.
- Runtime glyph performance acceptance fixture passed in Budgeted mode: five
  frames, main-thread P95 2.0ms, maximum single upload 0.6ms, aggregate hit
  rate 0.9, and no fallback glyphs; legacy-mode mismatch and hot-replay
  activity guards also failed as expected.
- NQO-CLM post-fix session `20260728-122935-test-session` passed both resource
  tooltip points on the fixed save: 巨型小麦田 displayed `这是迄今发现的最大麦田之一！`,
  and 蜂巢 displayed `蜂巢可被采收，由采集者或蜂房以产出蜂蜜`. The text
  handoff retained both final tooltip results; disposable captures were removed.
- NQO-CLM final Epicure session `20260728-123043-test-session` passed all six
  tooltip points. The winter clause now localizes the split `unable以` prefix
  before CJK layout and suppresses only the four residual source words within
  a 500 ms budget, removing their inherited English advances while preserving
  the 定居点 concept link. The text handoff retained the final tooltip result;
  the disposable capture was removed.
  Harness readiness markers timed out, but each requested capture contained the
  target tooltip; no crash or error dialog was observed.
- After regenerating the composite catalog (11471 entries, 15 rules),
  CompositeTextCatalog, text-tag, rich-text preservation, concept-link target,
  RuntimeBuildReport, and KnownTextReviewExport gates all passed. Runtime and
  patch unit suites also passed; profession-trait random coverage remains
  intentionally deferred per user decision.
