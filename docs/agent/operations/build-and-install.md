# Build and Installation Operations

Read this file for any patch build, install, uninstall, smoke, or artifact
check. It supplements the invariants in `../operations.md`.

## Commands

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Build-Patch.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\Install-ChinesePatch.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\Uninstall-ChinesePatch.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-GameLaunch.ps1
```

`Install-ChinesePatch.ps1` refreshes a manifest-backed previous patch before
copying the new one. Build and static checks must complete before that refresh.
Before any patch file is replaced, a direct installation shows the permission
notice: free/non-commercial, unofficial fan-made, no original-game-file
redistribution, legitimate-copy requirement, Conifer Games support limit,
project-owned crash reporting, and revocable good-faith permission. Automated
test callers pass `-NoInstallNotice`; public installation does not.
The 2026-07-30 notice regression verifies every required permission phrase,
the default WinForms popup path, and a non-interactive manifest refresh. The
popup itself was not manually dismissed against a live installation.
Its internal uninstall explicitly preserves save names. A direct
`Uninstall-ChinesePatch.ps1` run first removes non-ASCII characters from each
`.AtGSave` filename so original English/Latin menu fonts cannot crash while
enumerating saves. It never changes save contents; collision-safe ASCII suffixes
are added when necessary, then an informational OK-only popup lists the changes.
The 2026-07-30 fake-game regression covers direct-uninstall removal, collision
suffixing, empty-name fallback, original-file restoration, and the refresh
bypass; it intentionally does not rename a live player's saves during testing.

## Required Gates

1. Close the game process.
2. Build the patch and inspect `patch\.atg-build-report.json`.
3. Run the text-tag, generated-alias, font-budget, and affected subsystem
   checks named by `package-and-install.md`.
4. Confirm `patch\Content\Text\English.xml` starts with `<english>`.
5. Install the patch, then run the default main-menu smoke test once.
6. Record build, install, smoke, and manifest-refresh timings in the handoff.

`Test-GameLaunch.ps1` is a main-menu smoke test by default. It must not create
a random game unless the caller explicitly requires `-IncludeNewGame`.

## Renderer Artifacts

The default `DynamicCjk` package requires `AtG.RuntimeText.dll` and both
bundled Noto Sans SC font files. It must not contain generated merged-font XNB
files. `MergedFonts` is rollback-only; its marker and XNB budget are validated
by the font gate.

`AtG.RuntimeText` targets .NET Framework 4.0. Runtime-localization changes
must use APIs available there; do not introduce `Span` APIs or LINQ extension
calls without the corresponding compatible implementation/import and a full
`Build-Patch.ps1` verification.

When a task explicitly excludes game launch, record the result as a **static
smoke** rather than a UI pass. Verify the build report, installed manifest,
runtime-DLL hash, and generated runtime-map counts; state the missing visual
verification as a limitation in the final handoff.
