# Workflow: Publish the Player Release Branch

Run this workflow only from a clean local `main` that exactly matches
`origin/main`.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Publish-AtGRelease.ps1 -GamePath '<Steam AtG original>'
```

The command explicitly invokes the `Release` verification profile. It runs the
complete static suite, whole-catalog and interface audits, fake package and
transaction regressions, then the real transactional install and main-menu
smoke. The release-only transaction fixtures require the AtG process to be
stopped. It then exports a self-contained package, validates its strict
whitelist, creates one independent release commit whose message records the
source `main` SHA and patch count, and pushes it to
`codex/release-chinese-patch` with `--force-with-lease`.

Do not invoke `Release` for an ordinary player-visible localization repair;
normal work uses the `Localization` profile in `package-and-install.md`.

The published tree contains only:

- `README.md`
- `Install-ChinesePatch.ps1`
- `Uninstall-ChinesePatch.ps1`
- `patch/`

If the lease fails, do not use plain force push. Inspect the new remote release
head, synchronize `main`, rerun the gate, and publish again.
