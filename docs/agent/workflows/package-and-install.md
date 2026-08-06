# Workflow: Package, Install, and Smoke

## Purpose

Build the patch, refresh its installation, and prove it reaches the main menu.
Complete task cleanup first and reuse its handoff.

## Read First

- `docs/agent/knowledge-index.md`
- `docs/agent/operations/build-and-install.md`
- `docs/agent/crash-risks.md`

## Conditional Reading

- Read `text-sources/managed-patching.md` after XML/DLL/rewrite changes.
- Read only the matching crash-risk detail: `startup-and-content.md` for
  XML/settings/ClanCard output, `runtime-and-assets.md` for renderer or reload
  changes, or `managed-rewrites.md` for managed rewrite changes.
- Read `translations/composite-text-rules.json` after dynamic/rich-text/runtime
  display-map changes; generate a temporary `Composite` CSV only when needed.
- Read `operations/game-automation.md` only if smoke behavior itself fails.

## Steps

1. Close the game process.
2. Build with `tools\Build-Patch.ps1`.
3. Run required static gates: text tags, aliases, font budget, the
   current-patch install/uninstall completeness regression, and any test
   selected by the changed subsystem.
4. Refresh and validate the composite-rule JSON when composition sources or
   runtime display rules changed. Generate a temporary CSV only for inspection.
5. Confirm renderer and critical generated artifacts in the build report.
6. Install through `Install-ChinesePatch.ps1`; it refreshes only the prior
   manifest-backed patch.
7. Unless the user explicitly excludes testing, run one default
   `Test-GameLaunch.ps1` main-menu smoke. Do not pass `-IncludeNewGame` unless
   the selected test specifically requires it. If testing is excluded, still
   complete the install refresh in step 6 (it uninstalls the manifest-backed
   prior patch first), verify static artifacts, and record a static smoke.
8. Hand test/loop the build result, install refresh outcome, smoke or static
   smoke result, crash-log status when applicable, concise visual limitation,
   and timing.

## Failure

Build, install, smoke, settings, crash-log, or incomplete-window failures are
test-session failures. Record the concise evidence through the knowledge-update
workflow before returning to assess/fix.
