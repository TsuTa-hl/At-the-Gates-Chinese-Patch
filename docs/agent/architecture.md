# Patch Architecture

## Development inputs

`Initialize-AtGSource.ps1 -GamePath <Steam original> -Refresh` copies the
current original files required by the build into ignored `source/`. It refuses
an active Chinese-patch transaction so patched output cannot become source
input. The source manifest records provenance only; it is never used to reject
a player's installation.

## Atomic build

`Build-Patch.ps1` writes every generated file to a sibling staging directory.
The build contract validates required inputs and output hashes for text, managed
rewrites, runtime components, config nodes, and ClanCard aliases. Only a fully
validated staging directory replaces `patch/`; a failed build keeps the prior
patch intact. After that swap, it refreshes the source-derived composite catalog
so runtime display-map entries and durable KnownText locators cannot drift.

## Player transaction

The installer identifies AtG structurally, snapshots every affected file before
copying, writes a prepared manifest before the first overwrite, and verifies
every installed hash. The uninstaller restores those snapshots and preserves
its recovery data until every restore is verified. Legacy ownership rules cover
historic patch-only artifacts and ClanCard aliases.

## Verification and release

`Invoke-AtGVerification.ps1` defaults to the `Localization` profile. It uses
only explicit `ChangedPath` values from the task handoff, never the dirty
worktree diff, to select the local core and affected text, composition, managed,
font, automation, or documentation checks. Unknown paths are recorded and keep
the core checks. Every player-visible localization still captures source,
builds, installs transactionally, and runs the main-menu smoke unless
`-StaticOnly` is specified.

When the explicit paths are classified documentation paths only,
`Localization` instead uses a no-game static branch: no source capture, build,
installation, or smoke. A mixed or unclassified set remains on the normal
conservative game gate.

`Release` is selected only by an explicit publication request. It retains the
complete static suite, full catalog/progress audits, package and transaction
recovery regressions, then performs the same real transaction and smoke. Both
profiles restore locked dependencies before they capture game state, so a
tooling-only failure never touches the selected game directory. A failed
transaction restores captured files, manifest, and backup tree. The gate writes
its selected checks, outcomes, and phase timings to task-local `.tmp` evidence
for cleanup handoff rather than a test-result knowledge document.

`Publish-AtGRelease.ps1` accepts only clean, synchronized `main`; it runs the
full gate, exports self-contained scripts through an AST-checked dependency
manifest, and pushes a new independent minimal history with
`--force-with-lease`.
