# Build, Transaction, and Verification

Use the unified gate for a player-visible localization change. Pass only the
paths explicitly named in the current task handoff:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Invoke-AtGVerification.ps1 `
  -GamePath 'D:\SteamLibrary\steamapps\common\Jon Shafer''s At the Gates' `
  -Profile Localization -ChangedPath 'translations\zh-CN.json'
```

`Localization` is the default profile. It performs all of the following in
order:

1. Refuses to run while an AtG process is active, preventing mutation of a
    possibly unsaved game.
2. Restores locked test dependencies before touching the selected game
   directory, so a package-source failure cannot require game recovery.
3. Captures restored current-Steam inputs into `source/`.
4. Builds to staging and atomically replaces `patch/` only after the build
   contract and report validate.
5. Runs the local C# core plus only the PowerShell checks selected by the
   declared path categories. Text/XML, composition/runtime, managed rewrite,
   font, automation, and documentation changes each select their own checks.
   An unclassified path is reported and keeps the local core; it is never
   silently skipped.
6. Installs transactionally to the selected AtG directory.
7. Runs the xUnit-owned main-menu smoke and leaves the verified patch installed.

When every explicit path is a classified documentation path, `Localization`
uses a documentation-only static branch instead: it needs no `-GamePath`, runs
only the selected documentation checks, and does not capture source, build,
install, or smoke. A mixed or unmapped path set uses the normal game gate.

`Release` is not a normal-development default. It is used only by an explicit
Codex publication request (and by `Publish-AtGRelease.ps1`), and runs every
script and .NET group: full catalog/progress audits, package checks, fake
installation/uninstallation recovery matrices, and toolchain regressions
before the same real transaction and smoke. Its transaction fixtures declare
the stopped-game prerequisite in `tools/power-shell-test-suite.json`.

The gate records source capture, build, each selected test group, installation,
and smoke timings together with the selected checks in
`.tmp\runs\verification-*\verification-result.json`. Workspace cleanup retains
that JSON as a text handoff summary. This is task evidence, not a knowledge
document.

`-StaticOnly` is the only explicit way to omit the real smoke. It still builds,
runs the static suite, and installs the transaction, but its result must be
reported as a visual limitation.

## Direct debugging commands

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Initialize-AtGSource.ps1 -GamePath '<AtG>' -Refresh
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Build-Patch.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\Install-ChinesePatch.ps1 -GamePath '<AtG>' -NoInstallNotice
powershell -NoProfile -ExecutionPolicy Bypass -File .\Uninstall-ChinesePatch.ps1 -GamePath '<AtG>'
& .\.tools\dotnet\dotnet.exe test .\AtG.Patch.sln -c Release --no-restore -p:NuGetAudit=false
```

The direct solution command is a static diagnostic only. It does not select a
`ChangedPath`, install the patch, or run the real-game smoke; use the unified
gate for a normal localization task or an explicit release gate.

`-NoInstallNotice` is required for noninteractive agent refreshes because the
default public installer deliberately waits for acknowledgement of its notice.
It does not relax any transaction or game-process safety check; player-facing
manual installation continues to show the notice by default.

The direct installer accepts any structurally valid AtG directory; it never
checks a Steam build fingerprint. It records actual pre-install contents,
including a MOD file that shares a patched path. Uninstall validates the
restored bytes before deleting transaction data and retains recovery data on
any ambiguity.

`Test-GameLaunch.ps1` is main-menu smoke by default. Do not add
`-IncludeNewGame` to normal verification; that is black-box coverage.
