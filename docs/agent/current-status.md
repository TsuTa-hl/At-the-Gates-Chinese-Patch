# Current Status Contract

The repository does not treat dated prose as verification evidence. The current
state is established only by a fresh `Invoke-AtGVerification.ps1` result and
its resulting build report, xUnit output, transaction manifest, and smoke
artifact.

- Development baseline: restored current Steam original build.
- Default scope: build, static xUnit suite, fake-game package round trip,
  transactional installation, and main-menu smoke.
- Black-box UI coverage: opt-in and tracked in its owning scenario files.
- Static-only result: explicitly limited; it is not visual verification.
- Historical localization safety: retained only in
  `translations/localization-safety-registry.json`.
- This file records only repository-wide refactor and verification state. It
  does not record individual localization repairs, case-specific black-box
  results, or user-led manual-test pending items.

## Current refactor verification

- DynamicCjk build and build-report contract: passed.
- Source-capture and verification-preflight refactor: full locked xUnit suite
  passed.
- Interface progress refactor: the source-catalog audit rejects a partial
  catalog import instead of accepting incomplete input.
- Transaction and release-package refactor: fake-game refresh/recovery,
  uninstall restoration, and self-contained package checks passed.
- Unified verification, 2026-08-07: source capture, atomic DynamicCjk build,
  locked static suites, transactional installation, and the xUnit-owned
  main-menu smoke passed against the restored Steam baseline. The transaction
  manifest verified every installed patch hash and no new crash log was
  written.

Record a new current-status entry only for a repository-wide refactor or
verification-contract change. Keep individual localization fixes and any
manual-test status in their current task handoff or scenario owner.
