# Workflow: Package and Install

## Purpose

Use this workflow to build the patch, validate generated artifacts, refresh the
installed patch, and run the installation smoke test. This workflow owns the
static build gate and install smoke gate.

## Read First

- `docs/agent/operations.md`
- `docs/agent/crash-risks.md`
- `docs/agent/text-sources.md` if the build changes generated text or DLL
  patches.

## Inputs

- Current translation/config/DLL/font patch sources from `assess-and-fix.md`
  or the existing workspace.
- Game path from `-GamePath`, environment variable, or Steam auto-detection.

## Steps

1. Close any running game process before installing.
2. Run the standard build command from `operations.md`.
   - If any `translations\hardcoded-*-il-rewrite.json` map is non-empty, the build
     must use the repo-local `.tools\dotnet\dotnet.exe` and run
     `AtG.IlRewrite.dll`. It must not produce or run `AtG.IlRewrite.exe`.
3. Run text tag validation.
4. Run generated alias validation.
5. Run font budget validation with `tools\Test-FontPatchBudget.ps1`.
   - For `DynamicCjk`, this verifies the two bundled runtime fonts, the
     32 MiB atlas limit recorded in the build report, and the absence of
     generated merged-font XNB files.
   - For `MergedFonts`, it verifies the rollback marker and patched XNB budget.
6. Run IL rewrite mapped-file retry validation with
   `tools\Test-IlRewriteMappedFileRetry.ps1` when IL rewrite tooling or trial
   batch infrastructure changed.
7. Run trial batch safety validation with
   `tools\Test-TrialLocalizationBatchSafety.ps1` when trial batch
   infrastructure, Spark workflow, or IL rewrite map safety rules changed.
8. Run generated font cleanup retry validation with
   `tools\Test-FontPatchRemovalRetry.ps1` when font generation or build cleanup
   infrastructure changed.
9. Run `tools\Test-GameLoadMemoryPatch.ps1` when Game/ElfTools lifecycle
   rewriting, renderer redirects, save loading, or final managed-output copy
   behavior changed.
10. Confirm key artifacts:
   - `patch\Content\Text\English.xml` first line is `<english>`.
   - Generated resource, profession, discipline, and deposit aliases exist.
   - For `DynamicCjk`, `patch\AtG.RuntimeText.dll` and both
     `patch\Content\Fonts\NotoSansSC-*.ttf` files exist, while generated
     merged-font XNB files and `.atg-merged-fonts` do not.
   - For `MergedFonts`,
     `patch\Content\Images\Interface\Components\Fonts\.atg-merged-fonts`
     exists.
   - `patch\ElfTools.dll` exists when
     `translations\hardcoded-elftools-il-rewrite.json` is present.
   - `patch\Content\Images\Interface\ScreenSpecific\ClanCard\冶金\PortraitBackground_2.xnb`
     exists.
11. Read `patch\.atg-build-report.json` for the current build summary:
   text entry count, alias counts, rewrite map counts, font cache/budget, key
   artifacts, runtime redirect counts, renderer mode, atlas budget, load-memory
   patch status, and timing.
12. Install with `Install-ChinesePatch.ps1`. The installer automatically
   uninstalls any existing manifest-backed Chinese patch before copying the new
   patch, so removed patch files do not remain in the game directory.
13. Run `tools\Test-GameLaunch.ps1` as the install smoke test. By default this
   launches the game, reaches the main menu, captures a screenshot, and closes
   the process. It must not start a new random game unless the caller
   explicitly passes `-IncludeNewGame`; this keeps fixed-save UI tests from
   being affected by smoke-test state. Do not start a second smoke test while
   one is running; the script's single-instance lock should fail duplicate
   invocations before a second game process can launch.
14. Confirm the smoke result:
   - No new `Crash.AtGLog` timestamp.
   - No process exit before smoke-test cleanup.
   - No Windows Application Error, .NET Runtime, or WER event for
     `At The Gates.exe`.
   - Screenshot covers the complete game window.
   - The smoke test closes the game.
15. Carry forward timing evidence:
   - Build timing table from `Build-Patch.ps1`.
   - Build report path and key counts from `patch\.atg-build-report.json`.
   - Whether the IL rewrite tool used the repo-local dotnet DLL path.
   - Install duration and whether an old manifest-backed patch was uninstalled.
   - Smoke `StartupWaitSeconds` and total smoke duration.
   - If `-IncludeNewGame` was explicitly used, also record
     `NewGameSmokeSeconds` and `NewGameReadyMarker`. `NewGameSmokeSeconds`
     should normally stop when `Program.AtGLog` reaches
     `Controller - Giving Control to Human`, not when `Game World - New Game
     Complete` appears and not when the maximum timeout expires.

## Scope Boundary

`Test-GameLaunch.ps1` is the startup/main-menu smoke test by default. This
workflow proves the patched build can launch and render the main menu without
a smoke crash, but it does not prove random new-game entry, fixed-save loading,
in-game UI localization, hover text, or layout quality. Use `-IncludeNewGame`
only for workflows that explicitly need random new-game safety, and use
`test-and-loop.md` for fixed-save and interface-specific coverage.

## Stop Conditions

- Build or static validation fails.
- Install, uninstall-before-install, or required artifact validation fails.
- Smoke test updates `Crash.AtGLog`, shows a crash dialog, or captures an
  incomplete/invalid window.

## Outputs

- Ready-build handoff for `test-and-loop.md`: build result, install result,
  whether uninstall-before-install occurred, smoke result, smoke screenshot
  path, and `Crash.AtGLog` timestamp status.
- Timing handoff for build, install, and smoke stages.
- Failure evidence for `test-and-loop.md` if any step fails.

## Knowledge Updates

If this workflow discovers a new crash, missing artifact rule, or install
constraint, carry it forward as handoff evidence. Record it through
`update-knowledge.md` only after the test loop stops or passes.
