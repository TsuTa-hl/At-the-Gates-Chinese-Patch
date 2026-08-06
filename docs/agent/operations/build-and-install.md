# Build and Installation Operations

Read this file for any patch build, install, uninstall, smoke, or artifact
check. It supplements the invariants in `../operations.md`.

## Commands

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Build-Patch.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\Install-ChinesePatch.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\Uninstall-ChinesePatch.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-PatchUninstallCompleteness.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-GameLaunch.ps1
```

`Install-ChinesePatch.ps1` refreshes a manifest-backed previous patch before
copying the new one. Build and static checks must complete before that refresh.
Before any patch file is replaced, a direct installation shows the permission
notice: free/non-commercial, unofficial fan-made, no original-game-file
redistribution, legitimate-copy requirement, Conifer Games support limit,
project-owned crash reporting, and revocable good-faith permission. Automated
test callers pass `-NoInstallNotice`; public installation does not.
The 2026-08-01 notice regression verifies the Chinese permission declaration,
the default WinForms popup path, the non-interactive refresh, and the uninstall
preview without `System.Object[]` or a trailing empty object. The popup itself
was not manually dismissed against a live installation.
Its internal uninstall explicitly preserves save names. A direct
`Uninstall-ChinesePatch.ps1` run first removes non-ASCII characters from each
`.AtGSave` filename so original English/Latin menu fonts cannot crash while
enumerating saves. It never changes save contents; collision-safe ASCII suffixes
are added when necessary, then an informational OK-only popup lists the changes.
The 2026-07-30 fake-game regression covers direct-uninstall removal, collision
suffixing, empty-name fallback, original-file restoration, and the refresh
bypass; it intentionally does not rename a live player's saves during testing.
Every install now prepares a schema-2 manifest before the first patch copy,
recording every generated patch file together with its original and patch hashes.
Only after every copy hash verifies does it mark the manifest installed. Direct
uninstall validates each restored/deleted path before removing that manifest.
It also merges the backup inventory and known runtime-only artifacts, so a
legacy or incomplete manifest cannot leave an original DLL/XML file or the
AtG.RuntimeText mapping behind. Test-PatchUninstallCompleteness.ps1 enumerates
the live patch tree dynamically; any future translated artifact therefore has
to be represented in the install manifest and be restored or removed by the
fake-game round trip.

## Required Gates

1. Close the game process.
2. Build the patch and inspect `patch\.atg-build-report.json`.
3. Run the text-tag, generated-alias, font-budget, current-patch
   install/uninstall completeness, and affected subsystem checks named by
   package-and-install.md.
4. Confirm `patch\Content\Text\English.xml` starts with `<english>`.
5. Install the patch. `Install-ChinesePatch.ps1` first uninstalls its
   manifest-backed previous installation, so an explicit separate uninstall is
   not required for a normal refresh.
6. Unless the user explicitly excludes testing, run the default main-menu
   smoke once. When testing is excluded, do not launch the game: still build,
   run static gates, refresh the installation, and verify the build report,
   installed manifest, runtime-DLL hash, and runtime-map counts as a static
   smoke.
7. Record build, install, smoke or static-smoke, and manifest-refresh timings
   in the handoff.

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
