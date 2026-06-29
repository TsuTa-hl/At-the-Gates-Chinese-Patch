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
   - If `translations\hardcoded-ui-il-rewrite.json` is non-empty, the build
     must use the repo-local `.tools\dotnet\dotnet.exe` and run
     `AtG.IlRewrite.dll`. It must not produce or run `AtG.IlRewrite.exe`.
3. Run text tag validation.
4. Run generated alias validation.
5. Run font budget validation with `tools\Test-FontPatchBudget.ps1`.
6. Confirm key artifacts:
   - `patch\Content\Text\English.xml` first line is `<english>`.
   - Generated resource, profession, discipline, and deposit aliases exist.
   - `patch\Content\Images\Interface\Components\Fonts\.atg-merged-fonts`
     exists.
   - `patch\Content\Images\Interface\ScreenSpecific\ClanCard\冶金\PortraitBackground_2.xnb`
     exists.
7. Read `patch\.atg-build-report.json` for the current build summary:
   text entry count, alias counts, rewrite map counts, font cache/budget, key
   artifacts, and timing.
8. Install with `Install-ChinesePatch.ps1`. The installer automatically
   uninstalls any existing manifest-backed Chinese patch before copying the new
   patch, so removed patch files do not remain in the game directory.
9. Run `tools\Test-GameLaunch.ps1` as the install smoke test.
10. Confirm the smoke result:
   - No new `Crash.AtGLog` timestamp.
   - Screenshot covers the complete game window.
   - The smoke test closes the game.
11. Carry forward timing evidence:
   - Build timing table from `Build-Patch.ps1`.
   - Build report path and key counts from `patch\.atg-build-report.json`.
   - Whether the IL rewrite tool used the repo-local dotnet DLL path.
   - Install duration and whether an old manifest-backed patch was uninstalled.
   - Smoke `StartupWaitSeconds` and total smoke duration.

## Scope Boundary

`Test-GameLaunch.ps1` is the startup/main-menu smoke test. This workflow does
not prove new-game flow or in-game UI behavior unless a caller explicitly asks
for complete UI regression. `test-and-loop.md` consumes this workflow's result
instead of redefining or rerunning the same gates by default.

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
