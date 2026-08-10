# Workflow: Package, Install, and Smoke

## Purpose

Build from the Steam-current development source, test the generated package,
install it transactionally, and prove that the game reaches the main menu.
Complete task cleanup first and reuse its handoff.

## Read First

- `docs/agent/knowledge-index.md`
- `docs/agent/operations/build-and-install.md`
- `docs/agent/crash-risks.md`

## Steps

1. Close the game process and identify the Steam-current original AtG directory.
2. From the current task handoff, pass only the files changed by this
   localization to the default `Localization` profile. For example:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Invoke-AtGVerification.ps1 `
     -GamePath '<AtG>' -Profile Localization -ChangedPath 'translations\zh-CN.json'
   ```

   It captures source inputs, builds into staging, runs the local core plus
   checks selected for those explicit paths, installs transactionally, and
   performs the one main-menu smoke. It never reads `git diff`; an unmapped
   path is reported and still receives the conservative local core checks.
   A documentation-only task uses the same selector without `-GamePath` and
   runs only its selected static documentation checks; it does not capture
   source, install, or smoke.
3. Use `-StaticOnly` only when the user explicitly excludes the real smoke.
   It still builds, tests, and performs the transaction-backed installation.
   It never enables black-box scenarios.
4. The installer validates only the AtG directory shape. It does not reject
   a player MOD or a changed game fingerprint; uninstall restores the exact
   state captured before installation.
5. Hand off the gate outcome, smoke evidence or its explicit limitation,
   recovery result, selected checks, and stage timings from its task-local
   `.tmp\runs\verification-*\verification-result.json` evidence.

## Failure

Any failed stage is a test-session failure. The unified gate restores its
pre-test game state on failure. Keep the task evidence and cleanup handoff;
use the knowledge-update workflow only if the failure establishes a durable
project fact, not as a test-results log.
