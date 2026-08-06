# Workflow: Publish the Player Release Branch

## Purpose

The codex/release-chinese-patch branch is a player-facing snapshot, not a
development branch. It intentionally excludes source catalogs, translation
rules, tests, build tools, agent instructions, review evidence, and all other
development material.

The release root contains only:

- README.md: player-only installation, uninstall, support, and licensing
  information;
- Install-ChinesePatch.ps1 and Uninstall-ChinesePatch.ps1;
- patch/: every generated patch artifact.

The two entry scripts are self-contained in the release snapshot. The export
step inlines their small runtime helpers so a player never needs tools/.

## Prerequisites

1. Merge the intended development/publish branch into main first.
2. Record the exact main commit SHA used as the release source.
3. Run Test-ReleasePackage.ps1; do not publish a package that fails its
   whitelist, PowerShell parse, manifest-coverage, or fake-game rollback
   checks.

## Generate the Snapshot

From the synchronized development checkout, export a disposable release tree:

~~~powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-ReleasePackage.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Export-ReleasePackage.ps1 -OutputPath .\.tmp\release-package
~~~

Inspect the output before publishing. It must contain no tools/, docs/,
translations/, source/, .cache/, or development README content.

## Update codex/release-chinese-patch

The release branch has an independent, minimal history. Initialize a repository
inside the generated snapshot and push it as the branch root:

~~~powershell
git -C .\.tmp\release-package init
git -C .\.tmp\release-package add --all
git -C .\.tmp\release-package commit -m "Release Chinese patch"
git -C .\.tmp\release-package remote add origin https://github.com/TsuTa-hl/At-the-Gates-Chinese-Patch.git
git -C .\.tmp\release-package fetch origin codex/release-chinese-patch
git -C .\.tmp\release-package push --force-with-lease origin HEAD:codex/release-chinese-patch
~~~

Force-with-lease is intentional: the branch is regenerated from the latest
merged main and must contain only the player-release whitelist. It protects
against overwriting a release update that appeared after the fetch. If the
lease rejects the push, inspect the newer remote release commit, regenerate
from the intended main, and retry; never use a blind force push.

## Completion Evidence

Record the source main SHA, release branch SHA, whitelist result, script parse
result, full patch-file count, and fake-game install/uninstall result. The
release branch is complete only when its tree has exactly the whitelist above
and points at the generated snapshot for that merged main.

## Validation Record: 2026-08-06

The self-contained export passed its smoke regression with 58 patch files: the
whitelist was exact, every exported patch artifact matched its source SHA-256,
both inlined entry scripts parsed successfully, and a fake-game installation
was restored byte-for-byte by the exported uninstaller. No black-box scenario
was run for this packaging-only change.
